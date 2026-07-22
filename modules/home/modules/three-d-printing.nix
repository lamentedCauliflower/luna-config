{ ... }:
{
  flake.homeModules.threeDPrinting =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          orca-slicer
          inkscape-with-extensions
          gimp
        ];
      };
    };
}
