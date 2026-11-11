{ ... }:
{
  flake.nixosModules.paperclipContainer =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      dir = "stacks/paperclip";
      dataDir = "/var/lib/${dir}";
      composeFile = "/etc/${dir}/compose.yaml";
      port = 3100;

      # Paperclip's agents are CLI subprocesses (claude, codex, ...) running with
      # permission prompts bypassed, as the same uid as the server. The container
      # is the sandbox, so it gets its own uid: the image's default 1000 is
      # isaac on this host, who is in the docker group and so root in all but
      # name.
      user = "paperclip";

      # Its own bridge on a subnet outside 172.16/12, so caddy's lanVhosts gate
      # (which trusts docker bridges) 403s it too. The firewall chain below is
      # the real boundary; this is belt and braces.
      bridge = "br-paperclip";
      subnet = "10.200.0.0/24";
      gateway = "10.200.0.1";

      # Gitea publishes 3000 on every host address, so the agents reach it
      # through their own gateway; docker DNATs that to the gitea container.
      # Plain http, but the hop never leaves this host.
      giteaUrl = "http://${gateway}:3000";
      giteaTokenPath = "/run/secrets/gitea-token";

      # git reads /etc/gitconfig whatever env Paperclip hands an agent, so the
      # wiring holds for every agent without per-agent setup. The rewrites send
      # every clone URL Gitea advertises (https via caddy, ssh on 222) to the
      # one address the firewall lets through. Gitea resolves a token password
      # to its owner and ignores the username.
      gitconfig = pkgs.writeText "paperclip-gitconfig" ''
        [url "${giteaUrl}/"]
        	insteadOf = https://gitea.luna.monkeymeat.xyz/
        	insteadOf = ssh://git@gitea.luna.monkeymeat.xyz:222/
        	insteadOf = git@gitea.luna.monkeymeat.xyz:
        [credential "${giteaUrl}"]
        	username = paperclip
        	helper = "!f() { if [ \"$1\" = get ]; then echo \"password=$(cat ${giteaTokenPath})\"; fi; }; f"
      '';

      # Static musl build: the image is Debian and has no /nix/store to resolve
      # a dynamically linked nixpkgs binary against.
      giteaMcp = "${pkgs.pkgsStatic.gitea-mcp-server}/bin/gitea-mcp";

      # Taken with the container down, before every start, so an unattended
      # `:latest` migration (docker-auto-update restarts this unit) always has a
      # pre-migration copy. Workspaces and project checkouts are excluded:
      # they are bulky and their source of truth is Gitea.
      snapDir = "/mnt/raidDrive/paperclip-snapshots";
      keepSnapshots = 3;

      # Each CLI keeps its own MCP config in HOME (/paperclip), which the CLIs
      # rewrite themselves; going through their own `mcp add` avoids fighting
      # them. Remove-then-add keeps it idempotent and picks up changed args.
      registerMcp = ''
        claude mcp remove -s user gitea >/dev/null 2>&1
        claude mcp add -s user gitea \
          --env GITEA_ACCESS_TOKEN_FILE=${giteaTokenPath} \
          -- /usr/local/bin/gitea-mcp -t stdio -H ${giteaUrl}
        codex mcp remove gitea >/dev/null 2>&1
        codex mcp add gitea \
          --env GITEA_ACCESS_TOKEN_FILE=${giteaTokenPath} \
          -- /usr/local/bin/gitea-mcp -t stdio -H ${giteaUrl}
      '';
    in
    {
      virtualisation.docker.enable = true;

      users.users.${user} = {
        isSystemUser = true;
        group = user;
      };
      users.groups.${user} = { };

      # 0700: holds the embedded Postgres, secrets/master.key (decrypts every
      # key stored in the UI) and the CLIs' logins.
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0700 ${user} ${user} -"
      ];

      sops.secrets.paperclipAuthSecret.restartUnits = [ "paperclip.service" ];
      sops.secrets.paperclipToolActionSigningSecret.restartUnits = [ "paperclip.service" ];
      # Owned by the container's uid so it can be bind-mounted read-only and
      # read by git and gitea-mcp at use time, never sitting in an env var.
      sops.secrets.paperclipGiteaToken = {
        owner = user;
        restartUnits = [ "paperclip.service" ];
      };

      sops.templates."paperclip.env" = {
        content = ''
          BETTER_AUTH_SECRET=${config.sops.placeholder.paperclipAuthSecret}
          PAPERCLIP_TOOL_ACTION_SIGNING_SECRET=${config.sops.placeholder.paperclipToolActionSigningSecret}
        '';
        restartUnits = [ "paperclip.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        networks:
          default:
            enable_ipv6: false
            driver_opts:
              com.docker.network.bridge.name: ${bridge}
            ipam:
              config:
                - subnet: ${subnet}
                  gateway: ${gateway}

        services:
          paperclip:
            image: ghcr.io/paperclipai/paperclip:latest
            container_name: paperclip
            restart: unless-stopped
            stop_grace_period: 90s

            # The entrypoint starts as root, remaps the node user to
            # USER_UID/USER_GID, chowns /paperclip on mismatch and gosu-drops.
            # These are exactly what that needs; KILL lets tini (root) signal
            # the node-owned server so embedded Postgres shuts down cleanly.
            #
            # The image's /app is owned by uid 1000 and the entrypoint only
            # re-owns /paperclip, yet embedded Postgres creates its lib
            # symlinks under /app at every start: with USER_UID remapped it
            # dies on EACCES. Re-owning just those directories (not files, so
            # overlayfs copies up no data) fixes it; `;` not `&&` so a moved
            # path upstream surfaces as that same EACCES rather than a silent
            # no-start. Overriding entrypoint drops the image CMD, hence command.
            entrypoint:
              - /usr/bin/tini
              - -s
              - --
              - sh
              - -c
              - find -L /app/node_modules/.pnpm/embedded-postgres@*/node_modules/@embedded-postgres -type d -exec chown "$$USER_UID:$$USER_GID" {} +; exec docker-entrypoint.sh "$$@"
              - sh
            command: [node, server/dist-runtime/index.mjs]
            cap_drop: [ALL]
            cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]
            security_opt: ["no-new-privileges:true"]

            # Explicit, so a tailscale or pihole resolver on the host never
            # becomes one the firewall below silently blocks.
            dns: [1.1.1.1, 8.8.8.8]

            environment:
              USER_UID:
              USER_GID:
              HOST: "0.0.0.0"
              PAPERCLIP_DEPLOYMENT_MODE: authenticated
              PAPERCLIP_DEPLOYMENT_EXPOSURE: private
              # Also the auth base URL and the allowed-hostname default.
              PAPERCLIP_PUBLIC_URL: https://paperclip.${config.hostConfig.lanVhosts.httpsDomain}
              # caddy arrives through docker-proxy, i.e. from the gateway.
              TRUST_PROXY: ${gateway}

            env_file:
              - path: ${config.sops.templates."paperclip.env".path}
                format: raw

            ports:
              - "127.0.0.1:${toString port}:3100"

            volumes:
              - ${dataDir}:/paperclip
              - ${gitconfig}:/etc/gitconfig:ro
              - ${giteaMcp}:/usr/local/bin/gitea-mcp:ro
              - ${config.sops.secrets.paperclipGiteaToken.path}:${giteaTokenPath}:ro

            # pids lives here, not as top-level pids_limit: compose rejects the
            # two together once deploy.resources.limits exists at all.
            deploy:
              resources:
                limits:
                  memory: 8G
                  cpus: "4.0"
                  pids: 2048
      '';

      # Egress sandbox: the internet stays open (model APIs, npm/pip, web), but
      # nothing on this host, the LAN, other containers or the tailnet is
      # reachable except Gitea's web port.
      #
      # mangle PREROUTING because it is the one hook that sees the container's
      # packets after conntrack (so replies to caddy's proxied requests pass as
      # ESTABLISHED) yet before docker's DNAT (so the destination is still the
      # address the agent dialled, not the gitea container behind it). Matching
      # on the bridge interface rather than the subnet means a spoofed source
      # address changes nothing, and it sits ahead of tailscale's ts-forward,
      # which would otherwise ACCEPT anything bound for tailscale0.
      networking.firewall.extraCommands = ''
        iptables -t mangle -N paperclip-egress 2>/dev/null || iptables -t mangle -F paperclip-egress
        iptables -t mangle -A paperclip-egress -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
        iptables -t mangle -A paperclip-egress -d ${gateway} -p tcp --dport 3000 -j RETURN
        iptables -t mangle -A paperclip-egress -m addrtype --dst-type LOCAL -j DROP
        iptables -t mangle -A paperclip-egress -m addrtype --dst-type BROADCAST -j DROP
        iptables -t mangle -A paperclip-egress -m addrtype --dst-type MULTICAST -j DROP
        for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
          iptables -t mangle -A paperclip-egress -d "$net" -j DROP
        done
        iptables -t mangle -C PREROUTING -i ${bridge} -j paperclip-egress 2>/dev/null \
          || iptables -t mangle -I PREROUTING -i ${bridge} -j paperclip-egress
      '';
      networking.firewall.extraStopCommands = ''
        iptables -t mangle -D PREROUTING -i ${bridge} -j paperclip-egress 2>/dev/null || true
      '';

      systemd.services.paperclip = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        path = with pkgs; [
          docker
          gnutar
          gzip
          curl
        ];
        unitConfig.RequiresMountsFor = snapDir;

        preStart = ''
          set -eu
          install -d -m 0700 ${snapDir}
          inst=${dataDir}/instances/default
          if [ -d "$inst" ]; then
            tar -C "$inst" --exclude=./workspaces --exclude=./projects --exclude=./logs \
              -czf ${snapDir}/$(date +%Y%m%dT%H%M%S).tar.gz .
            ls -1t ${snapDir}/*.tar.gz | tail -n +${toString (keepSnapshots + 1)} | xargs -r rm --
          fi
        '';

        script = ''
          USER_UID=$(id -u ${user}) USER_GID=$(id -g ${user}) \
            docker compose -f ${composeFile} up --remove-orphans
        '';

        preStop = ''
          docker compose -f ${composeFile} down
        '';

        # Waits for the server rather than the container: the entrypoint remaps
        # node's uid first, and an exec that beats it would write the CLIs'
        # config as uid 1000. Failure only costs the gitea MCP, so it never
        # fails the unit.
        postStart = ''
          for _ in $(seq 150); do
            curl -so /dev/null http://127.0.0.1:${toString port}/ && break
            sleep 2
          done
          docker exec -u node paperclip sh -c ${lib.escapeShellArg registerMcp} \
            || echo "paperclip: gitea MCP registration failed" >&2
        '';

        serviceConfig = {
          Restart = "always";
          TimeoutStartSec = 600;
          # compose down waits out the 90s stop_grace_period.
          TimeoutStopSec = 150;
        };

        restartTriggers = [
          config.environment.etc."${dir}/compose.yaml".source
        ];
      };

      hostConfig.lanVhosts.services.paperclip.upstream = "127.0.0.1:${toString port}";
    };
}
