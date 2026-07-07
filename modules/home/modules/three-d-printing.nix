{ ... }:
{
  flake.homeModules.threeDPrinting =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          orca-slicer
          freecad
          inkscape-with-extensions
          gimp
        ];
      };
    };
}
