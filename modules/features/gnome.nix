# Stock GNOME, deliberately without a display manager: mewoSteamdeck boots
# straight into Gaming Mode (jovian.steam.autoStart) and reaches this session
# via Steam's "Switch to Desktop", so GDM would conflict. A host that wants a
# login screen must enable its own display manager alongside this module.
{ ... }:
{
  flake.nixosModules.gnome =
    { ... }:
    {
      services.desktopManager.gnome.enable = true;
    };

}
