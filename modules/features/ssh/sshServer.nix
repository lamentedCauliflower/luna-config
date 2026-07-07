{ ... }:
{
  flake.nixosModules.sshServer =
    { ... }:
    {
      services.openssh = {
        enable = true;
        settings = {
          X11Forwarding = true;
          PermitRootLogin = "no";
          PasswordAuthentication = false;
        };
        openFirewall = true;
      };

      users.users.isaac.openssh.authorizedKeys.keyFiles = [
        ./isaac_ed25519.pub
      ];
    };

}
