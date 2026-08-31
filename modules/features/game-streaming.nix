# Headless game streaming: Sunshine on cleoDesktop, Moonlight on the Steam Deck.
#
# The shape of this module is forced by Sunshine's capture backends, which are
# nvfbc, wlr, kms, kwin and x11. There is no xdg-desktop-portal path, so a
# GNOME/Mutter session cannot be captured at all — which is why the Stream
# Session is Plasma and not the obvious GNOME. See docs/adr/0006.
#
# Everything here is built so that nothing reaches the physical desk: the
# session renders to a virtual framebuffer, never takes DRM master, a VT or a
# connector, and every unit it touches is guarded so it cannot leak into a human
# user's Hyprland session.
{ self, ... }:
{
  flake.nixosModules.gameStreaming =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      streamUser = "streamer";

      # Fixed at compositor start. `--virtual` has no runtime mode switching,
      # and Sunshine's output_name is a global setting with no per-app override,
      # so a second output could never be selected per app entry anyway.
      # Moonlight scales to whatever the client asks for.
      virtualWidth = 1920;
      virtualHeight = 1080;

      # kwin_wayland_wrapper forwards its own argv verbatim to kwin_wayland
      # (kwin: src/helpers/wayland_wrapper/kwin_wrapper.cpp, `args <<
      # qApp->arguments().mid(1)`), so the virtual backend is reachable by
      # overriding this one unit's ExecStart.
      #
      # systemd.user units are global, so the choice has to be made at runtime
      # from the running user: streamer gets a headless framebuffer, and anyone
      # who logs into Plasma from ly gets the stock session rather than a broken
      # one. A ConditionUser= on the unit would have been shorter, but a false
      # condition skips the unit entirely, i.e. Plasma with no compositor.
      #
      # The system environment is sourced because this unit's PATH is NixOS's
      # default for user units — coreutils, findutils, grep, sed, systemd and
      # nothing else. The wrapper spawns `kwin_wayland` by bare name, and more
      # importantly KWin spawns `Xwayland` by bare name too. With `--xwayland`
      # the wrapper creates the X11 listening socket up front but starts
      # Xwayland lazily, so an unfindable Xwayland does not fail loudly: the
      # socket exists and simply never accepts, and every X client then blocks
      # in connect() forever. Sunshine's input::init() is such a client, which
      # is why this presented as Sunshine hanging before it bound its ports.
      kwinDispatch = pkgs.writeShellScript "kwin-wayland-dispatch" ''
        . /etc/set-environment
        export PATH=${pkgs.kdePackages.kwin}/bin:$PATH
        if [ "$(${pkgs.coreutils}/bin/id -un)" = ${lib.escapeShellArg streamUser} ]; then
          # Instrumentation, not configuration. After a cold boot this session
          # comes up with "Compositing Type: QPainter" (confirmed via KWin's own
          # supportInformation), while restarting it yields OpenGL -- so EGL
          # fails at startup for a reason nothing currently logs. KWin is silent
          # about it at default log levels. Remove once the cause is known.
          export QT_LOGGING_RULES="kwin_*.debug=true"
          exec ${pkgs.kdePackages.kwin}/bin/kwin_wayland_wrapper \
            --xwayland \
            --virtual \
            --width ${toString virtualWidth} \
            --height ${toString virtualHeight}
        fi
        exec ${pkgs.kdePackages.kwin}/bin/kwin_wayland_wrapper --xwayland
      '';

      # A lingering user never runs pam_systemd nor a login shell, so nothing
      # populates the session environment. startplasma-wayland sets
      # XDG_CONFIG_DIRS but only *inherits* XDG_DATA_DIRS, and with it unset
      # KService falls back to the XDG default /usr/local/share:/usr/share —
      # empty on NixOS. Every desktop file in /run/current-system/sw/share is
      # then invisible, including the one below that grants KWin screencast
      # permission, so capture is denied and Sunshine hangs. Sourcing the system
      # environment is exactly what a login would have done, and
      # startplasma's syncDBusEnvironment() then pushes it on to the systemd
      # user manager, so sunshine.service inherits it too.
      sessionStart = pkgs.writeShellScript "stream-session-start" ''
        . /etc/set-environment
        ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland &
        plasma=$!

        # A session that fell back to software compositing is useless here: KDE
        # screencast refuses it ("Unsupported compositing type"), so Sunshine
        # finds no display, every encoder probe fails, and the client sees a
        # bare 401. That is exactly what a cold boot produces, while restarting
        # the session comes up on OpenGL. Rather than guess how long the GPU
        # needs, ask KWin what it actually got and restart if it is wrong --
        # the check is the property we care about, not a proxy for it.
        for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
          ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.KWin /KWin supportInformation \
            2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'Compositing Type:' && break
          ${pkgs.coreutils}/bin/sleep 1
        done

        compositing=$(${pkgs.kdePackages.qttools}/bin/qdbus org.kde.KWin /KWin supportInformation \
          2>/dev/null | ${pkgs.gnugrep}/bin/grep -m1 'Compositing Type:')

        case "$compositing" in
          *OpenGL*)
            echo "stream-session: $compositing" >&2
            ;;
          *)
            echo "stream-session: ''${compositing:-Compositing Type: unknown} - not usable for screencast, restarting" >&2
            kill $plasma 2>/dev/null || true
            wait $plasma 2>/dev/null || true
            exit 1
            ;;
        esac

        wait $plasma
      '';

      # nixpkgs wraps Sunshine: bin/sunshine is a makeWrapper shell script that
      # execs bin/.sunshine-wrapped (it sets LD_LIBRARY_PATH for vulkan-loader),
      # so the running process's /proc/<pid>/exe — which is exactly what KWin
      # resolves via executablePathFromPid() before looking up
      # X-KDE-Wayland-Interfaces — is the *wrapped* binary. Neither the desktop
      # file Sunshine's package ships nor the temporary one Sunshine writes at
      # runtime (it uses argv[0], which the wrapper sets back to bin/sunshine)
      # names that path, so KWin denies zkde_screencast_unstable_v1. The failure
      # is silent and looks like a hang: Sunshine finds the output, then blocks
      # waiting for frames that never come, and never binds its ports.
      kwinScreencastPermission =
        pkgs.writeTextDir "share/applications/dev.lizardbyte.app.Sunshine.kwin-wrapped.desktop"
          ''
            [Desktop Entry]
            Type=Application
            Name=Sunshine KWin screencast permission (nixpkgs wrapper)
            Exec=${config.services.sunshine.package}/bin/.sunshine-wrapped
            X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1
            NoDisplay=true
          '';

      bridge = self.packages.${pkgs.stdenv.hostPlatform.system}.kwin-uinput-bridge;

      # Same privileged-interface mechanism as the screencast file above, for a
      # different interface. KWin always installs a FakeInputBackend regardless
      # of output backend, so org_kde_kwin_fake_input is the only input path a
      # --virtual session has: VirtualBackend does not override
      # createInputBackend(), so there is no libinput and Sunshine's uinput
      # devices would otherwise have no reader at all.
      kwinFakeInputPermission =
        pkgs.writeTextDir "share/applications/kwin-uinput-bridge.desktop"
          ''
            [Desktop Entry]
            Type=Application
            Name=Sunshine input bridge KWin permission
            Exec=${bridge}/bin/kwin-uinput-bridge
            X-KDE-Wayland-Interfaces=org_kde_kwin_fake_input
            NoDisplay=true
          '';

      # Sunshine stores Web UI credentials in its own state file, in a format it
      # does not document. Rather than reproduce that hash in a sops template
      # and have it rot on the next upstream change, hand Sunshine the password
      # and let it write its own file. Missing secret is not fatal: the Web UI
      # then simply prompts to set credentials on first visit.
      seedCreds = pkgs.writeShellScript "sunshine-seed-creds" ''
        set -eu
        secret=${config.sops.secrets.sunshineWebPassword.path}
        if [ ! -r "$secret" ]; then
          echo "sunshine: $secret unreadable, leaving Web UI credentials unset" >&2
          exit 0
        fi
        exec ${lib.getExe config.services.sunshine.package} \
          --creds ${lib.escapeShellArg streamUser} "$(cat "$secret")"
      '';
    in
    {
      # The Stream Session's own user. Separate from isaac because Steam is
      # single-instance per user: a Steam running in this session would capture
      # any `steam` launched from the Hyprland desk and map its windows into the
      # wrong session.
      users.users.${streamUser} = {
        isNormalUser = true;
        description = "Headless game streaming session";
        # user@.service at boot, with no login, no seat, no VT.
        linger = true;
        extraGroups = [
          "uinput" # Sunshine's virtual gamepad/keyboard/mouse.
          "render" # /dev/dri/renderD128, for KWin's GL and for NVENC.
          "video"
          # Vestigial under per-user PipeWire (the socket then lives in this
          # user's own XDG_RUNTIME_DIR and the group grants nothing), but kept
          # because it is exactly what system-wide PipeWire requires: KWin
          # delivers the screencast over PipeWire, so without access there is no
          # video at all, not merely no sound. Harmless to keep, and the single
          # thing needed again if this host ever returns to systemWide.
          "pipewire"
        ];
        # Deliberately NOT in "input": that grants read on every /dev/input/*,
        # which on a machine someone types at all day is a keylogger sitting in
        # an unattended 24/7 service. Sunshine only needs to *create* devices,
        # which is /dev/uinput alone. Deliberately NOT in "audio" either, so
        # this user's PipeWire physically cannot reach the desk's hardware.
      };

      services.desktopManager.plasma6.enable = true;

      # plasma6 sets `defaultSession = mkDefault "plasma"`, and nothing else in
      # this repo defines the option — so merely enabling Plasma would move the
      # ly login default off Hyprland. That is precisely the interruption this
      # feature is not allowed to cause.
      services.displayManager.defaultSession = "hyprland";

      # Enabled by mkDefault from plasma6. A screen reader on a session with no
      # listener is noise in the log and one more thing to start.
      services.orca.enable = false;

      environment.plasma6.excludePackages = with pkgs.kdePackages; [
        elisa
        khelpcenter
        plasma-browser-integration
        kate
        ktexteditor
        okular
        gwenview
        ark
        # A second remote-desktop stack is the last thing this host needs.
        krdp
      ];

      systemd.user.services.plasma-kwin_wayland = {
        # Amend the unit kwin's own package ships; do not replace it.
        overrideStrategy = "asDropin";
        serviceConfig.ExecStart = [
          ""
          "${kwinDispatch}"
        ];
      };

      # NOTE: `nixos-rebuild switch` does not restart another user's systemd
      # manager, so a rebuild leaves the running Stream Session on the *old*
      # closure until something restarts it. After changing anything in this
      # module, apply it with:
      #   sudo systemctl restart user@$(id -u streamer).service
      # A reboot does the same. This is also why a config change can look like
      # "switched but cannot connect".
      systemd.user.services.stream-session = {
        description = "Headless Plasma session for game streaming";
        # Global unit, so keep it out of every human's session. Unlike the kwin
        # override above, skipping this unit for other users is exactly right.
        unitConfig.ConditionUser = streamUser;
        wantedBy = [ "default.target" ];
        environment = {
          # A lingering user never runs pam_systemd, so nothing seeds the
          # session environment the way a login would. startplasma-wayland
          # aborts outright without a bus address, and everything the session
          # launches by bare name needs a usable PATH; startplasma pushes both
          # on to the user manager for the units it then starts.
          DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
          # mkForce: NixOS derives a default PATH for user units from the
          # `path` option; the session needs the system profile instead, and
          # /run/current-system/sw/bin already carries the coreutils/systemd
          # that default provided.
          PATH = lib.mkForce (
            lib.concatStringsSep ":" [
              "/run/wrappers/bin"
              "/etc/profiles/per-user/${streamUser}/bin"
              "/nix/var/nix/profiles/default/bin"
              "/run/current-system/sw/bin"
            ]
          );
        };
        # The self-heal above works by failing and being restarted, so the rate
        # limiter must not give up while the GPU is still settling -- but stays
        # finite so a permanently broken EGL setup stops and says so rather than
        # respawning Plasma forever.
        startLimitIntervalSec = 600;
        startLimitBurst = 100;
        serviceConfig = {
          ExecStart = "${sessionStart}";
          Restart = "always";
          RestartSec = "5s";
        };
      };

      services.sunshine = {
        enable = true;
        # Turing's NVENC path in Sunshine is the CUDA-backed one, and the
        # nixpkgs default is `cudaSupport = false`. Without this the encoder
        # falls back to nvidia's weak VAAPI shim or to software x264.
        package = pkgs.sunshine.override { cudaSupport = true; };
        openFirewall = true;
        # Must stay false. capSysAdmin repoints ExecStart at
        # /run/wrappers/bin/sunshine, and KWin authorises the privileged
        # zkde_screencast_unstable_v1 interface by matching the client's
        # canonical executable path against an installed .desktop file's Exec
        # (kwin: src/utils/serviceutils.h). Only the store path matches the
        # kwin .desktop file Sunshine's own package ships, so going through the
        # wrapper would get capture silently denied. cap_sys_admin is a KMS
        # capture requirement and buys nothing here.
        capSysAdmin = false;
        settings = {
          sunshine_name = "cleo";
          capture = "kwin";
          encoder = "nvenc";
          # Codecs are left to negotiation on purpose: Turing advertises H.264
          # and HEVC and never offers AV1, so pinning a codec list here would
          # only be a lie waiting to break on a GPU swap.
        };
        applications = {
          # Sunshine's unit runs with systemd's minimal PATH (the module forces
          # the NixOS-provided one to null for its tray icon), so apps launched
          # from it cannot find `steam` unless told where to look.
          env.PATH = "/run/current-system/sw/bin:/run/wrappers/bin:$(PATH)";
          apps = [
            # No cmd: streams the session as-is.
            { name = "Desktop"; }
            {
              name = "Steam Big Picture";
              cmd = "steam -gamepadui";
              auto-detach = "true";
            }
          ];
        };
      };

      systemd.user.services.sunshine = {
        # The stock unit is wantedBy graphical-session.target, which a Hyprland
        # login also reaches — without this, logging in at the desk would start
        # a second Sunshine capturing the real desktop and binding the ports.
        unitConfig.ConditionUser = streamUser;
        serviceConfig.ExecStartPre = [ "${seedCreds}" ];
      };

      environment.systemPackages = [
        kwinScreencastPermission
        kwinFakeInputPermission
      ];

      systemd.user.services.stream-input-bridge = {
        description = "Replay Sunshine's virtual input devices into KWin";
        unitConfig.ConditionUser = streamUser;
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${bridge}/bin/kwin-uinput-bridge --width ${toString virtualWidth} --height ${toString virtualHeight}";
          Restart = "always";
          RestartSec = "5s";
        };
      };

      # Sunshine creates its virtual devices as `streamer`, but the resulting
      # /dev/input/event* nodes are root:input 0660, which streamer cannot read
      # — and it is deliberately not in `input` (see the group list above).
      # LIBINPUT_IGNORE_DEVICE is what keeps the Stream Session off the desk.
      # Sunshine's virtual devices are real kernel input devices, so Hyprland --
      # which runs on a real seat and reads /dev/input through libinput -- picks
      # them up like any other mouse and keyboard, and remote input drives both
      # sessions at once. libinput honours this property and skips the device
      # entirely, while the bridge is unaffected because it opens the evdev node
      # directly rather than through libinput. KWin needs no exemption either:
      # the --virtual backend has no libinput at all and only ever sees input
      # via fake_input.
      #
      # Sunshine names every virtual device through inputtino_name_for_seat()
      # (its src/platform/linux/input/inputtino_common.h): "Mouse passthrough",
      # "Keyboard passthrough", "Touch passthrough", "Pen passthrough", and
      # "Sunshine <model> (virtual) pad" for gamepads — with a " (<seat>)"
      # suffix only when XDG_SEAT is set, which for this seatless lingering user
      # it never is. Only the gamepads carry a "Sunshine" prefix. Matching these
      # names still grants nothing on any real keyboard or mouse, so this stays
      # strictly narrower than the `input` membership Sunshine's docs ask for.
      services.udev.extraRules = ''
        # /dev/uinput is tagged uaccess by Steam's own rules
        # (60-steam-input.rules), so logind hands an ACL to the *active seat
        # user* and leaves the base ACL group entry as `group::---`. That
        # silently nullifies the GROUP="uinput" that hardware.uinput.enable
        # sets: group membership grants nothing at all. `streamer` is lingering
        # and seatless, so it never receives an ACL either, and Sunshine cannot
        # open /dev/uinput to create any virtual device -- it logs "Unable to
        # create virtual mouse: Permission denied" and every input path dies at
        # the source. Dropping the tag restores ordinary group semantics; isaac
        # is added to the uinput group in cleoDesktop/configuration.nix so Steam
        # Input keeps the access it had through uaccess.
        SUBSYSTEM=="misc", KERNEL=="uinput", TAG-="uaccess", MODE="0660", GROUP="uinput"

        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="* passthrough", MODE="0660", GROUP="uinput", ENV{LIBINPUT_IGNORE_DEVICE}="1"
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="* passthrough (*)", MODE="0660", GROUP="uinput", ENV{LIBINPUT_IGNORE_DEVICE}="1"
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="Sunshine *", MODE="0660", GROUP="uinput", ENV{LIBINPUT_IGNORE_DEVICE}="1"
      '';

      sops.secrets.sunshineWebPassword.owner = streamUser;

      home-manager.users.${streamUser} = {
        home.stateVersion = "25.11";

        xdg.configFile = {
          # Never lock. Over Moonlight a lock screen is a password prompt on a
          # machine with no local display and no keyboard attached to it.
          "kscreenlockerrc".text = ''
            [Daemon]
            Autolock=false
            LockOnResume=false
          '';

          # DPMS on a virtual output saves no power; it just stops the
          # framebuffer updating, which is a black stream. Timeouts are set
          # absurdly high rather than to 0, whose meaning varies per action.
          "powermanagementprofilesrc".text = ''
            [AC][DPMSControl]
            idleTime=999999
            lockBeforeTurnOff=0

            [AC][DimDisplay]
            idleTime=999999

            [AC][SuspendSession]
            idleTime=999999
            suspendType=0
          '';

          "baloofilerc".text = ''
            [Basic Settings]
            Indexing-Enabled=false
          '';

          # Live only because cleoDesktop sets services.pipewire.systemWide =
          # false; under system-wide PipeWire the per-user service is masked and
          # nothing would read this. streamer is lingering and seatless, so it
          # gets no /dev/snd ACLs and its graph has no hardware sinks at all —
          # this null sink is therefore the only sink, hence the default, hence
          # what Sunshine captures with no further configuration, and it cannot
          # reach the desk's speakers by any route.
          "pipewire/pipewire.conf.d/10-sunshine-sink.conf".text = ''
            context.objects = [
              { factory = adapter
                args = {
                  factory.name     = support.null-audio-sink
                  node.name        = "sunshine-sink"
                  node.description = "Sunshine Virtual Sink"
                  media.class      = Audio/Sink
                  audio.position   = [ FL FR ]
                }
              }
            ]
          '';
        };
      };
    };
}
