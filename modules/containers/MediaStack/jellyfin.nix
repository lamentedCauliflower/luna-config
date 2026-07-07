{ ... }:

{
  flake.nixosModules.jellyfinContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/jellyfin";
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
              - JELLYFIN_PublishedServerUrl=http://jellyfin.luna.local

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

      services.caddy.virtualHosts."jellyfin.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:8096
      '';

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
