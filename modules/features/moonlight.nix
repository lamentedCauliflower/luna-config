# Moonlight, the client half of the game streaming setup whose host half is
# nixosModules.gameStreaming on cleoDesktop (docs/adr/0006).
#
# Imported by mewoSteamdeck, where it surfaces as a Game Mode Tile so the stream
# is reachable from Gaming Mode without ever visiting Desktop Mode. Nothing here
# is Deck-specific, so any Steam host can import it.
{ ... }:
{
  flake.nixosModules.moonlight =
    { pkgs, ... }:
    let
      # The package ships only a scalable icon, and Steam's shortcuts.vdf wants a
      # raster one — an unsupported icon yields a blank tile rather than a build
      # error, which is a silent papercut. Render it once at build time instead.
      moonlightIcon =
        pkgs.runCommand "moonlight-tile-icon.png" { nativeBuildInputs = [ pkgs.librsvg ]; }
          ''
            rsvg-convert -w 256 -h 256 \
              -o $out \
              ${pkgs.moonlight-qt}/share/icons/hicolor/scalable/apps/moonlight.svg
          '';
    in
    {
      environment.systemPackages = [ pkgs.moonlight-qt ];

      hostConfig.steamShortcuts.shortcuts.Moonlight = {
        exe = "${pkgs.moonlight-qt}/bin/moonlight";
        icon = "${moonlightIcon}";

        # The tile opens Moonlight's own UI rather than streaming straight away.
        # `moonlight stream cleo "Steam Big Picture"` would launch directly, but
        # it fails to nothing when the host is asleep or the client is not yet
        # paired, whereas the UI shows the host list, handles pairing, and is
        # gamepad-navigable in Gaming Mode. To switch to direct launch later,
        # set: launchOptions = ''stream cleo "Steam Big Picture"'';
        #
        # Overlay off: this tile is a window onto a remote session that has its
        # own Steam overlay, and stacking the local one over it captures input
        # for the wrong Steam. Screenshots and the overlay still work on the
        # host side of the stream.
        allowOverlay = false;
      };
    };
}
