{ ... }:
{
  flake.nixosModules.tailscale =
    { ... }:
    {
      services.tailscale = {
        enable = true;
        openFirewall = true;
        extraUpFlags = [
          "--ssh"
          "--advertise-routes=192.168.0.0/24"
          "--advertise-exit-node"
        ];

      };

      networking.firewall = {
        # Always allow traffic from your Tailscale network
        trustedInterfaces = [ "tailscale0" ];
      };

      systemd.network.wait-online.enable = false;
      boot.initrd.systemd.network.wait-online.enable = false;

    };

}
