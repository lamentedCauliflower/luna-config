{ inputs, ... }:
{
  # Paperclip and its agents in a NixOS microVM, so agents get nix, devenv and
  # a real docker daemon. Why a VM and not the docker stack it replaces:
  # docs/adr/0009-paperclip-in-a-nixos-microvm.md.
  flake.nixosModules.paperclipVm =
    { config, lib, pkgs, ... }:
    let
      name = "paperclip";
      dataDir = "/var/lib/stacks/paperclip";
      port = 3100;
      sshPort = 2222;

      # Paperclip is upstream's image's /app, copied out on luna and run in the
      # guest. Not the npm package: that skips the pnpm patches and overrides
      # upstream ships (claude-agent-acp's isolation, its SDK pin, acpx,
      # embedded-postgres), and the unpinned SDK's bundled Claude Code was too
      # old for current models. Bump tag and digest together to upgrade; the
      # embedded Postgres in the data dir must stay on the major (18).
      image = "ghcr.io/paperclipai/paperclip:2026.1106.0@sha256:d6584f05cf57a4b26c117eb083725f18c1fe69ddafa7d16c9f8cce83f6fa17da";
      app = "${dataDir}/.app";
      # Root on luna, with the VM down. luna's docker already caches the image.
      installApp = pkgs.writeShellScript "paperclip-install-app" ''
        set -eu
        PATH=${lib.makeBinPath [ config.virtualisation.docker.package pkgs.coreutils ]}
        [ "$(cat ${app}/.image 2>/dev/null)" = ${image} ] && exit 0
        docker pull -q ${image}
        id=$(docker create ${image})
        trap 'docker rm -f "$id" >/dev/null' EXIT
        rm -rf ${app}.new
        docker cp "$id:/app" ${app}.new
        # Embedded Postgres links its libs inside its package at every start.
        chown -R ${toString uid}:${toString gid} ${app}.new
        echo ${image} > ${app}.new/.image
        rm -rf ${app}
        mv ${app}.new ${app}
      '';

      # The ids the docker stack wrote the data dir with. The share passes them
      # through unchanged, so the guest user must keep them.
      user = "paperclip";
      uid = 987;
      gid = 983;

      # SLiRP user networking on the subnet the docker bridge had, with luna as
      # 10.200.0.1. That address, the /usr/local/bin paths, tcp://dind:2375 and
      # /run/secrets/gitea-token are stored in Paperclip's database (Local
      # environment env vars, the gitea Tools connection, a company secret), so
      # the guest keeps all of them valid rather than editing the DB.
      subnet = "10.200.0.0/24";
      gateway = "10.200.0.1";
      giteaUrl = "http://${gateway}:3000";
      giteaTokenPath = "/run/secrets/gitea-token";

      # Host sops secrets handed to the guest as systemd credentials. qemu
      # reads them as the microvm user at start.
      credentials = {
        auth-secret = "paperclipAuthSecret";
        tool-action-signing-secret = "paperclipToolActionSigningSecret";
        gitea-token = "paperclipGiteaToken";
      };

      # Taken with the VM down, before every start, so a version bump always
      # has a pre-migration copy. Workspaces and project checkouts are
      # excluded: they are bulky and their source of truth is Gitea.
      snapDir = "/mnt/raidDrive/paperclip-snapshots";
      keepSnapshots = 3;
      snapshot = pkgs.writeShellScript "paperclip-snapshot" ''
        set -eu
        PATH=${lib.makeBinPath (with pkgs; [ coreutils findutils gnutar gzip ])}
        install -d -m 0700 ${snapDir}
        inst=${dataDir}/instances/default
        if [ -d "$inst" ]; then
          tar -C "$inst" --exclude=./workspaces --exclude=./projects --exclude=./logs \
            -czf ${snapDir}/$(date +%Y%m%dT%H%M%S).tar.gz .
          ls -1t ${snapDir}/*.tar.gz | tail -n +${toString (keepSnapshots + 1)} | xargs -r rm --
        fi
      '';

      hostConfig = config;
    in
    {
      imports = [ inputs.microvm.nixosModules.host ];

      users.users.${user} = {
        inherit uid;
        isSystemUser = true;
        group = user;
      };
      users.groups.${user}.gid = gid;

      # 0700: holds the embedded Postgres, secrets/master.key (decrypts every
      # key stored in the UI) and the CLIs' logins.
      systemd.tmpfiles.rules = [ "d ${dataDir} 0700 ${user} ${user} -" ];

      sops.secrets = lib.mapAttrs' (
        _: secret:
        lib.nameValuePair secret {
          owner = "microvm";
          restartUnits = [ "microvm@${name}.service" ];
        }
      ) credentials;

      microvm.vms.${name}.config =
        { pkgs, ... }:
        {
          system.stateVersion = "25.11";
          networking.hostName = name;

          microvm = {
            vcpu = 8;
            mem = 12288;
            # Free page reporting hands idle guest memory back to luna, so mem
            # is a ceiling rather than a reservation.
            balloon = true;

            # Data stays where the docker stack kept it: host backups and the
            # snapshot above keep working unchanged.
            shares = [
              {
                proto = "virtiofs";
                tag = "paperclip";
                source = dataDir;
                mountPoint = "/paperclip";
              }
            ];
            # The guest's own closure boots from an image (storeOnDisk), so the
            # host store is never visible to agents. Their builds land here.
            # ponytail: the nix db is on the tmpfs root, so these paths are
            # unregistered after each VM restart and get refetched; persist
            # /nix/var too if that churn ever matters.
            writableStoreOverlay = "/nix/.rw-store";
            volumes = [
              {
                image = "nix-rw.img";
                mountPoint = "/nix/.rw-store";
                size = 100 * 1024;
              }
              {
                image = "docker.img";
                mountPoint = "/var/lib/docker";
                size = 100 * 1024;
              }
            ];

            credentialFiles = lib.mapAttrs (_: s: hostConfig.sops.secrets.${s}.path) credentials;

            # Hand-written because microvm.interfaces can't set SLiRP's subnet.
            # A share forces PCI devices, hence virtio-net-pci. No IPv6: the
            # host egress rules below are IPv4.
            qemu.extraArgs = [
              "-netdev"
              (lib.concatStringsSep "," [
                "user"
                "id=n0"
                "net=${subnet}"
                "host=${gateway}"
                "ipv6=off"
                "hostfwd=tcp:127.0.0.1:${toString port}-:${toString port}"
                "hostfwd=tcp:127.0.0.1:${toString sshPort}-:22"
              ])
              "-device"
              "virtio-net-pci,netdev=n0,mac=02:00:00:00:0c:01"
            ];
          };

          # SLiRP would forward DNS to luna's resolver, which is tailscale's
          # 100.100.100.100 and blocked by the egress rules.
          networking.nameservers = [
            "1.1.1.1"
            "8.8.8.8"
          ];
          systemd.network.networks."99-ethernet-default-dhcp".dhcpV4Config.UseDNS = false;
          networking.hosts."127.0.0.1" = [ "dind" ];
          networking.firewall.allowedTCPPorts = [
            port
            22
          ];

          # Admin shell: `ssh -p ${toString sshPort} root@127.0.0.1` on luna.
          services.openssh.enable = true;
          users.users.root.openssh.authorizedKeys.keyFiles = [ ./ssh/isaac_ed25519.pub ];

          users.users.${user} = {
            inherit uid;
            isSystemUser = true;
            group = user;
            home = "/paperclip";
            extraGroups = [ "docker" ];
          };
          users.groups.${user}.gid = gid;

          # The guest is the sandbox, so agents are trusted by its own daemon:
          # devenv's cachix and `nix shell` work without host involvement.
          nix.settings = {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
            trusted-users = [
              "root"
              user
            ];
          };
          nix.gc = {
            automatic = true;
            options = "--delete-older-than 7d";
          };

          # Prebuilt binaries from npm: embedded Postgres, the Paperclip runner,
          # and whatever agents `npm install -g`.
          programs.nix-ld.enable = true;

          virtualisation.docker = {
            enable = true;
            # tcp://dind:2375 is what the Local environment's DOCKER_HOST says.
            # Loopback only, and everyone in the guest is an agent anyway.
            listenOptions = [
              "/run/docker.sock"
              "127.0.0.1:2375"
            ];
          };

          environment.systemPackages = with pkgs; [
            curl
            devenv
            direnv
            gh
            git
            gitea-mcp-server
            nodejs_24
            python3
            ripgrep
            wget
            inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];

          # git reads /etc/gitconfig whatever env Paperclip hands an agent. The
          # rewrites send every clone URL Gitea advertises to the one address
          # the egress rules let through; Gitea maps a token password to its
          # owner and ignores the username.
          environment.etc.gitconfig.text = ''
            [url "${giteaUrl}/"]
            	insteadOf = https://gitea.luna.monkeymeat.xyz/
            	insteadOf = ssh://git@gitea.luna.monkeymeat.xyz:222/
            	insteadOf = git@gitea.luna.monkeymeat.xyz:
            [credential "${giteaUrl}"]
            	username = paperclip
            	helper = "!f() { if [ \"$1\" = get ]; then echo \"password=$(cat ${giteaTokenPath})\"; fi; }; f"
          '';

          # Container-era paths still in Paperclip's database: the Local
          # environment's PATH starts with /usr/local/bin, the gitea Tools
          # connection runs /usr/local/bin/gitea-mcp, and
          # TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE names the rootless socket.
          # /app: the image's runtime bundle hardcodes paths under it.
          systemd.tmpfiles.rules = [
            "L+ /app - - - - /paperclip/.app"
            "L+ /usr/local/bin - - - - /run/current-system/sw/bin"
            "d /run/user/${toString uid} 0700 ${user} ${user} -"
            "L+ /run/user/${toString uid}/docker.sock - - - - /run/docker.sock"
          ];

          systemd.services.paperclip = {
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "docker.service"
            ];
            # Agent runs inherit this PATH unless the Local environment sets one.
            path = [
              "/paperclip/agent-tools"
              "/run/wrappers"
              "/run/current-system/sw"
            ];
            # The docker image's env, minus what only made sense in it.
            environment = {
              HOME = "/paperclip";
              NODE_ENV = "production";
              HOST = "0.0.0.0";
              PORT = toString port;
              SERVE_UI = "true";
              PAPERCLIP_HOME = "/paperclip";
              PAPERCLIP_INSTANCE_ID = "default";
              PAPERCLIP_CONFIG = "/paperclip/instances/default/config.json";
              PAPERCLIP_DEPLOYMENT_MODE = "authenticated";
              PAPERCLIP_DEPLOYMENT_EXPOSURE = "private";
              PAPERCLIP_PUBLIC_URL = "https://paperclip.${hostConfig.hostConfig.lanVhosts.httpsDomain}";
              # Agents share the server's machine, so loopback. 127.0.0.1 not
              # localhost, which may try ::1 against an IPv4-only listener.
              PAPERCLIP_API_URL = "http://127.0.0.1:${toString port}";
              # caddy arrives through the SLiRP port forward, i.e. from luna.
              TRUST_PROXY = gateway;
            };

            # The image's CMD, from its WORKDIR.
            script = ''
              export BETTER_AUTH_SECRET="$(cat "$CREDENTIALS_DIRECTORY/auth-secret")"
              export PAPERCLIP_TOOL_ACTION_SIGNING_SECRET="$(cat "$CREDENTIALS_DIRECTORY/tool-action-signing-secret")"
              cd /app
              exec ${pkgs.nodejs_24}/bin/node server/dist-runtime/index.mjs
            '';

            unitConfig.RequiresMountsFor = "/paperclip";
            serviceConfig = {
              User = user;
              Group = user;
              ImportCredential = builtins.attrNames credentials;
              # Read by git and gitea-mcp at use time, never sitting in an env var.
              ExecStartPre = [
                "+${pkgs.coreutils}/bin/install -D -m 0400 -o ${user} -g ${user} %d/gitea-token ${giteaTokenPath}"
              ];
              Restart = "always";
              # Embedded Postgres needs time to shut down cleanly.
              TimeoutStopSec = 90;
            };
          };
        };

      systemd.services."microvm@${name}" = {
        unitConfig.RequiresMountsFor = snapDir;
        wants = [ "docker.service" ];
        after = [ "docker.service" ];
        serviceConfig = {
          ExecStartPre = [
            "+${snapshot}"
            "+${installApp}"
          ];
          # A version bump pulls the whole image (about 12 GB) first.
          TimeoutStartSec = 1800;
          # Covers the guest's 90s Paperclip stop plus shutdown.
          TimeoutStopSec = 150;
        };
      };

      # Egress sandbox: the internet stays open (model APIs, npm, nix caches),
      # but nothing on this host, the LAN, other stacks or the tailnet is
      # reachable except Gitea's web port. SLiRP makes every guest connection,
      # docker test containers' included, a socket of the qemu process on luna,
      # so matching its uid in OUTPUT covers all of it; SLiRP sends the
      # gateway address to luna's loopback.
      networking.firewall.extraCommands = ''
        iptables -N paperclip-vm-egress 2>/dev/null || iptables -F paperclip-vm-egress
        iptables -A paperclip-vm-egress -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
        iptables -A paperclip-vm-egress -d 127.0.0.1 -p tcp --dport 3000 -j RETURN
        iptables -A paperclip-vm-egress -m addrtype --dst-type LOCAL -j REJECT
        iptables -A paperclip-vm-egress -m addrtype --dst-type BROADCAST -j DROP
        iptables -A paperclip-vm-egress -m addrtype --dst-type MULTICAST -j DROP
        for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
          iptables -A paperclip-vm-egress -d "$net" -j REJECT
        done
        iptables -C OUTPUT -m owner --uid-owner microvm -j paperclip-vm-egress 2>/dev/null \
          || iptables -I OUTPUT -m owner --uid-owner microvm -j paperclip-vm-egress
      '';
      networking.firewall.extraStopCommands = ''
        iptables -D OUTPUT -m owner --uid-owner microvm -j paperclip-vm-egress 2>/dev/null || true
      '';

      hostConfig.lanVhosts.services.paperclip.upstream = "127.0.0.1:${toString port}";
    };
}
