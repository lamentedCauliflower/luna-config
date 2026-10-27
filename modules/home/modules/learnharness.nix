{ self, ... }:
{
  flake.homeModules.learnharness =
    { config, lib, pkgs, ... }:
    let
      cfg = config.learnharness;
      pkg = self.packages.${pkgs.stdenv.hostPlatform.system}.learnharness;

      # The app has no locking of its own, so two hosts on the shared dataDir
      # would silently overwrite each other's chats/graph. flock on the share
      # (NFSv4, local_lock=none) is enforced by the server and released when
      # the app exits, or after the lease expires if a host dies — no stale
      # lockfile to clean up.
      launcher = pkgs.writeShellApplication {
        name = "learnharness";
        runtimeInputs = [ pkgs.util-linux pkgs.libnotify ];
        text = ''
          data=${lib.escapeShellArg cfg.dataDir}
          lock="$data.lock"

          die() {
            echo "$1" >&2
            notify-send -u critical LearnHarness "$1" || true
            exit 1
          }

          [ -d "$data" ] || die "$data is missing (share not mounted?)"

          exec 9<>"$lock"
          if flock -n 9; then
            # Padded so a shorter hostname fully overwrites a longer one.
            printf '%-63s\n' "$HOSTNAME" >&9
            # Not exec, and fd 9 closed for the app: its next-server child
            # outlives a killed Electron main, and would hold an inherited lock
            # forever. This shell holds it; bwrap --die-with-parent ties the
            # app to us.
            ${lib.getExe pkg} "$@" 9>&-
            exit
          fi

          read -r holder <"$lock" || holder=
          # Ours already: Electron's single-instance lock focuses the open window.
          if [ "$holder" = "$HOSTNAME" ]; then
            exec ${lib.getExe pkg} "$@"
          fi
          die "Already open on ''${holder:-another host}; close it there first."
        '';
      };
    in
    {
      options.learnharness.dataDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/mnt/isaac/LearnHarness";
        description = ''
          Where LearnHarness keeps its chats + knowledge graph. null keeps the
          app default (~/.config/LearnHarness/data). The Electron shell always
          overwrites LH_DATA_DIR with userData/data, so this symlinks that dir
          instead; keys, cookies and Chromium caches stay local. The target
          must already exist. Setting it also guards launches with
          <dataDir>.lock so only one host runs the app at a time.
        '';
      };

      config = {
        # launcher listed first so its bin/learnharness shadows the package's;
        # the .desktop Exec=learnharness then resolves to it via PATH.
        home.packages = [
          (
            if cfg.dataDir == null then
              pkg
            else
              pkgs.symlinkJoin {
                name = "learnharness-locked";
                paths = [ launcher pkg ];
              }
          )
        ];

        xdg.configFile."LearnHarness/data" = lib.mkIf (cfg.dataDir != null) {
          source = config.lib.file.mkOutOfStoreSymlink cfg.dataDir;
        };
      };
    };
}
