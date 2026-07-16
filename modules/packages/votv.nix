{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # --- pin (bump version + hash together) ------------------------------
      # Pin source: https://archive.votv.dev/manifest.json — the official
      # build archive publishes every build's sha256, so no prefetch needed:
      # pick a "stable"-channel build, copy its version and sha256 (hex →
      # `nix hash convert --hash-algo sha256 --to sri <hex>`).
      #
      # Saves live in the Steam-owned Proton prefix (see the votv feature
      # module) and pre-alpha updates can break them — back the save dir up
      # before bumping this pin.
      version = "0.9.0n";
      # Archive filenames are the version with the dots dropped
      # (0.9.0n -> 090n.7z, 0.8.0_0016 -> 080_0016.7z).
      archiveName = "${builtins.replaceStrings [ "." ] [ "" ] version}.7z";
      src = pkgs.fetchurl {
        # r2.votv.dev is the manifest's download.baseUrl: a plain R2 bucket,
        # stable URLs, no expiring signatures (unlike the itch.io mirror).
        url = "https://r2.votv.dev/archive/votv/${archiveName}";
        hash = "sha256-S4Daywkm0h1mUMaELhd4XD2dvqreXioxWTRsObuiB5k=";
      };
    in
    {
      packages.votv = pkgs.stdenvNoCC.mkDerivation {
        pname = "votv";
        inherit version src;

        nativeBuildInputs = [
          pkgs.p7zip
          pkgs.icoutils
        ];

        unpackPhase = ''
          7z x -y $src >/dev/null
        '';

        # The archive layout has varied across releases (game tree at the
        # root vs. nested one folder down), so locate the dir holding
        # VotV.exe instead of hardcoding it.
        installPhase = ''
          exe=$(find . -maxdepth 3 -name VotV.exe -print -quit)
          if [ -z "$exe" ]; then
            echo "VotV.exe not found in archive — layout changed?" >&2
            exit 1
          fi
          gamedir=$(dirname "$exe")

          mkdir -p $out/share/games
          cp -r "$gamedir" $out/share/games/votv

          # r2modman's Linux Proton detection: an empty .forceproton marker in
          # the game root tells it to launch the game through Proton. The
          # game dir is store-read-only, so bake the marker in here instead of
          # letting r2modman/the user create it.
          touch $out/share/games/votv/.forceproton

          # Tile icon, extracted from the exe's embedded resources (largest
          # size wins). Best effort: a failure only costs the tile art (set
          # grid art in Steam if so), it is not a build error.
          mkdir icons
          if wrestool -x -t14 -o icons/votv.ico "$exe" 2>/dev/null \
             && icotool -x -o icons icons/votv.ico 2>/dev/null; then
            install -m444 "$(ls -S icons/*.png | head -1)" \
              $out/share/games/votv/votv.png
          else
            echo "warning: no icon extracted from VotV.exe" >&2
          fi
        '';

        meta = {
          description = "Voices of the Void (pre-alpha), from the official build archive";
          homepage = "https://votv.dev";
          license = pkgs.lib.licenses.unfree; # freeware, no redistribution licence
          platforms = [ "x86_64-linux" ]; # Windows build, run via Proton
        };
      };
    };
}
