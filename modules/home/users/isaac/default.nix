{
  self,
  inputs,
  username,
  ...
}:
{
  flake.nixosModules.isaacHomeManager =
    { config, ... }:
    {
      imports = [ self.nixosModules.chromium ];

      # System-side declarations for secrets consumed by isaac's home-manager
      # modules (anki-client, taskwarrior, mpd) — the hm modules read the
      # rendered /run/secrets paths directly.
      sops.secrets.ankiSyncKey.owner = username;
      sops.secrets.taskwarriorSyncEncryptionSecret = { };
      sops.secrets.navidromePassword = { };
      sops.templates."task-sync.rc" = {
        owner = username;
        content = ''
          sync.server.url=http://tasksync.luna.local
          sync.server.client_id=${username}
          sync.server.encryption_secret=${config.sops.placeholder.taskwarriorSyncEncryptionSecret}
        '';
      };

      # httpdirfs reads its Navidrome credentials from here rather than from
      # argv, which /proc makes world-readable. One option per line, leading
      # dash, value after a space — httpdirfs appends the file to its own
      # argument list (src/main.c, parse_config_file).
      sops.templates."httpdirfs-navidrome.conf" = {
        owner = username;
        content = ''
          --sonic-username ${username}
          --sonic-password ${config.sops.placeholder.navidromePassword}
        '';
      };

      home-manager = {
        useGlobalPkgs = true;
        # On collision with an unmanaged file, rename it <file>.hm-bak
        # instead of aborting activation. Note: only one backup per ext —
        # if <file>.hm-bak already exists, activation still fails.
        backupFileExtension = "hm-bak";
        extraSpecialArgs = { inherit inputs; };
        users.isaac = self.homeModules.isaacConfiguration;
      };
    };
}
