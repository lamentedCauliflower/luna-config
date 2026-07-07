{ ... }:

{
  flake.nixosModules.octoprintContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/octoprint";
    in
    {

      virtualisation.docker.enable = true;

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: octoprint
        services:
          octoprint:
            image: octoprint/octoprint
            restart: unless-stopped
            ports:
              - 8888:80
            devices:
              - /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AD0JMD68-if00-port0:/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AD0JMD68-if00-port0
            volumes:
              - /etc/${dir}/data:/octoprint
      '';

      systemd.services.octoprint = {
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

      services.caddy.virtualHosts."octoprint.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:8888
      '';

      networking.firewall = {
        allowedTCPPorts = [
          8888
        ];

      };

    };

}
