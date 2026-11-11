{ ... }:
{
  flake.nixosModules.hyprland =
    {
      pkgs,
      ...
    }:

    {
      programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        # Matches nixpkgs' default hyprland build (withUwsm = true), so it is
        # substituted from cache.nixos.org. false makes the module override the
        # package with UWSM off and recompile Hyprland (~6.5 min) every bump.
        # Also adds a "Hyprland (UWSM)" session to ly; plain Hyprland is unchanged.
        withUWSM = true;
        portalPackage = pkgs.xdg-desktop-portal-hyprland;
      };
      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      environment.systemPackages = with pkgs; [
        kitty
        hyprlauncher
        hypridle
        hyprpicker
        hyprpolkitagent
        hyprsunset
        hyprls
        hyprlock
        hyprpaper
        hyprcursor
        playerctl
        brightnessctl
        quickshell
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        gtk3
        rofi
      ];

      services.udev.packages = [ pkgs.brightnessctl ];

      qt.enable = true;

      services.displayManager.ly.enable = true;

      environment.variables = {
        GSETTINGS_SCHEMA_DIR = "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas";
      };
    };

}
