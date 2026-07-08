{ username, ... }:
{
  flake.nixosModules.steamShortcuts =
    { pkgs, config, ... }:
    let
      # LibreWolf's extension policies live in the home-manager-wrapped
      # finalPackage (its distribution/policies.json), NOT the bare pkgs.librewolf.
      # The shortcut must launch the wrapped binary or Gaming Mode gets a browser
      # with zero force-installed extensions.
      librewolf = config.home-manager.users.${username}.programs.librewolf.finalPackage;

      # ponytail: icon sizes are best-effort store paths; a missing size only
      # yields a blank tile (not a build error) — bump if a tile shows blank.
      shortcuts = [
        {
          AppName = "Chromium";
          Exe = "${pkgs.ungoogled-chromium}/bin/chromium";
          StartDir = "${pkgs.ungoogled-chromium}/bin/";
          icon = "${pkgs.ungoogled-chromium}/share/icons/hicolor/256x256/apps/chromium.png";
          # Gaming Mode is a nested gamescope Wayland compositor. Chromium's
          # default XWayland path leaves the top-level window unmapped there, so
          # gamescope shows a black screen forever ("stalls"). Render natively
          # into gamescope's Wayland instead (what SteamOS's own Chrome does).
          # If a GPU-context stall persists on this hardware, fall back to
          # "--ozone-platform=x11 --disable-gpu" (see steam-runtime#830).
          LaunchOptions = "--ozone-platform=wayland --enable-features=UseOzonePlatform";
        }
        {
          AppName = "LibreWolf";
          Exe = "${librewolf}/bin/librewolf";
          StartDir = "${librewolf}/bin/";
          icon = "${librewolf}/share/icons/hicolor/128x128/apps/librewolf.png";
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
