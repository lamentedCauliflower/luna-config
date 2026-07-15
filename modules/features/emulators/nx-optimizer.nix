{ self, ... }:
{
  flake.nixosModules.nxOptimizer =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.emulators.nxOptimizer;
    in
    {
      # Repo standard: importing a module enables it — no enable flag.
      options.hostConfig.emulators.nxOptimizer = {
        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.nx-optimizer;
          defaultText = lib.literalExpression "self.packages.<system>.nx-optimizer";
          description = "Pinned NX Optimizer package (built in modules/packages/nx-optimizer.nix).";
        };
      };

      # No Game Mode Tile: it is a set-up-then-play tool, launched from a
      # desktop-mode app menu (the package carries its own .desktop entry).
      config = {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
