{ ... }:

{
  flake.nixosModules.fourgetContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/fourget";
    in
    {

      virtualisation.docker.enable = true;

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        services:
          fourget:
            image: luuul/4get:latest
            restart: unless-stopped
            environment:
              - FOURGET_PROTO=http
              - FOURGET_SERVER_NAME=4get.luna.local
            ports:
              - "44480:80"
      '';

      systemd.services.fourget = {
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

      services.caddy.virtualHosts."4get.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:44480
      '';

      networking.firewall = {
        allowedTCPPorts = [
          44480
        ];

        allowedUDPPorts = [
          44480
        ];
      };

    };

}
