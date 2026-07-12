{ username, ... }:
{
  flake.nixosModules.eden =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.emulators.eden;

      emu = "/mnt/media/Games/Emulation";

      # --- pin (bump version + hash together) ------------------------------
      #   nix-prefetch-url <url>
      #   nix hash convert --hash-algo sha256 --to sri <printed-hash>
      # amd64-clang-pgo = generic modern x86_64, PGO-optimised; runs on both the
      # desktop and the Deck (there are Deck-specific builds, but one is simpler).
      version = "0.2.1";
      src = pkgs.fetchurl {
        url = "https://stable.eden-emu.dev/v${version}/Eden-Linux-v${version}-amd64-clang-pgo.AppImage";
        hash = "sha256-eii/mIsGSIMZiXIr26qQqzE3G0A4CBmYE+DqfIslum0=";
      };

      # Eden's .AppImage carries the type-2 magic but its payload is DwarFS, not
      # squashfs, so appimageTools can't extract it ("no valid SQUASHFS
      # superblock"). Extract the DwarFS image with dwarfsextract (offset
      # auto-detected, so it survives version bumps), then FHS-wrap the AppDir.
      edenAppDir = pkgs.runCommand "eden-${version}-appdir" {
        nativeBuildInputs = [ pkgs.dwarfs ];
      } ''
        mkdir -p $out
        dwarfsextract --input=${src} --image-offset=auto --output=$out
      '';

      eden = pkgs.appimageTools.wrapAppImage {
        pname = "eden";
        inherit version;
        src = edenAppDir;
        # Qt (the rest is bundled in the AppDir) needs libxcb-cursor + xkbcommon
        # for its xcb platform plugin on Qt 6.5+, or it fails to start with a
        # visible window; the Vulkan renderer needs the loader. Extend if a GPU
        # backend is missing on-device.
        extraPkgs = p: [
          p.vulkan-loader
          p.xorg.xcbutilcursor
          p.libxkbcommon
        ];
        extraInstallCommands = ''
          install -Dm444 ${edenAppDir}/dev.eden_emu.eden.svg \
            $out/share/icons/hicolor/scalable/apps/eden.svg
          install -Dm444 ${edenAppDir}/dev.eden_emu.eden.desktop \
            $out/share/applications/eden.desktop
          substituteInPlace $out/share/applications/eden.desktop \
            --replace-warn 'Icon=dev.eden_emu.eden' 'Icon=eden'
        '';
      };
    in
    {
      options.hostConfig.emulators.eden = {
        enable = lib.mkEnableOption "Eden (Yuzu-lineage Switch emulator)";

        package = lib.mkOption {
          type = lib.types.package;
          default = eden;
          defaultText = lib.literalExpression "the FHS-wrapped Eden AppImage";
          description = "Pinned Eden package.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

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
