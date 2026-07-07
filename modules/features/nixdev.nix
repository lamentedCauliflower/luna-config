{ ... }:
{
  flake.nixosModules.nixDev =
    { pkgs, ... }:
    {

      environment.systemPackages = with pkgs; [
        nil
        nixd
        prettier
        devenv
      ];

      # Binary cache for devenv.sh
      nix.settings = {
        extra-substituters = [ "https://devenv.cachix.org" ];
        extra-trusted-public-keys = [
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };
    };

}
