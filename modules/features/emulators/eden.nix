{ self, username, ... }:
{
  flake.nixosModules.eden =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.emulators.eden;

      emu = "/mnt/media/Games/Emulation";

      # qt-config.ini seed. Unlike Ryujinx's Config.json — where a partial seed
      # NREs at startup — a partial ini is safe: Eden reads missing keys with
      # built-in defaults and rewrites the full file on first exit. Two format
      # rules, both verified against Eden's source (frontend_common/config.cpp
      # + qt_common/config/qt_config.cpp):
      #
      # 1. Settings that HAVE a built-in default (nand_directory,
      #    sdmc_directory) also read a `key\default` marker whose fallback is
      #    TRUE — a seeded value without `key\default=false` is silently
      #    ignored. Array `path` entries are read without a default, so they
      #    need no marker.
      # 2. A non-empty gamedirs array suppresses Eden's auto-added
      #    SDMC/UserNAND/SysNAND game-list entries, so the seed re-adds them
      #    before the rom dir.
      #
      # NAND + SDMC live on the media Saves share (so installed titles' saves
      # land there); DLC + title updates are external content dirs — Eden scans
      # them directly, nothing is installed into NAND (the Ryujinx
      # autoload_dirs equivalent).
      configSeed = pkgs.writeText "eden-qt-config-seed.ini" ''
        [Data%20Storage]
        nand_directory\default=false
        nand_directory=${emu}/Saves/nintendo-switch/eden/Nand
        sdmc_directory\default=false
        sdmc_directory=${emu}/Saves/nintendo-switch/eden/SD Card

        [UI]
        Paths\gamedirs\1\path=SDMC
        Paths\gamedirs\2\path=UserNAND
        Paths\gamedirs\3\path=SysNAND
        Paths\gamedirs\4\path=${emu}/Roms/nintendo-switch
        Paths\gamedirs\size=4
        Paths\external_content_dirs\1\path=${emu}/DLC/nintendo-switch
        Paths\external_content_dirs\2\path=${emu}/Updates/nintendo-switch
        Paths\external_content_dirs\size=2
      '';

      edenGameMode = pkgs.writeShellScriptBin "eden-gamemode" ''
        # Force Qt onto XWayland: gamescope's focus handoff only tracks X11
        # windows, so a native-Wayland Qt window renders to gamescope-0 and never
        # gets focused ("Launching" forever). Hiding the Wayland socket makes Qt
        # fall back to xcb; QT_QPA_PLATFORM=xcb makes it explicit. Verify on-device.
        unset WAYLAND_DISPLAY
        export QT_QPA_PLATFORM=xcb
        exec ${cfg.package}/bin/eden "$@"
      '';
    in
    {
      # Repo standard: importing a module enables it — no enable flag.
      options.hostConfig.emulators.eden = {
        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.eden;
          defaultText = lib.literalExpression "self.packages.<system>.eden";
          description = "Pinned Eden package (built in modules/packages/eden.nix).";
        };
      };

      config = {
        environment.systemPackages = [ cfg.package ];

        # Game Mode Tile; importing this module requires the steamShortcuts
        # module on the same host (see docs/adr/0003).
        hostConfig.steamShortcuts.shortcuts.Eden = {
          exe = "${edenGameMode}/bin/eden-gamemode";
          # Only a scalable SVG ships; Steam may show a blank tile (set grid art
          # in Steam if so) but it is not a build error.
          icon = "${cfg.package}/share/icons/hicolor/scalable/apps/eden.svg";
          # Qt emulator UI. If it hangs before mapping a window under the Steam
          # overlay LD_PRELOAD, set allowOverlay = false here. Verify on-device.
        };

        home-manager.users.${username} =
          { config, lib, ... }:
          {
            # prod.keys/title.keys shared with Ryujinx via the media BIOS dir.
            home.file.".local/share/eden/keys".source =
              config.lib.file.mkOutOfStoreSymlink "${emu}/BIOS/nintendo-switch";

            # NAND/SDMC (and with them, saves) are redirected to the media share
            # by configSeed's [Data%20Storage] — no nand symlink needed. The
            # share dirs are eden-specific (Eden's save format differs from
            # Ryujinx, so they must not share a tree).
            #
            # Seed qt-config.ini once (see configSeed above); Eden owns the
            # file after first launch. Firmware: install in-app.
            home.activation.edenSeedConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              cfg="$HOME/.config/eden/qt-config.ini"
              if [ ! -e "$cfg" ]; then
                run mkdir -p "$HOME/.config/eden"
                run install -m600 ${configSeed} "$cfg"
              fi
            '';
          };
      };
    };
}
