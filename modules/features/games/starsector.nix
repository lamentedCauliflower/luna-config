{ ... }:
{
  flake.nixosModules.starsector =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        starsector
      ];
    };

}
