{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # --- pin (bump version + hash together) ------------------------------
      #   nix-prefetch-url <url>
      #   nix hash convert --hash-algo sha256 --to sri <printed-hash>
      # Not in nixpkgs; this wraps the upstream Linux x64 AppImage. The app's
      # own electron-updater can't replace a store path, so bump here.
      version = "0.3.9";
      src = pkgs.fetchurl {
        url = "https://github.com/amosblomqvist/learnharness/releases/download/v${version}/LearnHarness-${version}-x86_64.AppImage";
        hash = "sha256-mlSd5V/RojGh9m1ZLOCkCKattj8H1Tz7icnWbiZZ4IU=";
      };

      appimageContents = pkgs.appimageTools.extract {
        pname = "learnharness";
        inherit version src;
      };
    in
    {
      packages.learnharness = pkgs.appimageTools.wrapType2 {
        pname = "learnharness";
        inherit version src;
        extraInstallCommands = ''
          install -Dm444 ${appimageContents}/usr/share/icons/hicolor/512x512/apps/learnharness.png \
            $out/share/icons/hicolor/512x512/apps/learnharness.png
          install -Dm444 ${appimageContents}/learnharness.desktop \
            $out/share/applications/learnharness.desktop
          substituteInPlace $out/share/applications/learnharness.desktop \
            --replace-fail 'Exec=AppRun' 'Exec=learnharness'
        '';
        meta = {
          description = "LearnHarness (AI agent harness for learning), wrapped upstream AppImage";
          homepage = "https://github.com/amosblomqvist/learnharness";
          license = pkgs.lib.licenses.agpl3Only;
          mainProgram = "learnharness";
          platforms = [ "x86_64-linux" ];
        };
      };
    };
}
