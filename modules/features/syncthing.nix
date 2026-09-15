{
  self,
  username,
  ...
}:
{
  flake.nixosModules.syncthing =
    {
      ...
    }:

    let
      webUiPort = 8384;
    in
    {
      # cleoDesktop and yuroLaptop import this module but not nixosModules.caddy,
      # so the lanVhosts options have to come in here rather than riding along
      # with caddy. Caddy stays disabled on those hosts; the vhost this declares
      # is inert there, exactly as it was before.
      imports = [ self.nixosModules.lanVhosts ];

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

      hostConfig.lanVhosts.services.syncthing.upstream = "127.0.0.1:${toString webUiPort}";

    };
}
