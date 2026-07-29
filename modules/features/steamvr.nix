# SteamVR support on top of the steam module. Everything here exists because
# SteamVR ships as mutable files in the user's Steam library, so none of it can
# be expressed as a normal package/wrapper — the HMD udev rules themselves come
# free with programs.steam (hardware.steam-hardware).
{ username, ... }:
{
  flake.nixosModules.steamVr =
    { pkgs, ... }:
    let
      # ~/.steam/steam is a symlink; systemd.paths must watch the real dir.
      steamRoot = "/home/${username}/.local/share/Steam";
      steamVrRoot = "${steamRoot}/steamapps/common/SteamVR";
      launcher = "${steamVrRoot}/bin/linux64/vrcompositor-launcher";
    in
    {
      # Asynchronous reprojection needs the compositor to raise its own
      # scheduling priority, which needs CAP_SYS_NICE. Valve splits this into a
      # tiny launcher binary precisely so the capability can be granted here:
      # it re-execs vrcompositor without the caps, so the file capability does
      # not turn the real compositor into an AT_SECURE process (which would
      # make glibc drop the Steam runtime's LD_LIBRARY_PATH).
      #
      # Without it every session logs "0 reprojected" and drops frames instead
      # of reprojecting them.
      systemd.services.steamvr-setcap = {
        description = "Grant CAP_SYS_NICE to SteamVR's compositor launcher";
        unitConfig.ConditionPathExists = launcher;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.libcap}/bin/setcap CAP_SYS_NICE+ep ${launcher}";
        };
      };

      # Every SteamVR update rewrites the launcher and wipes its xattrs, so the
      # capability has to be re-applied on change, not just at boot. PathExists
      # covers boot (and a fresh SteamVR install); PathModified covers updates.
      systemd.paths.steamvr-setcap = {
        description = "Watch SteamVR's compositor launcher for updates";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = launcher;
          PathModified = launcher;
        };
      };

      # vrserver aborts with a watchdog timeout in UpdateControllerRoles when
      # the kernel autosuspends the HMD's built-in hub mid-session, taking the
      # wands' dongles with it. Pin HTC (0bb4) and Valve (28de) USB devices
      # awake; scoped to those vendors so ordinary peripherals keep saving power.
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", TEST=="power/control", ATTR{power/control}="on"
      '';

      # OpenXR apps dlopen libopenxr_loader.so; Steam's own runtime bundles a
      # copy but nothing outside it does, so nix-built OpenXR programs need the
      # loader on the system path.
      environment.systemPackages = [
        pkgs.openxr-loader

        # SteamVR's own Desktop View captures through X11 only, so it renders
        # black on a Wayland session. wayvr mirrors Wayland outputs into the
        # headset over OpenVR/OpenXR instead.
        pkgs.wayvr
      ];

      # Point the loader at SteamVR as the OpenXR runtime. Steam writes the same
      # symlink into ~/.config/openxr/1/ when SteamVR installs, which wins over
      # this one — but that copy is imperative and dies with the profile, so
      # declare the XDG_CONFIG_DIRS fallback too. Deliberately a symlink to
      # Valve's manifest rather than a hand-written copy, so a manifest change
      # in a SteamVR update is picked up.
      #
      # Not set as XR_RUNTIME_JSON: that would hard-pin the runtime and block
      # switching a single app to monado/wivrn by exporting it per-launch.
      environment.etc."xdg/openxr/1/active_runtime.json".source =
        "${steamVrRoot}/steamxr_linux64.json";
    };

}
