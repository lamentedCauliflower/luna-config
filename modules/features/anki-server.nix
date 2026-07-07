{ username, ... }:
{
  flake.nixosModules.ankiServer =
    {
      config,
      dnsName,
      ...
    }:
    {
      sops.secrets.ankiSyncServerPassword = { };

      services.anki-sync-server = {
        enable = true;
        address = "0.0.0.0";
        openFirewall = true;
        users = [
          {
            username = username;
            passwordFile = config.sops.secrets.ankiSyncServerPassword.path;
          }
        ];
      };

      services.caddy.virtualHosts."http://anki.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString config.services.anki-sync-server.port}
      '';
    };

}
