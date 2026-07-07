{ ... }:

{
  flake.nixosModules.rommContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/romm";
    in

    {
      virtualisation.docker.enable = true;

      sops.secrets = {
        rommSecret = { };
        screenscraperUsername = { };
        screenscraperPassword = { };
        retroAchievementsAPIKey = { };
        steamGridDBAPIKey = { };
      };
      # Interpolation variables for `docker compose --env-file` (not injected
      # into containers directly). The compose file keeps its original quoted
      # `- KEY="${VAR}"` entries so the values the containers see stay
      # byte-identical to the pre-sops deployment — the mariadb volume was
      # initialised with those exact bytes.
      sops.templates."romm.env" = {
        content = ''
          ROMM_SECRET=${config.sops.placeholder.rommSecret}
          SCREENSCRAPER_USER=${config.sops.placeholder.screenscraperUsername}
          SCREENSCRAPER_PASS=${config.sops.placeholder.screenscraperPassword}
          RETROACHIEVEMENTS_KEY=${config.sops.placeholder.retroAchievementsAPIKey}
          STEAMGRIDDB_KEY=${config.sops.placeholder.steamGridDBAPIKey}
        '';
        restartUnits = [ "romm.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''

        services:
          romm:
            image: rommapp/romm:latest
            container_name: romm
            restart: unless-stopped
            environment:
              - DB_HOST=romm-db
              - DB_NAME=romm
              - DB_USER=romm-user
              - DB_PASSWD="''${ROMM_SECRET}"
              - ROMM_AUTH_SECRET_KEY="''${ROMM_SECRET}"
              - SCREENSCRAPER_USER="''${SCREENSCRAPER_USER}"
              - SCREENSCRAPER_PASSWORD="''${SCREENSCRAPER_PASS}"
              - RETROACHIEVEMENTS_API_KEY="''${RETROACHIEVEMENTS_KEY}"
              - STEAMGRIDDB_API_KEY="''${STEAMGRIDDB_KEY}"
              - HASHEOUS_API_ENABLED=true # https://docs.romm.app/latest/Getting-Started/Metadata-Providers/#hasheous
            volumes:
              - /var/lib/${dir}/resources/:/romm/resources # Resources fetched from IGDB (covers, screenshots, etc.)
              - /var/lib/${dir}/redis/:/redis-data # Cached data for background tasks
              - /mnt/raidDrive/media/Games/Roms/:/romm/library # Your game library. Check https://docs.romm.app/latest/Getting-Started/Folder-Structure/ for more details.
              - /mnt/raidDrive/media/Games/RommAssets/:/romm/assets # Uploaded saves, states, etc.
              - /etc/${dir}/config/:/romm/config # (Optional) Path where config.yml is stored
            ports:
              - 7442:8080
            depends_on:
              romm-db:
                condition: service_healthy
                restart: true

          romm-db:
            image: mariadb:latest
            container_name: romm-db
            restart: unless-stopped
            environment:
              - MARIADB_ROOT_PASSWORD="''${ROMM_SECRET}"
              - MARIADB_DATABASE=romm
              - MARIADB_USER=romm-user
              - MARIADB_PASSWORD="''${ROMM_SECRET}"
            volumes:
              - /var/lib/${dir}/mariadb/:/var/lib/mysql
            healthcheck:
              test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
              start_period: 30s
              start_interval: 10s
              interval: 10s
              timeout: 5s
              retries: 5
      '';

      systemd.services.romm = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        path = [ pkgs.docker ];
        script = ''
          docker compose --env-file ${config.sops.templates."romm.env".path} -f /etc/${dir}/compose.yaml up
        '';
        restartTriggers = [
          config.environment.etc."${dir}/compose.yaml".source
        ];
      };

      services.caddy.virtualHosts."romm.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:7442
      '';

      networking.firewall = {
        allowedTCPPorts = [
          7442
        ];
      };

    };

}
