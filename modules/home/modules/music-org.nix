{ ... }:
{
  flake.homeModules.musicOrganisation =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          beets
          picard
          tidal-dl
          puddletag
          nicotine-plus
        ];
      };
    };
}
