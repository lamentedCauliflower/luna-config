{ ... }:

{
  flake.nixosModules.navidromeContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/navidrome";
    in
    {

      virtualisation.docker.enable = true;

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        services:
          navidrome:
            image: deluan/navidrome:latest
            restart: unless-stopped
            ports:
              - "4533:4533"
            environment:
              ND_PORT: 4533
              ND_SCANNER_SCHEDULE: "@every 1h"

            volumes:
              - "/etc/${dir}/data/:/data"
              - "/mnt/raidDrive/media/Music:/music:ro"
      '';

      systemd.services.navidrome = {
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

      services.caddy.virtualHosts."navidrome.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:4533
      '';

      networking.firewall = {
        allowedTCPPorts = [
          4533
        ];

        allowedUDPPorts = [
          4533
        ];
      };

    };

}
