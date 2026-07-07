{
  username,
  ...
}:
{
  flake.nixosModules.syncthing =
    {
      dnsName,
      ...
    }:

    let
      webUiPort = 8384;
    in
    {
      users.users.syncthing.extraGroups = [ "users" ];

      services.syncthing = {
        enable = true;
        openDefaultPorts = true;
        guiAddress = "0.0.0.0:${toString webUiPort}";
        settings.gui = {
          user = username;
          # bcrypt hash of the GUI password — syncthing accepts pre-hashed
          # values; the hash is deliberately committed (see docs/adr/0002).
          password = "$2b$10$Te0myMGbrntbl6OiNyMKkuLtpe3WLxmaI8Hlrt8/rHShA.A6e/Ihq";
        };

      };

      networking.firewall.allowedTCPPorts = [ webUiPort ];

      services.caddy.virtualHosts."syncthing.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString webUiPort}
        '';
      };

    };
}
