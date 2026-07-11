{ username, ... }:
{
  flake.nixosModules.ryujinxCanary =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.emulators.ryujinx;

      emu = "/mnt/media/Games/Emulation";
      romsDir = "${emu}/Roms/nintendo-switch";

      # --- Canary pin (bump version + hash together) -----------------------
      # Canary is not in nixpkgs; this wraps the prebuilt Linux x64 AppImage.
      # The GitLab is Anubis-gated, but *direct asset downloads* bypass the
      # challenge, so Nix's fetcher works. To bump:
      #   nix-prefetch-url https://git.ryujinx.app/Ryubing/Canary/releases/download/<ver>/ryujinx-canary-<ver>-x64.AppImage
      #   nix hash convert --hash-algo sha256 --to sri <printed-hash>
      version = "1.3.334";
      src = pkgs.fetchurl {
        url = "https://git.ryujinx.app/Ryubing/Canary/releases/download/${version}/ryujinx-canary-${version}-x64.AppImage";
        hash = "sha256-SIrL2MCmHzFrNXz5+HYmwJ7by9ioVBw0F+EqKj/zi6k=";
      };

      # Icon + .desktop live inside the AppImage squashfs; extract to expose
      # them at $out/share (Desktop-Mode launcher + Steam Game Mode tile icon).
      appimageContents = pkgs.appimageTools.extractType2 {
        pname = "ryujinx-canary";
        inherit version src;
      };

      ryujinx = pkgs.appimageTools.wrapType2 {
        pname = "ryujinx-canary";
        inherit version src;
        # SDL3, ffmpeg, Skia and soundio are bundled inside the AppImage; the
        # GPU driver/loader libs are not, so add them to the FHS env. Extend
        # here if a game fails to find a Vulkan/GL driver on-device.
        #
        # icu: .NET needs libicu for globalization or it FailFast-crashes at
        # Program.Main before drawing a window ("Couldn't find a valid ICU
        # package"). appimageTools' default FHS does not include it.
        extraPkgs = p: [
          p.icu
          p.vulkan-loader
          p.libGL
        ];
        extraInstallCommands = ''
          install -Dm444 ${appimageContents}/usr/share/icons/hicolor/256x256/apps/app.ryujinx.Ryujinx.png \
            $out/share/icons/hicolor/256x256/apps/ryujinx-canary.png
          install -Dm444 ${appimageContents}/usr/share/applications/app.ryujinx.Ryujinx.desktop \
            $out/share/applications/ryujinx-canary.desktop
          substituteInPlace $out/share/applications/ryujinx-canary.desktop \
            --replace-warn 'Exec=Ryujinx.sh' 'Exec=ryujinx-canary' \
            --replace-warn 'Icon=app.ryujinx.Ryujinx' 'Icon=ryujinx-canary'
        '';
      };

      # Keys verified on-device against a Ryujinx-generated Config.json (Canary
      # 1.3.334, config `version` 73):
      #   game_dirs     - dirs scanned for roms
      #   autoload_dirs - dirs scanned for DLC + title updates (one list, both)
      # The `version` field is REQUIRED: without it Ryujinx rejects the file as
      # invalid, renames it *.invalid and loads defaults (so nothing applies).
      # A partial config with `version` present IS accepted (unknown fields
      # default). Seed only applies on first run (activation writes if absent);
      # a future Canary that bumps the schema migrates this on load. If a bump
      # ever rejects it, refresh `version` from a freshly generated Config.json.
      configSeed = pkgs.writeText "ryujinx-config-seed.json" (
        builtins.toJSON {
          version = 73;
          game_dirs = [ romsDir ];
          autoload_dirs = [
            "${emu}/DLC/nintendo-switch"
            "${emu}/Updates/nintendo-switch"
          ];
        }
      );
    in
    {
      options.hostConfig.emulators.ryujinx = {
        enable = lib.mkEnableOption "Ryujinx Canary (Ryubing) Switch emulator";

        package = lib.mkOption {
          type = lib.types.package;
          default = ryujinx;
          defaultText = lib.literalExpression "the pinned Ryujinx Canary AppImage wrapper";
          description = "Pinned Ryujinx Canary package; shared with the steamShortcuts Game Mode tile.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        home-manager.users.${username} =
          { config, lib, ... }:
          {
            # Only the Ryujinx-managed dirs are redirected. Saves live under
            # <base>/bis/user/save; keys under <base>/system. Roms/DLC/Updates are
            # NOT stored by Ryujinx — it references them by path (see configSeed).
            #
            # Saves -> shared NFS media. NOTE: both hosts point at the SAME save
            # tree, so don't run the same title on both hosts at once (clobber).
            home.file.".config/Ryujinx/bis/user/save".source =
              config.lib.file.mkOutOfStoreSymlink "${emu}/Saves/nintendo-switch/ryujinx";

            # prod.keys/title.keys shared across hosts via the media BIOS dir.
            # Firmware is installed in-app per host (Tools > Install Firmware,
            # from ${emu}/BIOS/nintendo-switch/firmware).
            home.file.".config/Ryujinx/system".source =
              config.lib.file.mkOutOfStoreSymlink "${emu}/BIOS/nintendo-switch";

            # Seed Config.json once; Ryujinx owns it after first launch (it
            # rewrites the file on exit, so we must not manage it as a read-only
            # store symlink). Only writes if absent.
            home.activation.ryujinxSeedConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              cfg="$HOME/.config/Ryujinx/Config.json"
              if [ ! -e "$cfg" ]; then
                run mkdir -p "$HOME/.config/Ryujinx"
                run install -m600 ${configSeed} "$cfg"
              fi
            '';
          };
      };
    };
}
