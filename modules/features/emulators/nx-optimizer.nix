{ ... }:
{
  flake.nixosModules.nxOptimizer =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.emulators.nxOptimizer;

      # --- pin (bump version + hash together) ------------------------------
      #   nix-prefetch-url <url>
      #   nix hash convert --hash-algo sha256 --to sri <printed-hash>
      version = "3.2.0";
      src = pkgs.fetchurl {
        url = "https://github.com/MaxLastBreath/nx-optimizer/releases/download/manager-${version}/NX.Optimizer.${version}.AppImage";
        hash = "sha256-a29nCz9KbGFd2vhrMMMUUycKrWqIPCBEO7tFoyaxdNg=";
      };

      # Despite the .AppImage name this is a PyInstaller onefile ELF (a Tkinter
      # GUI — ttkbootstrap + tkinterdnd2), NOT a squashfs AppImage, so
      # appimageTools cannot extract it. Install it executable and run it inside
      # an FHS env so /lib64/ld-linux and the X/Tk libraries its bundled Python
      # dlopens are present. xclip is the documented clipboard dependency.
      nxoBin = pkgs.runCommandLocal "nx-optimizer-bin" { } ''
        install -Dm755 ${src} $out/bin/nx-optimizer-unwrapped
      '';

      nxOptimizer = pkgs.buildFHSEnv {
        pname = "nx-optimizer";
        inherit version;
        targetPkgs =
          p:
          (with p; [
            xclip
            tk
            tcl
            fontconfig
            freetype
            zlib
            openssl
          ])
          ++ (with p.xorg; [
            libX11
            libXext
            libXft
            libXrender
            libxcb
          ]);
        runScript = "${nxoBin}/bin/nx-optimizer-unwrapped";
      };

      # PyInstaller ships no usable .desktop; add one so it is launchable from a
      # desktop-mode app menu (it is a set-up-then-play tool, not a Game Mode
      # tile). Auto-detects Ryujinx at ~/.config/Ryujinx and writes mods there.
      desktopItem = pkgs.makeDesktopItem {
        name = "nx-optimizer";
        desktopName = "NX Optimizer";
        comment = "Install UltraCam mods / graphics presets into Ryujinx";
        exec = "nx-optimizer";
        terminal = false;
        categories = [
          "Game"
          "Utility"
        ];
      };
    in
    {
      options.hostConfig.emulators.nxOptimizer = {
        enable = lib.mkEnableOption "NX Optimizer (UltraCam mod installer for Switch emulators)";

        package = lib.mkOption {
          type = lib.types.package;
          default = nxOptimizer;
          defaultText = lib.literalExpression "the FHS-wrapped NX Optimizer";
          description = "Pinned NX Optimizer package.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          desktopItem
        ];
      };
    };
}
