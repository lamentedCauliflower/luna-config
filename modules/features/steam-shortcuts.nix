{ self, username, ... }:
{
  flake.nixosModules.steamShortcuts =
    { pkgs, config, lib, ... }:
    let
      cfg = config.hostConfig.steamShortcuts;

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

      # The writer consumes VDF-shaped objects ({ AppName, Exe, StartDir, icon,
      # LaunchOptions?, AllowOverlay?, CompatTool? }); the nix-side schema is
      # the nixified submodule below, mapped here in one place.
      shortcutsJson = pkgs.writeText "steam-nonsteam-shortcuts.json" (
        builtins.toJSON (
          lib.mapAttrsToList (name: sc: {
            AppName = name;
            Exe = sc.exe;
            StartDir = sc.startDir;
            icon = sc.icon;
            LaunchOptions = sc.launchOptions;
            AllowOverlay = if sc.allowOverlay then 1 else 0;
            CompatTool = sc.compatTool;
          }) cfg.shortcuts
        )
      );

      writer = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-shortcuts-writer;
    in
    {
      options.hostConfig.steamShortcuts = {
        shortcuts = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, config, ... }:
              {
                options = {
                  exe = lib.mkOption {
                    type = lib.types.str;
                    description = "Absolute path of the program the tile launches.";
                  };
                  startDir = lib.mkOption {
                    type = lib.types.str;
                    default = "${dirOf config.exe}/";
                    defaultText = lib.literalExpression ''"''${dirOf exe}/"'';
                    description = "Working directory Steam launches the program from.";
                  };
                  icon = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = ''
                      Icon path for the tile. Best-effort: a missing or
                      unsupported icon only yields a blank tile (not a build
                      error) — set grid art in Steam if so.
                    '';
                  };
                  launchOptions = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Steam LaunchOptions string appended to the invocation.";
                  };
                  allowOverlay = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = ''
                      Whether Steam's gameoverlayrenderer.so is LD_PRELOADed.
                      Disable for programs the overlay deadlocks before they map
                      a window (Firefox-based and QtWebEngine apps so far).
                    '';
                  };
                  compatTool = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    example = "proton_experimental";
                    description = ''
                      Steam compatibility tool forced for this shortcut, for
                      tiles whose exe is a Windows binary (see docs/adr/0004).
                      Written to config.vdf's CompatToolMapping keyed by the
                      shortcut's appid; null (the default) leaves the tile
                      launching natively.
                    '';
                  };
                };
              }
            )
          );
          default = { };
          description = ''
            Non-Steam Shortcuts to merge into every Steam account's
            shortcuts.vdf, keyed by tile name (the Steam AppName). Any module
            may add entries — each emulator module declares its own tile when
            imported (see docs/adr/0003).
          '';
        };
      };

      config = {
        hostConfig.steamShortcuts.shortcuts = {
          Chromium = {
            exe = chromium;
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
            launchOptions = chromiumGameMode;
          };
          YouTube = {
            # YouTube in Chromium kiosk (fullscreen, no browser UI). Shares the
            # default Chromium profile, so it inherits uBlock Origin + SponsorBlock
            # + DeArrow (ad-free, sponsor-skipping). Gaming Mode runs one app at a
            # time, so sharing the profile with the Chromium tile can't clash.
            exe = chromium;
            icon = "${pkgs.ungoogled-chromium}/share/icons/hicolor/256x256/apps/chromium.png";
            launchOptions = "${chromiumGameMode} --kiosk https://www.youtube.com/";
          };
          LibreWolf = {
            exe = "${librewolf}/bin/librewolf";
            icon = "${librewolf}/share/icons/hicolor/128x128/apps/librewolf.png";
            # Steam's gameoverlayrenderer.so LD_PRELOAD deadlocks LibreWolf's
            # startup (it hangs on a futex before mapping a window — verified
            # on-device: overlay on => hang, overlay off => window maps). Chromium
            # tolerates the overlay, Firefox-based LibreWolf does not, so disable
            # it just here.
            allowOverlay = false;
          };
          Jellyfin = {
            exe = "${jellyfin}/bin/jellyfin-gamemode";
            # Only a scalable SVG ships; Steam may show a blank tile (set grid art
            # in Steam if so) but it is not a build error.
            icon = "${pkgs.jellyfin-media-player}/share/icons/hicolor/scalable/apps/org.jellyfin.JellyfinDesktop.svg";
            # 10-foot TV UI, fullscreen — the console-style layout for Game Mode.
            launchOptions = "--fullscreen --tv";
            # Same overlay deadlock as LibreWolf: with Steam's overlay injected the
            # Qt/QtWebEngine app hangs before mapping its main window (only a Qt
            # clipboard-owner window appears). Verified: overlay off => "Jellyfin"
            # window maps. Disable the overlay here too.
            allowOverlay = false;
          };
        };

        # Steam overwrites shortcuts.vdf from memory on exit, so the merge must run
        # while Steam is not running. multi-user.target is ordered before the
        # graphical session that launches Steam, and User=${username} writes into
        # the user's own userdata dirs. An account's shortcut only appears after
        # that account has logged into Steam once (its userdata dir must exist).
        systemd.services.steam-nonsteam-shortcuts = lib.mkIf (cfg.shortcuts != { }) {
          description = "Merge declarative non-Steam browser shortcuts into shortcuts.vdf";
          wantedBy = [ "multi-user.target" ];
          before = [ "display-manager.service" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = username;
            ExecStart = "${lib.getExe writer} ${shortcutsJson}";
          };
        };
      };
    };
}
