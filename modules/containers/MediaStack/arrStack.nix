{ username, ... }:

{
  flake.nixosModules.arrStackContainer =
    {
      pkgs,
      config,
      ...
    }:
    let
      dir = "stacks/arrStack";
      torrent_dir = "/mnt/raidDrive/downloads/torrent";
      soulseek_dir = "/mnt/raidDrive/downloads/soulseek";
      media_dir = "/mnt/raidDrive/media";
      # nl-ams-wg-201.mullvad.ts.net. IP, not hostname: containerboot's
      # `tailscale up` can't resolve hostnames before the netmap exists.
      exitNode = "100.123.199.85";
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

      # Own tailnet node so only it rides Mullvad; the host stays an exit node itself.
      sops.secrets.arrTailscaleAuthKey = { };
      sops.templates."arrTailscale.env" = {
        content = "TS_AUTHKEY=${config.sops.placeholder.arrTailscaleAuthKey}";
        restartUnits = [ "arrStack.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: Arr Stack
        services:
          # transmission, prowlarr, slskd and flaresolverr share this netns, so their outbound
          # traffic leaves via the Mullvad exit node. Their ports live here too.
          tailscale:
            image: tailscale/tailscale:latest
            hostname: luna-arr
            # Send LAN traffic via the docker gateway, not Mullvad, so direct
            # ip:port access works. Tailscale's `lookup 52` rule sits at 5270,
            # so this must be a rule at a lower priority, not a route in main.
            entrypoint:
              - sh
              - -c
              - ip rule del to 192.168.0.0/24 lookup main priority 5000 2>/dev/null; ip rule add to 192.168.0.0/24 lookup main priority 5000 && exec containerboot
            env_file:
              - ${config.sops.templates."arrTailscale.env".path}
            environment:
              - TS_STATE_DIR=/var/lib/tailscale
              - TS_USERSPACE=false
              # Image defaults to iptables-legacy; the host kernel only has nft tables.
              - TS_DEBUG_FIREWALL_MODE=nftables
              - TS_EXTRA_ARGS=--exit-node=${exitNode} --exit-node-allow-lan-access
            volumes:
              - /etc/${dir}/tailscale:/var/lib/tailscale
            devices:
              - /dev/net/tun:/dev/net/tun
            cap_add:
              - NET_ADMIN
              - NET_RAW
            networks:
              default:
                aliases: [transmission, prowlarr, slskd]
            ports:
              - 9091:9091
              - 51413:51413
              - 51413:51413/udp
              - 9696:9696
              - 5030:5030
              - 5031:5031
              - 50300:50300
            restart: unless-stopped

          transmission:
            image: lscr.io/linuxserver/transmission:latest
            network_mode: service:tailscale
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/transmission:/config
              - ${torrent_dir}:/downloads
            restart: unless-stopped

          prowlarr:
            image: lscr.io/linuxserver/prowlarr:nightly
            network_mode: service:tailscale
            env_file:
              - ${config.sops.templates."arrStack.env".path}
            environment:
              - PUID=1000
              - PGID=1000
            volumes:
              - /etc/${dir}/prowlarr:/config
            restart: unless-stopped

          # Shares prowlarr's netns: add it in prowlarr as http://localhost:8191.
          flaresolverr:
            image: ghcr.io/flaresolverr/flaresolverr:latest
            network_mode: service:tailscale
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
              network_mode: service:tailscale
              environment:
                - SLSKD_REMOTE_CONFIGURATION=true
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

      hostConfig.lanVhosts.services = {
        sonarr.upstream = "127.0.0.1:8989";
        radarr.upstream = "127.0.0.1:7878";
        prowlarr.upstream = "127.0.0.1:9696";
        transmission.upstream = "127.0.0.1:9091";
        lidarr.upstream = "127.0.0.1:8686";
        soulseek.upstream = "127.0.0.1:5030";
        seer.upstream = "127.0.0.1:5055";
      };

    };

}
