{ ... }:
{
  flake.nixosModules.bootUpdate =
    { config, lib, ... }:
    let
      cfg = config.hostConfig.bootUpdate;
    in
    {
      options.hostConfig.bootUpdate = {
        enable = lib.mkEnableOption "daily nixos-rebuild boot from the flake (persistent)";

        flakePath = lib.mkOption {
          type = lib.types.str;
          description = "Flake URI to rebuild from (e.g. github:owner/repo).";
        };
      };

      # Was a hand-rolled `nh os boot` unit, but nh refuses to run as root
      # ("Don't run nh os as root"), so every run failed. The stock module runs
      # nixos-rebuild as root and is what lunaserver's autoUpdate already uses.
      # Only builds what's pushed: the lock is updated on the dev machine.
      config = lib.mkIf cfg.enable {
        system.autoUpgrade = {
          enable = true;
          flake = cfg.flakePath;
          operation = "boot";
          dates = "daily";
          # Desktops are often off at the scheduled time; run on next boot.
          persistent = true;
          randomizedDelaySec = "5min";
        };
      };
    };
}
