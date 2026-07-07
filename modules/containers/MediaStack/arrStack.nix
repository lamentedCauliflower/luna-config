{ username, ... }:

{
  flake.nixosModules.arrStackContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/arrStack";
      torrent_dir = "/mnt/raidDrive/downloads/torrent";
      soulseek_dir = "/mnt/raidDrive/downloads/soulseek";
      media_dir = "/mnt/raidDrive/media";
    in
    {

      virtualisation.docker.enable = true;

      sops.secrets.arrStackApiKey = { };
      # Shared by every service in the stack; unused vars are ignored per image.
      sops.templates."arrStack.env" = {
        content = ''
          USER=${username}
          PASS=${config.sops.placeholder.arrStackApiKey}
          PROWLARR__AUTH__APIKEY=${config.sops.placeholder.arrStackApiKey}
          SONARR__AUTH__APIKEY=${config.sops.placeholder.arrStackApiKey}
          RADARR__AUTH__APIKEY=${config.sops.placeholder.arrStackApiKey}
          LIDARR__AUTH__APIKEY=${config.sops.placeholder.arrStackApiKey}
        '';
        restartUnits = [ "arrStack.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: Arr Stack
        services:
          transmission:
            image: lscr.io/linuxserver/transmission:latest
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/transmission:/config
              - ${torrent_dir}:/downloads
            ports:
              - 9091:9091
              - 51413:51413
              - 51413:51413/udp
            restart: unless-stopped

          prowlarr:
            image: lscr.io/linuxserver/prowlarr:nightly
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/prowlarr:/config
            ports:
              - 9696:9696
            restart: unless-stopped

          sonarr:
            image: lscr.io/linuxserver/sonarr:latest
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/sonarr/:/config
              - ${media_dir}/Shows/:/tv
              - ${media_dir}/Anime/:/anime
              - ${torrent_dir}:/downloads
            ports:
              - 8989:8989
            restart: unless-stopped

          radarr:
            image: lscr.io/linuxserver/radarr:latest
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/radarr/:/config
              - ${media_dir}/Movies/:/movies
              - ${torrent_dir}:/downloads
            ports:
              - 7878:7878
            restart: unless-stopped

          lidarr:
            image: lscr.io/linuxserver/lidarr:nightly
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/lidarr/:/config
              - ${media_dir}/Music/:/music
              - ${torrent_dir}:/downloads
              - ${soulseek_dir}:/app/downloads

            ports:
              - 8686:8686
            restart: unless-stopped

          slskd:
              user: '1000:1000'
              image: slskd/slskd
              environment:
                - SLSKD_REMOTE_CONFIGURATION=true
              ports:
                - 5030:5030
                - 5031:5031
                - 50300:50300
              volumes:
                - /etc/${dir}/slskd/:/app
                - ${soulseek_dir}:/app/downloads
              restart: unless-stopped

          seerr:
            image: ghcr.io/seerr-team/seerr:latest
            init: true
            container_name: seerr
            environment:
              - LOG_LEVEL=debug
              - PORT=5055
            ports:
              - 5055:5055
            volumes:
              - /etc/${dir}/slskd/:/app/config
            healthcheck:
              test: wget --no-verbose --tries=1 --spider http://localhost:5055/api/v1/settings/public || exit 1
              start_period: 20s
              timeout: 3s
              interval: 15s
              retries: 3
            restart: unless-stopped

      '';

      systemd.services.arrStack = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        path = [ pkgs.docker ];
        script = ''
          docker compose -f /etc/${dir}/compose.yaml up
        '';
        restartTriggers = [
          config.environment.etc."${dir}/compose.yaml".source
        ];
      };

      networking.firewall = {
        allowedTCPPorts = [
          9696
          8989
          7878
          9091
          51413
          8686
          5030
          5031
          50300
          5055
        ];

        allowedUDPPorts = [
          51413
        ];
      };

      services.caddy.virtualHosts."sonarr.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:8989
      '';

      services.caddy.virtualHosts."radarr.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:7878
      '';

      services.caddy.virtualHosts."prowlarr.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:9696
      '';

      services.caddy.virtualHosts."transmission.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:9091
      '';

      services.caddy.virtualHosts."lidarr.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:8686
        '';
      };

      services.caddy.virtualHosts."soulseek.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:5030
        '';
      };

      services.caddy.virtualHosts."seer.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:5055
        '';
      };

    };

}
