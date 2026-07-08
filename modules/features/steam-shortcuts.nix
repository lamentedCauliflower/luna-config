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
          # Force XWayland. Gaming Mode's focus handoff only tracks XWayland
          # windows (it tags them with the STEAM_GAME atom via the X11-only
          # overlay). A native-Wayland Chromium renders straight to gamescope-0
          # and never produces a focusable window, so gamescope shows "Launching"
          # forever. --ozone-platform=x11 keeps the window on the :1 XWayland
          # that Gaming Mode focuses. (Verified on-device: wayland => no window
          # on :1 => not in GAMESCOPE_FOCUSABLE_WINDOWS; x11 => window maps.)
          #
          # --password-store=basic: Game Mode runs no keyring daemon, so
          # Chromium's startup Secret Service D-Bus call blocks forever (browser
          # stuck at the zygote, no window). basic skips the keyring — the same
          # thing Steam's own webhelper does. Verified: without it the browser
          # hangs in recv on the session bus; with it, 10 procs + focused window.
          LaunchOptions = "--ozone-platform=x11 --password-store=basic";
        }
        {
          AppName = "LibreWolf";
          Exe = "${librewolf}/bin/librewolf";
          StartDir = "${librewolf}/bin/";
          icon = "${librewolf}/share/icons/hicolor/128x128/apps/librewolf.png";
          # Steam's gameoverlayrenderer.so LD_PRELOAD deadlocks LibreWolf's
          # startup (it hangs on a futex before mapping a window — verified
          # on-device: overlay on => hang, overlay off => window maps). Chromium
          # tolerates the overlay, Firefox-based LibreWolf does not, so disable
          # it just here.
          AllowOverlay = 0;
        }
        {
          AppName = "Jellyfin";
          Exe = "${pkgs.jellyfin-media-player}/bin/jellyfin-desktop";
          StartDir = "${pkgs.jellyfin-media-player}/bin/";
          # Only a scalable SVG ships; Steam may show a blank tile (set grid art
          # in Steam if so) but it is not a build error.
          icon = "${pkgs.jellyfin-media-player}/share/icons/hicolor/scalable/apps/org.jellyfin.JellyfinDesktop.svg";
          # 10-foot TV UI, fullscreen — the console-style layout for Game Mode.
          LaunchOptions = "--fullscreen --tv";
          # Same overlay deadlock as LibreWolf: with Steam's overlay injected the
          # Qt/QtWebEngine app hangs before mapping its main window (only a Qt
          # clipboard-owner window appears). Verified: overlay off => "Jellyfin"
          # window maps. Disable the overlay here too.
          AllowOverlay = 0;
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
