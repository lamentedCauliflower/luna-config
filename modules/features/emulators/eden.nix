{ self, username, ... }:
{
  flake.nixosModules.eden =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.emulators.eden;

      emu = "/mnt/media/Games/Emulation";

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
          { config, ... }:
          {
            # prod.keys/title.keys shared with Ryujinx via the media BIOS dir.
            home.file.".local/share/eden/keys".source =
              config.lib.file.mkOutOfStoreSymlink "${emu}/BIOS/nintendo-switch";

            # Saves on the media share, in an eden-specific subdir (Eden's save
            # format differs from Ryujinx, so they must not share a tree).
            home.file.".local/share/eden/nand/user/save".source =
              config.lib.file.mkOutOfStoreSymlink "${emu}/Saves/nintendo-switch/eden";

            # Roms: add ${emu}/Roms/nintendo-switch as a Game Directory in the
            # GUI on first run (Eden stores it in qt-config.ini, which it owns
            # and rewrites — not seeded here). Firmware: install in-app. Updates
            # /DLC: install to NAND from the files under ${emu}/Updates and /DLC.
          };
      };
    };
}
