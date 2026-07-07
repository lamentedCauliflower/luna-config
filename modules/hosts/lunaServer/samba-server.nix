{ self, username, ... }:
{
  flake.nixosModules.lunaSambaServer =
    { config, ... }:
    {
      imports = [ self.nixosModules.lunaNFSServer ];

      sops.secrets.sambaPassword = { };

      services.samba = {
        enable = true;
        openFirewall = true;
        settings = {
          global = {
            "security" = "user";
            "guest account" = "nobody";
            "map to guest" = "bad user";
          };
          "userShare" = {
            "path" = "/export/${username}";

            "browseable" = "yes";
            "read only" = "no";
            "guest ok" = "no";
            "create mask" = "0644";
            "directory mask" = "0755";
            "valid users" = username;
            "force user" = username;
            "force group" = "users";
          };

          "mediaShare" = {
            "path" = "/export/media";

            "browseable" = "yes";
            "read only" = "no";
            "guest ok" = "no";
            "create mask" = "0644";
            "directory mask" = "0755";
            "valid users" = username;
            "force user" = username;
            "force group" = "users";
          };
        };
      };

      services.samba-wsdd = {
        enable = true;
        openFirewall = true;
      };

      services.avahi = {
        publish.enable = true;
        publish.userServices = true;
        # ^^ Needed to allow samba to automatically register mDNS records (without the need for an `extraServiceFile`
        nssmdns4 = true;
        # ^^ Not one hundred percent sure if this is needed- if it aint broke, don't fix it
        enable = true;
        openFirewall = true;
      };

      networking.firewall.allowPing = true;

      # Activation scripts run every time nixos switches build profiles, so the
      # samba password is refreshed from the sops secret during nixos-rebuild.
      # An absolute path to smbpasswd is necessary as it is not in $PATH in the
      # activation script's environment. The password is piped twice because
      # smbpasswd demands a confirmation even in non-interactive mode.
      system.activationScripts = {
        init_smbpasswd = {
          deps = [ "setupSecrets" ];
          text = ''
            pw="$(cat ${config.sops.secrets.sambaPassword.path})"
            /run/current-system/sw/bin/printf "%s\n%s\n" "$pw" "$pw" | /run/current-system/sw/bin/smbpasswd -sa ${username}
          '';
        };
      };

    };

}
