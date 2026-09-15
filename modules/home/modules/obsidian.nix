{ ... }:
{
  flake.homeModules.obsidian =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          obsidian
        ];
      };
    };
}
