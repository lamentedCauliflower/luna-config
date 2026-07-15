{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
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
    in
    {
      packages.ryujinx-canary = pkgs.appimageTools.wrapType2 {
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
        meta = {
          description = "Ryujinx Canary (Ryubing) Switch emulator, wrapped upstream AppImage";
          mainProgram = "ryujinx-canary";
          platforms = [ "x86_64-linux" ];
        };
      };
    };
}
