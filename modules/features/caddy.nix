{ ... }:
{
  flake.nixosModules.caddy =
    { ... }:
    {
      services.caddy.enable = true;

      networking.firewall = {
        allowedTCPPorts = [
          80
          443
        ];

        allowedUDPPorts = [
          80
          443
        ];
      };
    };
}
