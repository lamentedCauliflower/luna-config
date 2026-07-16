{ self, username, ... }:
{
  flake.nixosModules.votv =
    { config, lib, pkgs, ... }:
    let
      cfg = config.hostConfig.games.votv;

      # Writable game copy, materialized from the store package by the
      # home-manager activation below. Writable because r2modman/shimloader
      # must write into the game folder (the store-read-only tree broke mod
      # installs), in $HOME because pressure-vessel shares $HOME into the
      # Proton container (see docs/adr/0004).
      #
      # The tile's appid is crc32(Exe + AppName) and keys BOTH its
      # CompatToolMapping entry and its compatdata prefix — where the saves
      # live — so this path and the tile name must never change (a package
      # bump doesn't touch them; renaming either orphans the prefix).
      gameRoot = "/home/${username}/.local/share/votv";
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
          # Thunderstore mod manager. Mods load via Unreal Shimloader; point
          # r2modman's "Change VotV directory" at ${gameRoot}. The
          # .forceproton marker r2modman looks for on Linux ships in the game
          # tree (modules/packages/votv.nix).
          pkgs.r2modman
        ];

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
          # r2modman's prescribed Proton launch line for shimloader mods: the
          # wrapper (host-side, $HOME is shared into the container) injects
          # the profile's --mod-dir/--pak-dir args and the WINEDLLOVERRIDES
          # proxy loads the shim. r2modman must have managed VotV once for
          # the wrapper to exist — a missing wrapper kills the tile's launch
          # outright (r2modman's "Start vanilla" still works); recreate the
          # profile or drop this line if r2modman's local state is ever wiped.
          launchOptions =
            ''WINEDLLOVERRIDES="winhttp,version=n,b" ''
            + ''"/home/${username}/.config/r2modmanPlus-local/VotV/linux_wrapper.sh" %command%'';
        };

        home-manager.users.${username} =
          { lib, ... }:
          {
            # Sync the game tree from the store package whenever the pin
            # changes (stamp file tracks the copied store path). rsync
            # overwrites game files but keeps extra files — mods, shimloader
            # state, generated configs — and deliberately does NOT --delete:
            # leftover files from a previous game version are the lesser evil
            # next to wiping mod installs. If a bump misbehaves, delete
            # ${gameRoot} and re-activate for a clean copy.
            home.activation.votvMaterialize = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              src="${cfg.package}/share/games/votv"
              dest="${gameRoot}"
              stamp="$dest/.nix-src"
              if [ ! -e "$stamp" ] || [ "$(cat "$stamp")" != "$src" ]; then
                run mkdir -p "$dest"
                run ${pkgs.rsync}/bin/rsync -a --chmod=u+w "$src/" "$dest/"
                run sh -c 'printf %s "$1" > "$2"' _ "$src" "$stamp"
              fi
            '';
          };
      };
    };
}
