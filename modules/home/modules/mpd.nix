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

      # nixpkgs pins 1.2.10, which cannot be used with --cache against a sonic
      # server. fs_open's cache-creation retry path frees the Link's sonic id
      # and then reads it back, so the retried Cache_exist looks for the cache
      # under a garbage filename, fails, and the whole filesystem exits with
      # "Cache file creation failure". mpd hits it within a file or two of
      # starting a scan, which leaves a stale mountpoint behind and takes the
      # library with it. Upstream fixed exactly this in 1.2.11 ("Resolved
      # concurrent cache initialization race in fs_open"); 1.3.0 then fixed
      # further use-after-frees in Cache_free and TOCTOU races in Cache_exist
      # and Cache_delete, which are the same failure under a different name, so
      # this pins the current release rather than the minimum one.
      #
      # Dropping --cache also avoids the crash and was rejected: the cache is
      # what makes a scan finish at all (see docs/adr/0008).
      #
      # The test subdir is patched out because it pulls the Unity framework
      # through a meson wrap, which cannot download in the build sandbox. The
      # nixpkgs derivation runs no tests either way.
      httpdirfs = pkgs.httpdirfs.overrideAttrs (old: {
        version = "1.3.3";
        src = pkgs.fetchFromGitHub {
          owner = "fangfufu";
          repo = "httpdirfs";
          tag = "1.3.3";
          hash = "sha256-HMcb23Rk7MD4qsdXXFaOqOenb87BDB1N1ov4wWPOq58=";
        };
        postPatch = (old.postPatch or "") + ''
          substituteInPlace meson.build --replace-fail "subdir('tests')" ""
        '';
      });

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
      home.packages = [ httpdirfs ];

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
            (lib.getExe httpdirfs)
            "-f"
            # Two words. The = spelling only started working in 1.2.11; in
            # 1.2.10 the argv scan is a plain strcmp against "--config", so
            # --config=PATH left the path unread, fell back to
            # $XDG_CONFIG_HOME/httpdirfs/config, found nothing and ran with no
            # credentials at all — a successful mount of an empty tree rather
            # than an error. The pin above is past that, but the two-word form
            # works on every version and the = form does not.
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
