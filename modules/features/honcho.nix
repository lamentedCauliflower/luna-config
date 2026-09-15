{ ... }:
{
  flake.nixosModules.honcho =
    { pkgs, ... }:
    {
      ## no service for nix yet so just open port and forward
      networking.firewall.allowedTCPPorts = [ 3456 ];

      hostConfig.lanVhosts.services.honcho.upstream = "127.0.0.1:3456";

    };

}
