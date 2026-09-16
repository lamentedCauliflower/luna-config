{ ... }:
{
  flake.homeModules.mpd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Navidrome's Subsonic API, presented as an ordinary directory tree by
      # httpdirfs, is mpd's music_directory. mpd stays plain upstream mpd and
      # every mpd client (rmpc, waybar) keeps working unchanged — see
      # docs/adr/0008 for why this rather than mopidy or upmpdcli.
      mountPoint = "${config.home.homeDirectory}/mnt/navidrome";
      navidromeUrl = "http://navidrome.luna.local";

      # A FUSE mount whose process is gone is worse than absent: every stat on
      # the path returns ENOTCONN, so a plain `mkdir -p` fails and the unit
      # restart-loops forever without ever reaching httpdirfs. Restarts can also
      # stack mounts on the same directory, so pop until there is nothing left
      # rather than unmounting once.
      prepareMount = pkgs.writeShellScript "prepare-navidrome-mount" ''
        for _ in $(seq 1 10); do
          ${pkgs.fuse3}/bin/fusermount3 -uz ${mountPoint} >/dev/null 2>&1 || break
        done
        ${pkgs.coreutils}/bin/mkdir -p ${mountPoint}
      '';

      # httpdirfs does not notify systemd, and the FUSE tree appears some
      # milliseconds after the process starts. Without this, an mpd that starts
      # in the same transaction can index an empty directory.
      #
      # Non-empty, not merely mounted: httpdirfs mounts successfully even when
      # it never reached sonic mode, and hands back an empty tree. mpd reads
      # that as "every file was deleted" and empties its tag cache, which is
      # how this failed the first time. An empty library is never what is
      # wanted here, so fail the unit instead of letting mpd see it.
      waitForMount = pkgs.writeShellScript "wait-for-navidrome-mount" ''
        for _ in $(seq 1 150); do
          if ${pkgs.util-linux}/bin/mountpoint -q ${mountPoint} \
            && [ -n "$(${pkgs.coreutils}/bin/ls -A ${mountPoint})" ]; then
            exit 0
          fi
          sleep 0.2
        done
        echo "${mountPoint} is not a mountpoint, or mounted but empty" >&2
        exit 1
      '';
    in
    {
      home.sessionVariables = {
        MPD_HOST = "localhost";
        MPD_PORT = "6600";
      };

      # Not needed by the unit below (it calls the store path), but wanted at
      # the shell for --cache-clear when the cache goes stale.
      home.packages = [ pkgs.httpdirfs ];

      systemd.user.services.navidrome-mount = {
        Unit = {
          Description = "Navidrome library as a FUSE filesystem (httpdirfs)";
          Documentation = [ "https://github.com/fangfufu/httpdirfs" ];
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
          # mpd is socket-activated, so this only orders the two at login;
          # ExecStartPost is what actually guarantees the tree is populated.
          Before = [ "mpd.service" ];
        };

        Service = {
          Type = "simple";
          ExecStartPre = "${prepareMount}";
          # -f keeps httpdirfs in the foreground so systemd owns the process.
          #
          # Credentials arrive through --config, never argv: /proc/<pid>/cmdline
          # is world-readable, so --sonic-password on the command line would
          # publish the Navidrome password to every local process.
          #
          # --cache is not optional in *sonic mode. Each tag read during an mpd
          # update is an HTTP range request, and without the permanent segment
          # cache a library scan is unusable rather than merely slow.
          ExecStart = lib.concatStringsSep " " [
            (lib.getExe pkgs.httpdirfs)
            "-f"
            # Two words, not --config=PATH. httpdirfs 1.2.10 scans argv for
            # the config path with a plain strcmp against "--config", so the
            # = spelling leaves the path unread, silently falls back to
            # $XDG_CONFIG_HOME/httpdirfs/config, and starts with no
            # credentials at all — which is a successful mount of nothing
            # rather than an error. The = form is only supported on git master.
            "--config /run/secrets/rendered/httpdirfs-navidrome.conf"
            "--cache"
            "--sonic-id3"
            navidromeUrl
            mountPoint
          ];
          ExecStartPost = "${waitForMount}";
          # FUSE can leave the mountpoint behind when the process is killed
          # rather than exiting; -z detaches it so the next start is not ENOTCONN.
          ExecStop = "-${pkgs.fuse3}/bin/fusermount3 -uz ${mountPoint}";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = [ "default.target" ];
      };

      services.mpd = {
        enable = true;
        musicDirectory = mountPoint;
        network.startWhenNeeded = true;
        network.listenAddress = "any";
        extraConfig = ''
          audio_output {
            type            "pipewire"
            name            "Pipewire Output"
          }

          # auto_update would re-scan the whole FUSE tree on every inotify event
          # httpdirfs cannot deliver anyway. Updates are manual: `mpc update`,
          # or `u` in rmpc, after Navidrome picks up new files.
          auto_update "no"
        '';
      };

      programs.rmpc = {
        enable = true;
        config = ''
          (
            address: "127.0.0.1:6600",
            password: None,
            enable_mouse: true,
          )
        '';
      };
    };
}
