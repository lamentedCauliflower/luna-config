{ username, ... }:
{
  flake.nixosModules.steamShortcuts =
    { pkgs, ... }:
    let
      # Non-Steam Shortcuts for the two browsers. Plain binary launch, no flags —
      # Steam's gamescope handles the window in Gaming Mode.
      # ponytail: icon sizes are best-effort store paths; a missing size only
      # yields a blank tile (not a build error) — bump if a tile shows blank.
      shortcuts = [
        {
          AppName = "Chromium";
          Exe = "${pkgs.ungoogled-chromium}/bin/chromium";
          StartDir = "${pkgs.ungoogled-chromium}/bin/";
          icon = "${pkgs.ungoogled-chromium}/share/icons/hicolor/256x256/apps/chromium.png";
        }
        {
          AppName = "LibreWolf";
          Exe = "${pkgs.librewolf}/bin/librewolf";
          StartDir = "${pkgs.librewolf}/bin/";
          icon = "${pkgs.librewolf}/share/icons/hicolor/128x128/apps/librewolf.png";
        }
      ];

      shortcutsJson = pkgs.writeText "steam-nonsteam-shortcuts.json" (builtins.toJSON shortcuts);

      writer = pkgs.writers.writePython3 "steam-nonsteam-shortcuts" {
        libraries = [ pkgs.python3Packages.vdf ];
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./steam-shortcuts-writer.py);
    in
    {
      # Steam overwrites shortcuts.vdf from memory on exit, so the merge must run
      # while Steam is not running. multi-user.target is ordered before the
      # graphical session that launches Steam, and User=${username} writes into
      # the user's own userdata dirs. An account's shortcut only appears after
      # that account has logged into Steam once (its userdata dir must exist).
      systemd.services.steam-nonsteam-shortcuts = {
        description = "Merge declarative non-Steam browser shortcuts into shortcuts.vdf";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          ExecStart = "${writer} ${shortcutsJson}";
        };
      };
    };
}
