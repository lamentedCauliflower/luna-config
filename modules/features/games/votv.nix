{ self, username, ... }:
{
  flake.nixosModules.votv =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.games.votv;

      # Stable profile path for the game tree. The tile's appid is
      # crc32(Exe + AppName) and keys BOTH its CompatToolMapping entry and its
      # compatdata prefix — where the saves live — so Exe must never contain a
      # store hash (a package bump would orphan the prefix). pathsToLink keeps
      # this path fixed across rebuilds. Corollary: renaming the tile also
      # changes the appid and orphans the prefix — don't (see docs/adr/0004).
      gameRoot = "/run/current-system/sw/share/games/votv";
    in
    {
      # Repo standard: importing a module enables it — no enable flag.
      options.hostConfig.games.votv = {
        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.votv;
          defaultText = lib.literalExpression "self.packages.<system>.votv";
          description = "Pinned Voices of the Void package (built in modules/packages/votv.nix).";
        };
      };

      config = {
        environment.systemPackages = [
          cfg.package
          # Thunderstore mod manager. VotV mods load via Unreal Shimloader
          # (profile-virtualized UE4SS): r2modman keeps mods/config in its own
          # profile dirs and overlays them at runtime, so the store-read-only
          # game tree is fine. Point r2modman's "Change VotV directory" at
          # ${gameRoot}. The .forceproton marker r2modman looks for on Linux
          # is baked into the package (modules/packages/votv.nix).
          pkgs.r2modman
        ];
        environment.pathsToLink = [ "/share/games" ];

        # Proton Tile: a Windows exe launched through Steam's Proton via a
        # declarative CompatToolMapping entry (docs/adr/0004). Importing this
        # module requires the steamShortcuts module on the same host
        # (docs/adr/0003). Proton Experimental itself is Steam-managed: on a
        # host that never installed it, the first launch prompts the download.
        #
        # Saves live inside the Steam-owned prefix:
        #   ~/.local/share/Steam/steamapps/compatdata/<appid>/pfx/
        #     drive_c/users/steamuser/AppData/Local/VotV
        # Pre-alpha updates can break saves — back that dir up before bumping
        # the package pin.
        hostConfig.steamShortcuts.shortcuts."Voices of the Void" = {
          exe = "${gameRoot}/VotV.exe";
          icon = "${gameRoot}/votv.png";
          compatTool = "proton_experimental";
          # Proton runs inside the Steam Linux Runtime container
          # (pressure-vessel), which shares /nix but NOT /run/current-system —
          # without this the exe path resolves on the host and dies in the
          # container (wine bootstraps the prefix, then exits within seconds,
          # no game log ever written). PRESSURE_VESSEL_FILESYSTEMS_RO is the
          # documented steam-runtime knob to share extra paths; verified
          # on-device inside the SLR container (see docs/adr/0004).
          #
          # The linux_wrapper.sh part is r2modman's prescribed Proton launch
          # line for shimloader mods: the wrapper (host-side, $HOME is shared
          # into the container) injects the profile's --mod-dir/--pak-dir args
          # and the WINEDLLOVERRIDES proxy loads the shim. r2modman must have
          # managed VotV once for the wrapper to exist — a missing wrapper
          # kills the tile's launch outright (r2modman's "Start vanilla" still
          # works); recreate the profile or drop this line if r2modman's
          # local state is ever wiped.
          launchOptions =
            "PRESSURE_VESSEL_FILESYSTEMS_RO=/run/current-system "
            + ''WINEDLLOVERRIDES="winhttp,version=n,b" ''
            + ''"/home/${username}/.config/r2modmanPlus-local/VotV/linux_wrapper.sh" %command%'';
        };
      };
    };
}
