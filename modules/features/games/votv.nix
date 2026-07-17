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

      # Host-side save dir, symlinked into the Proton prefix below. Outside
      # gameRoot on purpose: the documented clean-slate escape ("delete
      # gameRoot and re-activate") must never take saves with it.
      saveDir = "/home/${username}/.local/share/votv-saves";

      # crc32("VotV.exe path (quoted)" + AppName) — the id the shortcuts
      # writer derives (steam_appid_unsigned in steam-shortcuts-writer.py).
      # Recompute if gameRoot or the tile name ever changes.
      appid = "3351335672";
      prefix = "/home/${username}/.local/share/Steam/steamapps/compatdata/${appid}";

      # r2modman profile whose mods the tile loads. Z:-style paths because
      # the args are consumed by shimloader inside wine ($HOME is shared into
      # the Proton container, so Z:/home/... resolves).
      shimProfile = "Z:/home/${username}/.config/r2modmanPlus-local/VotV/profiles/Default/shimloader";
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
        # The game writes saves to %localappdata%/VotV inside the prefix; the
        # votvSaveRedirect activation below replaces that dir with a symlink
        # to ${saveDir}, so saves live host-side and survive prefix
        # rotation/deletion. Pre-alpha updates can still break save
        # compatibility — back ${saveDir} up before bumping the package pin.
        hostConfig.steamShortcuts.shortcuts."Voices of the Void" = {
          exe = "${gameRoot}/VotV.exe";
          icon = "${gameRoot}/votv.png";
          compatTool = "proton_experimental";
          # Shimloader modded launch. r2modman deploys the UE4SS proxy pair
          # (dwmapi.dll + ue4ss.dll) next to the shipping exe in the writable
          # game copy; the dwmapi override makes wine load that native proxy
          # (dwmapi is builtin-preferred otherwise → vanilla), and the
          # shimloader args point it at the r2modman profile. r2modman's own
          # "Start modded" button and its linux_wrapper.sh do NOT work for
          # this non-Steam Proton setup — launch through this tile; r2modman
          # is only the mod installer. Without the dlls in the game copy the
          # override is inert and the tile launches vanilla.
          launchOptions =
            ''WINEDLLOVERRIDES="dwmapi=n,b" %command%''
            + " --mod-dir \"${shimProfile}/mod\""
            + " --pak-dir \"${shimProfile}/pak\""
            + " --cfg-dir \"${shimProfile}/cfg\""
            + " --overlay-dir \"${shimProfile}/overlay\"";
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

            # Redirect the game's save location (%localappdata%/VotV in the
            # Proton prefix) to the host-side ${saveDir}: wine follows Linux
            # symlinks, and pre-creating the drive_c path is safe — wineboot
            # builds the rest of the user tree around it on first prefix
            # init. Saves created before the redirect are migrated once.
            home.activation.votvSaveRedirect = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              saves="${saveDir}"
              appdata="${prefix}/pfx/drive_c/users/steamuser/AppData/Local"
              run mkdir -p "$saves" "$appdata"
              if [ -d "$appdata/VotV" ] && [ ! -L "$appdata/VotV" ]; then
                run sh -c 'cp -a "$1"/. "$2"/ && rm -rf "$1"' _ "$appdata/VotV" "$saves"
              fi
              run ln -sfn "$saves" "$appdata/VotV"
            '';
          };
      };
    };
}
