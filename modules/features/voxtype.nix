{ ... }:
{
  flake.nixosModules.voxtype =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        voxtype
      ];
    };

}
