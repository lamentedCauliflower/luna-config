{ username, ... }:
{
  flake.nixosModules.hermesContainer =
    {
      pkgs,
      lib,
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
      # and the session-signing secret next to it are sops-managed.
      dashboardUser = "isaac";

      # The vault is one directory on the raid, reached over NFS as
      # /mnt/${username}/Obsidian from every client. The container gets the same
      # path it has everywhere else, so a note, skill or session transcript that
      # references the vault resolves identically on the agent and on a desktop.
      obsidianHostPath = "/mnt/raidDrive/${username}/Obsidian";
      obsidianContainerPath = "/mnt/${username}/Obsidian";

      # Written by preStart, never by Nix: it holds the derived password hash,
      # so it must not reach the store. /run is tmpfs, root-owned, 0400.
      dashboardEnvFile = "/run/hermes/dashboard.env";

      # Derives Hermes' scrypt hash from the sops-held plaintext at activation,
      # so rotating the dashboard password is `sops set` plus a rebuild rather
      # than a hand-run hash_password inside the image.
      #
      # The parameters are upstream's, checked against a hash the image itself
      # produced: scrypt$N$r$p$<b64 salt>$<b64 dk>, n=16384 r=8 p=1, 16-byte
      # salt, 32-byte output, no pepper. If upstream ever changes them the
      # failure is a rejected login, not a corrupted file — recoverable by
      # re-running hash_password and pinning the hash again.
      dashboardEnvScript = pkgs.writeText "hermes-dashboard-env.py" /* python */ ''
        import base64
        import hashlib
        import hmac
        import os
        import secrets
        import sys

        pw_file, secret_file, username, out_file = sys.argv[1:5]

        N, R, P, DKLEN, SALT_LEN = 16384, 8, 1, 32, 16


        def read(path):
            with open(path, "rb") as fh:
                data = fh.read()
            return data[:-1] if data.endswith(b"\n") else data


        password = read(pw_file)
        session_secret = read(secret_file).decode()


        def derive(salt, n, r, p, dklen):
            return hashlib.scrypt(password, salt=salt, n=n, r=r, p=p, dklen=dklen)


        def matches(encoded):
            try:
                tag, n, r, p, salt_b64, dk_b64 = encoded.split("$")
                if tag != "scrypt":
                    return False
                want = base64.b64decode(dk_b64)
                got = derive(base64.b64decode(salt_b64), int(n), int(r), int(p), len(want))
            except Exception:
                return False
            return hmac.compare_digest(got, want)


        # Reuse the hash already on disk when the password behind it has not
        # changed. Rewriting it would change the env file on every rebuild, and
        # compose recreates the container when its environment moves — which
        # kills every running agent session for no reason.
        existing = {}
        if os.path.exists(out_file):
            with open(out_file) as fh:
                for line in fh:
                    key, _, value = line.rstrip("\n").partition("=")
                    existing[key] = value

        current = existing.get("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH", "")
        if (
            current
            and existing.get("HERMES_DASHBOARD_BASIC_AUTH_USERNAME") == username
            and existing.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET") == session_secret
            and matches(current)
        ):
            sys.exit(0)

        salt = secrets.token_bytes(SALT_LEN)
        encoded = "scrypt$%d$%d$%d$%s$%s" % (
            N,
            R,
            P,
            base64.b64encode(salt).decode(),
            base64.b64encode(derive(salt, N, R, P, DKLEN)).decode(),
        )

        fd = os.open(out_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o400)
        with os.fdopen(fd, "w") as fh:
            fh.write(
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=" + username + "\n"
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=" + encoded + "\n"
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=" + session_secret + "\n"
            )
        os.chmod(out_file, 0o400)
      '';

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
      # platforms are linked; these keys are set by an admin and never
      # rewritten, so that reason does not reach them.
      #
      # They arrive as container environment, not through sync_env below,
      # because the dashboard is one backend for every profile while the
      # API_SERVER_* keys differ per profile and so have to live in each
      # profile's own .env. Upstream documents container environment as
      # overriding the .env, naming secrets-manager integration as the case for
      # it, so this is the supported direction and not a trick.
      #
      # The plaintext is what is stored, and it never leaves sops or /run:
      # preStart derives the hash Hermes actually wants, so the store never sees
      # either form. Deriving at activation rather than in a derivation is the
      # whole point — a build input would land world-readable in the store.
      #
      # _SECRET signs dashboard sessions: without a stable one, every restart of
      # the container logs every dashboard session out.
      sops.secrets.hermesDashboardPassword.restartUnits = [ "hermes.service" ];
      sops.secrets.hermesDashboardAuthSecret.restartUnits = [ "hermes.service" ];

      # 0700 because the .env under here holds every API key and chat token the
      # agent has; the data dir is the only place they exist on this host.
      #
      # The vault rules grant the image's uid the least that lets it work: `--x`
      # on ${username}'s directory is traverse without the right to list it, so
      # the agent reaches Obsidian and nothing else under there. The A+ line is
      # the default ACL, which is what makes notes the agent creates inherit the
      # grant; without it only the vault root would be writable. Neither rule
      # recurses, so files that predate them need the one-off setfacl in
      # docs/adr/0007.
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0700 ${toString hermesUid} ${toString hermesGid} -"

        "a+ /mnt/raidDrive/${username} - - - - u:${toString hermesUid}:--x"
        "a+ ${obsidianHostPath} - - - - u:${toString hermesUid}:rwx"
        "A+ ${obsidianHostPath} - - - - u:${toString hermesUid}:rwx"
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
              - path: ${dashboardEnvFile}
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

              # Read-write on purpose: the agent is meant to write notes. It
              # also runs shell tools, so it can rewrite or delete anything in
              # the vault — the vault's protection against that is Syncthing
              # history and backups, not this mount.
              - ${obsidianHostPath}:${obsidianContainerPath}

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

          install -d -m 0700 -o root -g root "$(dirname ${dashboardEnvFile})"
          ${pkgs.python3}/bin/python3 ${dashboardEnvScript} \
            ${config.sops.secrets.hermesDashboardPassword.path} \
            ${config.sops.secrets.hermesDashboardAuthSecret.path} \
            ${dashboardUser} \
            ${dashboardEnvFile}

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
      hostConfig.lanVhosts.services.hermes.upstream = "127.0.0.1:${toString dashboardPort}";

    };

}
