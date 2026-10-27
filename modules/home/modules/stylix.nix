{ username, ... }:
{
  flake.homeModules.stylix =
    {
      pkgs,
      config,
      ...
    }:
    {
      stylix = {
        enable = true;
        base16Scheme = "${pkgs.base16-schemes}/share/themes/deep-oceanic-next.yaml";
        targets.librewolf.profileNames = [ username ];
        image = ../../../assets/wallpaper.png;
        # useGlobalPkgs ignores HM nixpkgs.overlays, and home-manager now
        # asserts on them. Stylix only auto-disables this when enabled at the
        # NixOS level, which it isn't here.
        overlays.enable = false;
      };

    };
}
