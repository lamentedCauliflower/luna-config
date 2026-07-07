{ username, ... }:
{
  flake.nixosModules.libVirt =
    { pkgs, ... }:
    {
      boot.kernelModules = [
        "bridge"
        "tap"
        "tun"
      ];
      environment.systemPackages = with pkgs; [
        dnsmasq
      ];

      virtualisation.libvirtd = {
        enable = true;
        qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
      };

      programs.virt-manager.enable = true;
      users.users.${username}.extraGroups = [ "libvirtd" ];
      networking.firewall.trustedInterfaces = [ "virbr0" ];

    };

}
