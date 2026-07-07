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
      };

    };
}
