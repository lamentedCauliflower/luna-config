{ ... }:
{
  flake.homeModules.jellyfin =
    { pkgs, ... }:
    {
      # Jellyfin desktop client (jellyfin-media-player; bin: jellyfin-desktop).
      # Installed here for Desktop Mode; the Steam non-Steam shortcut launches
      # the same binary in Game Mode (see features/steam-shortcuts.nix).
      home.packages = [ pkgs.jellyfin-media-player ];
    };
}
