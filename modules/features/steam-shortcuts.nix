{ username, ... }:
{
  flake.nixosModules.steamShortcuts =
    { pkgs, config, lib, ... }:
    let
      # LibreWolf's extension policies live in the home-manager-wrapped
      # finalPackage (its distribution/policies.json), NOT the bare pkgs.librewolf.
      # The shortcut must launch the wrapped binary or Gaming Mode gets a browser
      # with zero force-installed extensions.
      librewolf = config.home-manager.users.${username}.programs.librewolf.finalPackage;

      # jellyfin-media-player is QtWebEngine; under Steam's runtime its Chromium
      # sandbox deadlocks the process at startup (single-thread futex, no
      # window). QtWebEngine reads QTWEBENGINE_DISABLE_SANDBOX from the env,
      # which a Steam LaunchOptions arg can't set, so wrap it. Verified on a
      # clean boot: with it the Jellyfin window maps and is focused.
      jellyfin = pkgs.writeShellScriptBin "jellyfin-gamemode" ''
        export QTWEBENGINE_DISABLE_SANDBOX=1
        exec ${pkgs.jellyfin-media-player}/bin/jellyfin-desktop "$@"
      '';

      # The three flags Chromium needs to open at all in Gaming Mode (see the
      # Chromium tile below for why each is required). Shared so the plain
      # browser tile and the YouTube kiosk tile can't drift apart.
      chromium = "${pkgs.ungoogled-chromium}/bin/chromium";
      chromiumGameMode = "--ozone-platform=x11 --password-store=basic --no-sandbox";

      # Ryujinx tile only exists when the emulator is enabled on this host (set
      # by allEmulators). `or false` keeps this safe on a host that has
      # steamShortcuts but not allEmulators — then the option is undeclared and
      # the tile is dropped. Both are lazy: ryujinxPkg/ryujinxGameMode are only
      # forced when the tile is actually included.
      ryujinxEnabled = config.hostConfig.emulators.ryujinx.enable or false;
      ryujinxPkg = config.hostConfig.emulators.ryujinx.package;
      ryujinxGameMode = pkgs.writeShellScriptBin "ryujinx-gamemode" ''
        # Avalonia picks Wayland when WAYLAND_DISPLAY is set and renders straight
        # to gamescope-0, which Gaming Mode's X11-only focus handoff never tracks
        # (tile stuck "Launching"). Hide the Wayland socket so it falls back to
        # the :1 XWayland Gaming Mode focuses — same rationale as the Chromium
        # --ozone-platform=x11 tile. Verify on-device.
        unset WAYLAND_DISPLAY
        exec ${ryujinxPkg}/bin/ryujinx-canary "$@"
      '';

      # Eden tile, same enable-gating and XWayland rationale as Ryujinx.
      edenEnabled = config.hostConfig.emulators.eden.enable or false;
      edenPkg = config.hostConfig.emulators.eden.package;
      edenGameMode = pkgs.writeShellScriptBin "eden-gamemode" ''
        # Force Qt onto XWayland: gamescope's focus handoff only tracks X11
        # windows, so a native-Wayland Qt window renders to gamescope-0 and never
        # gets focused ("Launching" forever). Hiding the Wayland socket makes Qt
        # fall back to xcb; QT_QPA_PLATFORM=xcb makes it explicit. Verify on-device.
        unset WAYLAND_DISPLAY
        export QT_QPA_PLATFORM=xcb
        exec ${edenPkg}/bin/eden "$@"
      '';

      # ponytail: icon sizes are best-effort store paths; a missing size only
      # yields a blank tile (not a build error) — bump if a tile shows blank.
      shortcuts = [
        {
          AppName = "Chromium";
          Exe = chromium;
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
          #
          # --no-sandbox: under Steam's runtime the zygote can't set up its
          # namespace sandbox, so the browser process deadlocks in recvmsg
          # waiting for a zygote fork that never completes (only visible on a
          # cold boot — a warm session had the services it needed). Steam's own
          # webhelper runs --no-sandbox for the same reason. Verified on a clean
          # boot: without it the browser hangs at the zygote; with it, 14 procs
          # + GAMESCOPE_FOCUSED_APP.
          LaunchOptions = chromiumGameMode;
        }
        {
          # YouTube in Chromium kiosk (fullscreen, no browser UI). Shares the
          # default Chromium profile, so it inherits uBlock Origin + SponsorBlock
          # + DeArrow (ad-free, sponsor-skipping). Gaming Mode runs one app at a
          # time, so sharing the profile with the Chromium tile can't clash.
          AppName = "YouTube";
          Exe = chromium;
          StartDir = "${pkgs.ungoogled-chromium}/bin/";
          icon = "${pkgs.ungoogled-chromium}/share/icons/hicolor/256x256/apps/chromium.png";
          LaunchOptions = "${chromiumGameMode} --kiosk https://www.youtube.com/";
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
          Exe = "${jellyfin}/bin/jellyfin-gamemode";
          StartDir = "${jellyfin}/bin/";
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
      ]
      ++ lib.optionals ryujinxEnabled [
        {
          AppName = "Ryujinx";
          Exe = "${ryujinxGameMode}/bin/ryujinx-gamemode";
          StartDir = "${ryujinxGameMode}/bin/";
          icon = "${ryujinxPkg}/share/icons/hicolor/256x256/apps/ryujinx-canary.png";
          # Avalonia emulator UI. If it hangs before mapping a window under the
          # Steam overlay LD_PRELOAD like LibreWolf/Jellyfin did, set
          # AllowOverlay = 0 here — left on for now since the overlay is useful
          # in-game. Verify on-device.
        }
      ]
      ++ lib.optionals edenEnabled [
        {
          AppName = "Eden";
          Exe = "${edenGameMode}/bin/eden-gamemode";
          StartDir = "${edenGameMode}/bin/";
          # Only a scalable SVG ships; Steam may show a blank tile (set grid art
          # in Steam if so) but it is not a build error.
          icon = "${edenPkg}/share/icons/hicolor/scalable/apps/eden.svg";
          # Qt emulator UI. If it hangs before mapping a window under the Steam
          # overlay LD_PRELOAD, set AllowOverlay = 0 here. Verify on-device.
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
