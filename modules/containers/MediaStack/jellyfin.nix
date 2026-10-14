{ ... }:

{
  flake.nixosModules.jellyfinContainer =
    {
      pkgs,
      config,
      ...
    }:
    let
      dir = "stacks/jellyfin";
      lan = config.hostConfig.lanVhosts;
      host = "jellyfin.${lan.httpsDomain}";
    in
    {

      virtualisation.docker.enable = true;

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: jellyfin
        services:
          jellyfin:
            container_name: jellyfin
            image: jellyfin/jellyfin
            ports:
              - 8096:8096/tcp
              - 7359:7359/udp
            volumes:
              - /etc/${dir}/config/:/config
              - /var/cache/jellyfin:/cache
              - /mnt/raidDrive/media:/media
            restart: "unless-stopped"
            environment:
              - JELLYFIN_PublishedServerUrl=https://${host}

      '';

      systemd.services.jellyfin = {
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

      # Public on purpose, so not a lanVhost. Its Cloudflare record is DNS-only
      # at the WAN IP and caddy gets the cert over the forwarded 80/443, like
      # homeassistant.monkeymeat.xyz. Proxying it through Cloudflare would break
      # TLS (the free edge cert covers one subdomain level, not jellyfin.luna)
      # and Cloudflare's terms bar serving video through their proxy anyway.
      services.caddy.virtualHosts = {
        ${host}.extraConfig = "reverse_proxy 127.0.0.1:8096";
        "http://jellyfin.${lan.domain}".extraConfig = "redir https://${host}{uri} 308";
      };

      networking.firewall = {
        allowedTCPPorts = [
          8096
        ];

        allowedUDPPorts = [
          7359
        ];
      };

    };

}
