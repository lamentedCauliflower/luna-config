# Monado as the OpenXR runtime, in place of SteamVR.
#
# Mutually exclusive with nixosModules.steamVr: both declare
# /etc/xdg/openxr/1/active_runtime.json, so importing the two together is an
# eval conflict rather than a silently wrong runtime. Swapping which one a host
# imports is the whole switch.
#
# Unlike SteamVR, Monado is an ordinary store path, so nothing here has to chase
# mutable files in the Steam library — upstream's services.monado grants
# cap_sys_nice through security.wrappers instead of a setcap-on-update dance.
{ username, ... }:
{
  flake.nixosModules.monado =
    { pkgs, ... }:
    {
      services.monado = {
        enable = true;
        # Publishes the runtime manifest to /etc/xdg/openxr/1/.
        defaultRuntime = true;
        # Deliberately off, even though it targets the right file. It relinks
        # ~/.config/openxr/1/active_runtime.json from monado.service's preStart,
        # but the service is socket-activated: a client has to find Monado to
        # connect, and a stale SteamVR symlink in ~/.config is exactly what stops
        # it finding Monado. So it cannot bootstrap out of the state it exists to
        # fix. Home-manager owns that symlink below instead — one writer, and it
        # lands at activation rather than at first connection.
        forceDefaultRuntime = false;
        # highPriority defaults true -> cap_sys_nice for async reprojection.
      };

      # OpenVR titles (which is most of a Steam VR library) cannot talk to
      # Monado directly. OpenComposite reimplements openvr_api and translates it
      # to OpenXR; a game picks it up from the runtime entry in
      # openvrpaths.vrpath below.
      environment.systemPackages = [
        pkgs.opencomposite

        # OpenXR apps dlopen libopenxr_loader.so; services.monado installs the
        # runtime but not the loader.
        pkgs.openxr-loader

        # Wayland desktop windows inside the headset. Native OpenXR against
        # Monado, so unlike the SteamVR path it needs no LD_LIBRARY_PATH
        # patching for a prebuilt vrclient.so.
        pkgs.wayvr
      ];

      # Both files below are runtime-selection state that SteamVR wrote
      # imperatively into ~/.config, so both need force. Neither is ever
      # hand-authored, so clobbering them is safe.
      home-manager.users.${username}.xdg.configFile = {
        # The OpenXR loader searches XDG_CONFIG_HOME before XDG_CONFIG_DIRS, so
        # this file — not the /etc/xdg one from defaultRuntime — is what actually
        # decides the runtime. The /etc/xdg copy stays as the fallback for any
        # other user.
        "openxr/1/active_runtime.json" = {
          force = true;
          source = "${pkgs.monado}/share/openxr/1/openxr_monado.json";
        };

        # vrpathreg's registry. Repointing the runtime entry at OpenComposite is
        # what makes an OpenVR game load the translation layer.
        "openvr/openvrpaths.vrpath" = {
          force = true;
          text = builtins.toJSON {
            version = 1;
            jsonid = "vrpathreg";
            runtime = [ "${pkgs.opencomposite}/lib/opencomposite" ];
            config = [ "/home/${username}/.local/share/Steam/config" ];
            log = [ "/home/${username}/.local/share/Steam/logs" ];
            external_drivers = null;
          };
        };
      };

      # Steam games run inside pressure-vessel, which does not bind /nix/store,
      # so a game that resolves OpenComposite to a store path would fail to open
      # it. Nothing else in the container needs this, but it is read-only.
      environment.sessionVariables.PRESSURE_VESSEL_FILESYSTEMS_RO = "/nix/store";

      # Same rationale as the steamVr module: the kernel autosuspending the
      # HMD's built-in hub takes the wands' dongles with it mid-session. Scoped
      # to HTC (0bb4) and Valve (28de) so other peripherals keep power saving.
      # services.monado already supplies the access rules via xr-hardware.
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", TEST=="power/control", ATTR{power/control}="on"
      '';
    };

}
