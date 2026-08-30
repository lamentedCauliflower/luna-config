{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Replays Sunshine's virtual uinput devices into KWin through
      # org_kde_kwin_fake_input. Needed because KWin's virtual backend has no
      # libinput at all, so uinput devices have no reader on a headless session
      # (see game-streaming.nix and docs/adr/0006).
      #
      # Deliberately NOT wrapped: KWin authorises the privileged fake_input
      # interface by matching /proc/<pid>/exe against an installed desktop
      # file's Exec, and a makeWrapper shim would break that match -- the exact
      # failure Sunshine's own wrapped binary hits.
      packages.kwin-uinput-bridge = pkgs.stdenv.mkDerivation {
        pname = "kwin-uinput-bridge";
        version = "0.1.0";

        dontUnpack = true;

        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.wayland-scanner
        ];
        buildInputs = [
          pkgs.wayland
          pkgs.libevdev
        ];

        buildPhase = ''
          runHook preBuild

          xml=${pkgs.kdePackages.plasma-wayland-protocols}/share/plasma-wayland-protocols/fake-input.xml
          wayland-scanner client-header "$xml" fake-input-client-protocol.h
          wayland-scanner private-code  "$xml" fake-input-protocol.c

          $CC -O2 -Wall -Wextra -Wno-unused-parameter \
            -o kwin-uinput-bridge \
            ${./kwin-uinput-bridge.c} fake-input-protocol.c \
            -I. $(pkg-config --cflags --libs wayland-client libevdev)

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm755 kwin-uinput-bridge $out/bin/kwin-uinput-bridge
          runHook postInstall
        '';

        meta = {
          description = "Replay Sunshine's uinput devices into KWin via fake_input";
          mainProgram = "kwin-uinput-bridge";
          platforms = lib.platforms.linux;
        };
      };
    };
}
