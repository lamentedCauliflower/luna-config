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
      # modules (anki-client, taskwarrior) — the hm modules read the rendered
      # /run/secrets paths directly.
      sops.secrets.ankiSyncKey.owner = username;
      sops.secrets.taskwarriorSyncEncryptionSecret = { };
      sops.templates."task-sync.rc" = {
        owner = username;
        content = ''
          sync.server.url=http://tasksync.luna.local
          sync.server.client_id=${username}
          sync.server.encryption_secret=${config.sops.placeholder.taskwarriorSyncEncryptionSecret}
        '';
      };

      home-manager = {
        useGlobalPkgs = true;
        extraSpecialArgs = { inherit inputs; };
        users.isaac = self.homeModules.isaacConfiguration;
      };
    };
}
