{ ... }:
{
  flake.nixosModules.bluetooth =
    { pkgs, ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      environment.systemPackages = [
        pkgs.bluejay
      ];
    };
}
