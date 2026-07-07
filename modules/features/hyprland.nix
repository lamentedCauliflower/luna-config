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
        quickshell
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        gtk3
        rofi
      ];

      qt.enable = true;

      services.displayManager.ly.enable = true;

      environment.variables = {
        GSETTINGS_SCHEMA_DIR = "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas";
      };
    };

}
