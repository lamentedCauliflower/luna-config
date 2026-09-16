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

      # httpdirfs does not notify systemd, and the FUSE tree appears some
      # milliseconds after the process starts. Without this, an mpd that starts
      # in the same transaction can index an empty directory.
      waitForMount = pkgs.writeShellScript "wait-for-navidrome-mount" ''
        for _ in $(seq 1 150); do
          ${pkgs.util-linux}/bin/mountpoint -q ${mountPoint} && exit 0
          sleep 0.2
        done
        echo "${mountPoint} did not become a mountpoint" >&2
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
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountPoint}";
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
            "--config=/run/secrets/rendered/httpdirfs-navidrome.conf"
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
