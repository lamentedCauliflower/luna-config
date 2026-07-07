{ ... }:
{
  flake.nixosModules.honcho =
    { pkgs, dnsName, ... }:
    {
      ## no service for nix yet so just open port and forward
      networking.firewall.allowedTCPPorts = [ 3456 ];

      services.caddy.virtualHosts."honcho.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:3456
        '';
      };

    };

}
