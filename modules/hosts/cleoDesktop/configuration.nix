{ self, username, ... }:
{
  flake.nixosModules.cleoDesktopConfiguration =
    { pkgs, ... }:
    {

      _module.args.dnsName = "cleo";
      imports = [
        self.nixosModules.cleoDesktopHardware

        self.nixosModules.sopsBase

        self.nixosModules.docker
        self.nixosModules.libVirt

        self.nixosModules.sshServer
        self.nixosModules.tailscale

        self.nixosModules.ukLocalisation
        self.nixosModules.fonts
        self.nixosModules.basicUtils

        self.nixosModules.pipewire
        self.nixosModules.pipewire-5_1-to-4_1

        self.nixosModules.steam
        self.nixosModules.steamShortcuts
        self.nixosModules.steamGamescopeSession
        self.nixosModules.minecraft
        self.nixosModules.votv

        self.nixosModules.nfsMount
        self.nixosModules.hyprland
        self.nixosModules.isaacHomeManager

        self.nixosModules.nixDev
        self.nixosModules.nvim
        self.nixosModules.syncthing

        self.nixosModules.voxtype

        self.nixosModules.bootUpdate
        self.nixosModules.rustDev
        self.nixosModules.rebootWindows

        self.nixosModules.allEmulators
      ];

      hostConfig.bootUpdate = {
        enable = true;
        flakePath = "github:lamentedCauliflower/luna-config";
      };

      home-manager.users.${username}.monitors = {
        left = "HDMI-A-1";
        middle = "desc:Dell Inc. DELL U2414H 292K46B105AL";
        right = "desc:Dell Inc. DELL U2414H 9TG464CU50PL";
      };

      nixpkgs.config = {
        allowUnfree = true;
      };

      environment.sessionVariables = {
        NH_FLAKE = "github:lamentedCauliflower/luna-config";
      };

      programs.nix-index-database.comma.enable = true;

      networking.hostName = "cleodesktop";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      boot.loader = {
        limine = {
          enable = true;
          extraEntries = ''
            /Windows Boot Manager
                comment: Chainload the EFI loader on the second NVMe
                protocol: efi
                path: guid(a3d03aeb-5139-44bf-8b82-0e27ee09f133):/EFI/Microsoft/Boot/bootmgfw.efi
          '';
          force = true;
          efiSupport = true;
        };
        efi = {
          canTouchEfiVariables = true;
        };
        grub.enable = false;

      };

      networking.networkmanager = {
        enable = true;
        dns = "none";
      };

      users.users.isaac = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "pipewire"
        ];
        shell = pkgs.zsh;
      };
      nix.settings.trusted-users = [ username ];

      system.stateVersion = "25.11";

      networking = {
        interfaces.enp35s0.useDHCP = false;

        bridges."br0".interfaces = [ "enp35s0" ];

        interfaces.br0 = {
          ipv4.addresses = [
            {
              address = "192.168.0.251";
              prefixLength = 24;
            }
          ];
          useDHCP = false;
        };

        defaultGateway = {
          address = "192.168.0.1";
          interface = "br0";
        };

        useDHCP = false;
        dhcpcd.enable = false;
        nameservers = [
          "192.168.0.12"
          "8.8.8.8"
        ];

        firewall.trustedInterfaces = [ "br0" ];
      };

      swapDevices = [
        {
          device = "/swapfile";
          size = 48 * 1024;
        }
      ];

    };

}
