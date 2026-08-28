{ username, ... }:

{
  flake.nixosModules.minecraftContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/minecraft";
      packwizPort = 25566;
      mcPort = 25565;

      # Live world + modpack already exist here and are exported over NFS/Samba,
      # so the modpack can be edited from a desktop without touching the server.
      packRoot = "/mnt/raidDrive/${username}/Minecraft/aeroslop";

      composeFile = "/etc/${dir}/compose.yaml";

      # Loader version is pinned to pack.toml's `neoforge` field. itzg resolves
      # "latest for this Minecraft version" when NEOFORGE_VERSION is unset, and
      # packwiz does not constrain it — the server has already drifted 248 -> 249
      # that way. With a nightly restart, leaving it unpinned is 365 unattended
      # chances a year for the loader to move under the pack.
      neoforgeVersion = "21.1.248";
    in
    {

      virtualisation.docker.enable = true;

      # Docker's own shutdown timeout overrides stop_grace_period when the host
      # reboots, so without this an unattended kernel reboot SIGKILLs a saving
      # server. Must stay >= the stop_grace_period below.
      virtualisation.docker.daemon.settings.shutdown-timeout = 180;

      sops.secrets.minecraftRconPassword = { };
      sops.templates."minecraft.env" = {
        content = ''
          RCON_PASSWORD=${config.sops.placeholder.minecraftRconPassword}
        '';
        restartUnits = [ "minecraftServer.service" ];
      };

      # Whitelist and ops are deliberately absent: they are managed in-game and
      # persist in data/whitelist.json + data/ops.json. Setting WHITELIST/OPS
      # here would put player names in a public repo, and OVERRIDE_* would make
      # the nightly restart stomp any in-game change.
      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: aeroslop
        services:
          packwiz:
            image: python:3-alpine
            working_dir: /packwiz
            command: python -m http.server 8080
            restart: unless-stopped
            ports:
              - "${toString packwizPort}:8080"
            volumes:
              - ${packRoot}/packwiz:/packwiz:ro

          minecraft-server:
            image: itzg/minecraft-server:java21
            container_name: minecraft-server
            pull_policy: daily
            restart: unless-stopped
            tty: true
            stdin_open: true

            # mc-server-runner turns SIGTERM into a console `stop`, but the world
            # needs longer than docker's 10s default to flush.
            stop_grace_period: 180s

            depends_on:
              - packwiz

            ports:
              - "${toString mcPort}:25565"

            env_file:
              - ${config.sops.templates."minecraft.env".path}

            environment:
              EULA: "TRUE"
              TYPE: NEOFORGE
              VERSION: "1.21.1"
              NEOFORGE_VERSION: "${neoforgeVersion}"
              PACKWIZ_URL: "http://packwiz:8080/pack.toml"

              INIT_MEMORY: 2G
              MAX_MEMORY: 8G
              USE_AIKAR_FLAGS: "TRUE"

              # Match the existing data dir (isaac:users); itzg defaults to
              # GID 1000, which owns nothing here.
              UID: 1000
              GID: 100

              ENABLE_WHITELIST: "TRUE"
              ENABLE_RCON: "TRUE"

              # Short heads-up for stops we do not drive ourselves (host reboot,
              # systemctl stop). The nightly restart does its own countdown.
              STOP_SERVER_ANNOUNCE_DELAY: 10

            volumes:
              - ${packRoot}/data:/data
      '';

      systemd.services.minecraftServer = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        path = [ pkgs.docker ];
        script = ''
          docker compose -f ${composeFile} up --remove-orphans
        '';
        preStop = ''
          docker compose -f ${composeFile} down
        '';
        serviceConfig = {
          Restart = "always";
          # Must exceed stop_grace_period, or systemd kills the stack before the
          # world has finished saving.
          TimeoutStopSec = 300;
        };
        restartTriggers = [
          config.environment.etc."${dir}/compose.yaml".source
        ];
      };

      # Nightly restart at 04:30. system.autoUpgrade runs at 04:00 with
      # allowReboot, so these can overlap; the grace periods above make either
      # path a clean shutdown.
      systemd.services.minecraftDailyRestart = {
        after = [ "minecraftServer.service" ];
        requires = [ "minecraftServer.service" ];
        path = [ pkgs.docker ];
        script = ''
          # A hung server cannot answer RCON. Warn on a best-effort basis and
          # restart regardless — a wedged server is the one most worth bouncing.
          warn() { docker exec minecraft-server rcon-cli "$@" || true; }

          warn say "Server restarting in 60 seconds"
          sleep 30
          warn say "Server restarting in 30 seconds"
          sleep 20
          warn say "Server restarting in 10 seconds"
          sleep 10
          warn save-all flush

          docker compose -f ${composeFile} restart minecraft-server
        '';
        serviceConfig = {
          Type = "oneshot";
          # 60s of warnings plus up to 180s of graceful stop overruns the 90s
          # default and would kill the script mid-restart.
          TimeoutStartSec = 600;
        };
      };

      systemd.timers.minecraftDailyRestart = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 04:30:00";
          Persistent = false;
          Unit = "minecraftDailyRestart.service";
        };
      };

      services.caddy.virtualHosts."http://mc.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString packwizPort}
        '';
      };

      services.caddy.virtualHosts."mc.monkeymeat.xyz" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString packwizPort}
        '';
      };

      networking.firewall = {
        allowedTCPPorts = [
          packwizPort
          mcPort
        ];
      };

    };

}
