{ self, ... }:
{
  flake.nixosModules.caddy =
    { ... }:
    {
      # Brings in hostConfig.lanVhosts, which every LAN-only service declares
      # itself through. Importing caddy without it would let a service fall
      # back to a bare virtualHosts entry and quietly lose the remote_ip gate.
      imports = [ self.nixosModules.lanVhosts ];

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
