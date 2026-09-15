{ ... }:
{
  flake.nixosModules.hermesContainer =
    {
      pkgs,
      lib,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/hermes";
      dataDir = "/var/lib/${dir}";
      composeFile = "/etc/${dir}/compose.yaml";

      # The image drops to this fixed non-root uid and /opt/data is a host bind
      # mount, so the host directory has to be owned by it or the gateway cannot
      # write sessions, memories or skills.
      hermesUid = 10000;
      hermesGid = 10000;

      # One dashboard backend fronts every profile at once — the Desktop/Web
      # client sends the target profile with each request, so this port does not
      # multiply with the profile list below.
      dashboardPort = 9119;

      # Not a secret, so it stays here rather than in secrets.yaml; the password
      # hash and the session-signing secret next to it are sops-managed.
      dashboardUser = "isaac";

      # Multi-profile: a profile is a supervised gateway (s6 slot) inside the one
      # container, not a container each. Upstream recommends the single-container
      # shape and warns that two gateway processes must never share a data dir.
      #
      # A profile needs an entry here only to get its own OpenAI-compatible API
      # server on its own port; the dashboard reaches profiles that are not
      # listed. `default` is the profile Hermes ships with. To add one, give it a
      # free port and rebuild — the profile, its s6 slot and its API server are
      # created on the next start of the unit.
      profiles = {
        default = { apiPort = 8642; };
        # coder = { apiPort = 8643; };
      };

      extraProfiles = lib.filterAttrs (name: _: name != "default") profiles;

      # The default profile keeps its .env at the root of the data dir; every
      # other profile gets one under profiles/<name>/.
      envFileOf = name: if name == "default" then "${dataDir}/.env" else "${dataDir}/profiles/${name}/.env";

      # Only these three keys are managed here. The rest of a profile's .env is
      # the user's — API keys and chat-platform tokens, written by `hermes
      # setup` — and is never read, copied or rendered into the store. Dashboard
      # auth used to live there too and is now declared above instead.
      syncEnvFn = ''
        sync_env() {
          file="$1"
          port="$2"
          install -d -m 0700 -o ${toString hermesUid} -g ${toString hermesGid} "$(dirname "$file")"
          touch "$file"
          for kv in API_SERVER_ENABLED=true API_SERVER_HOST=0.0.0.0 "API_SERVER_PORT=$port"; do
            grep -qxF "$kv" "$file" && continue
            sed -i "/^''${kv%%=*}=/d" "$file"
            printf '%s\n' "$kv" >> "$file"
          done
          chown ${toString hermesUid}:${toString hermesGid} "$file"
          chmod 0600 "$file"
        }
      '';

      # Run before the container, so a port change in `profiles` is already in
      # the .env by the time that profile's gateway boots. A profile directory
      # that does not exist yet is left alone: `hermes profile create` owns it.
      preStartSync = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: p:
          if name == "default" then
            ''sync_env "${envFileOf name}" ${toString p.apiPort}''
          else
            ''[ -d "${dataDir}/profiles/${name}" ] && sync_env "${envFileOf name}" ${toString p.apiPort}''
        ) profiles
      );

      postStartCreate = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: p: ''
          if [ ! -d "${dataDir}/profiles/${name}" ]; then
            docker exec hermes hermes profile create ${name}
            sync_env "${envFileOf name}" ${toString p.apiPort}
            docker exec hermes hermes -p ${name} gateway restart
          fi
        '') extraProfiles
      );

      # Plain strings, not indented-string literals: Nix strips leading
      # whitespace back off an ''...'' and would flatten the yaml.
      publishedPorts = lib.mapAttrsToList (
        _: p: "      - \"127.0.0.1:${toString p.apiPort}:${toString p.apiPort}\""
      ) profiles;
    in
    {

      virtualisation.docker.enable = true;

      # Dashboard auth is the one piece of Hermes' configuration declared here
      # rather than left to the data dir's .env. ADR 0007 kept the .env out of
      # sops because `hermes setup` writes it and Hermes rewrites it as chat
      # platforms are linked; these three keys are set once by an admin and
      # never rewritten, so that reason does not reach them.
      #
      # They arrive as container environment, not through sync_env below,
      # because the dashboard is one backend for every profile while the
      # API_SERVER_* keys differ per profile and so have to live in each
      # profile's own .env. Upstream documents container environment as
      # overriding the .env, naming secrets-manager integration as the case for
      # it, so this is the supported direction and not a trick.
      #
      # _SECRET signs dashboard sessions: without a stable one, every restart of
      # the container logs every dashboard session out.
      sops.secrets.hermesDashboardPasswordHash = { };
      sops.secrets.hermesDashboardAuthSecret = { };
      sops.templates."hermes-dashboard.env" = {
        content = ''
          HERMES_DASHBOARD_BASIC_AUTH_USERNAME=${dashboardUser}
          HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=${config.sops.placeholder.hermesDashboardPasswordHash}
          HERMES_DASHBOARD_BASIC_AUTH_SECRET=${config.sops.placeholder.hermesDashboardAuthSecret}
        '';
        restartUnits = [ "hermes.service" ];
      };

      # 0700 because the .env under here holds every API key and chat token the
      # agent has; the data dir is the only place they exist on this host.
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0700 ${toString hermesUid} ${toString hermesGid} -"
      ];

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        services:
          hermes:
            image: nousresearch/hermes-agent:latest
            container_name: hermes
            restart: unless-stopped
            command: gateway run

            # Chromium under Playwright ships in the image and dies on docker's
            # 64M default /dev/shm, taking every browser tool call with it.
            shm_size: 1gb

            environment:
              HERMES_DASHBOARD: "1"

            # sops-rendered, so the values live on /run's tmpfs and never in the
            # nix store. The dashboard defaults to binding 0.0.0.0 inside the
            # container — which it must, since a container-loopback bind is
            # unreachable through the port publish below — and a non-loopback
            # bind engages its auth gate, so without these keys the dashboard
            # refuses to start at all.
            #
            # format: raw because compose interpolates unquoted env_file values.
            # A scrypt hash is `scrypt$N$r$p$salt$hash`, and `$salt` parses as a
            # variable reference that expands to nothing — which corrupts the
            # hash quietly: the provider still registers on a non-empty value,
            # so the dashboard comes up and serves a login that rejects the
            # correct password.
            env_file:
              - path: ${config.sops.templates."hermes-dashboard.env".path}
                format: raw

            # Nothing is published to the LAN. Caddy fronts the dashboard on
            # ${toString dashboardPort}; the API servers are loopback-only because an
            # unset API_SERVER_KEY leaves them unauthenticated, and this agent
            # can run shell and browser tools. Give a profile a key in its .env
            # before adding a caddy vhost for its port.
            ports:
        ${lib.concatStringsSep "\n" publishedPorts}
              - "127.0.0.1:${toString dashboardPort}:${toString dashboardPort}"

            volumes:
              - ${dataDir}:/opt/data

            # Replaces the hypervisor-enforced ceiling the Hermes VM had. Compose
            # v2 applies these outside swarm. Browser tools want 2G+ on their
            # own, so this is not as generous as it looks.
            deploy:
              resources:
                limits:
                  memory: 8G
                  cpus: "4.0"
      '';

      systemd.services.hermes = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        # coreutils/gnused/gnugrep are already in every unit's default path.
        path = [ pkgs.docker ];

        preStart = ''
          set -eu
          ${syncEnvFn}
          ${preStartSync}
        '';

        script = ''
          docker compose -f ${composeFile} up --remove-orphans
        '';

        preStop = ''
          docker compose -f ${composeFile} down
        '';

        postStart = lib.optionalString (extraProfiles != { }) ''
          set -eu
          ${syncEnvFn}

          # `docker compose up` returns long before s6 inside the container is
          # accepting exec, and profile creation goes through exec.
          for _ in $(seq 60); do
            docker exec hermes hermes profile list >/dev/null 2>&1 && break
            sleep 2
          done

          ${postStartCreate}
        '';

        serviceConfig = {
          Restart = "always";
        } // lib.optionalAttrs (extraProfiles != { }) {
          # postStart may wait up to 120s for s6, which overruns the 90s default.
          TimeoutStartSec = 300;
        };

        restartTriggers = [
          config.environment.etc."${dir}/compose.yaml".source
        ];
      };

      # Same hostname the Hermes VM answered on, now pointing at the dashboard
      # rather than the VM's own port. The dashboard supervises every profile, so
      # the LAN reaches it only behind the basic auth declared above.
      #
      # dashboard.public_url stays unset: basic auth needs no OAuth callback, and
      # setting it turns on a Host-header check that rejects this vhost unless
      # dashboard.trusted_proxies also lists the proxy.
      services.caddy.virtualHosts."hermes.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString dashboardPort}
        '';
      };

    };

}
