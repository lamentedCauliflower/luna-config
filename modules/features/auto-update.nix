{ ... }:
{
  flake.nixosModules.autoUpdate =
    { config, lib, ... }:
    let
      cfg = config.hostConfig.autoUpdate;
    in
    {
      options.hostConfig.autoUpdate = {
        flakePath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to flake used for auto-upgrade runs.";
        };
      };

      config = {
        assertions = [
          {
            assertion = cfg.flakePath != null;
            message = "autoUpdate.flakePath must be set when auto updates are enabled.";
          }
        ];

        system.autoUpgrade = {
          enable = true;
          dates = "04:00";
          randomizedDelaySec = "0";
          flake = cfg.flakePath;
          operation = "switch";
          allowReboot = true;
        };
      };
    };

}
