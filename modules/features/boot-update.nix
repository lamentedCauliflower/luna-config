{ ... }:
{
  flake.nixosModules.bootUpdate =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.bootUpdate;
    in
    {
      options.hostConfig.bootUpdate = {
        enable = lib.mkEnableOption "nh os boot on boot (daily, persistent)";

        flakePath = lib.mkOption {
          type = lib.types.str;
          description = "Flake URI passed to `nh os boot` (e.g. github:owner/repo).";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.nos-update = {
          description = "Run nh os boot (set next-boot generation)";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          path = with pkgs; [
            nh
            nix
            git
            openssh
            gnutar
            gzip
            coreutils
          ];

          environment = {
            NH_FLAKE = cfg.flakePath;
          };

          serviceConfig = {
            Type = "oneshot";
            User = "root";
          };

          # No --update: the flake is a remote GitHub URI, so the lock file
          # cannot be rewritten here; input updates happen on the dev machine.
          script = ''
            nh os boot
          '';
        };

        systemd.timers.nos-update = {
          description = "Daily nos-update, runs on boot if missed";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "5min";
            Unit = "nos-update.service";
          };
        };
      };
    };
}
