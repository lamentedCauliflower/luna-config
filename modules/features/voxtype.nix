{ inputs, ... }:
{
  flake.nixosModules.voxtype =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };

}
