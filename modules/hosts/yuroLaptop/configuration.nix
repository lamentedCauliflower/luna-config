{ self, username, ... }:
{
  flake.nixosModules.yuroLaptopConfiguration =
    { pkgs, ... }:
    {
      _module.args.dnsName = "yuro";

      imports = [
        self.nixosModules.yuroLaptopHardware

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

        self.nixosModules.nfsMount
        self.nixosModules.hyprland
        self.nixosModules.isaacHomeManager

        self.nixosModules.nixDev
        self.nixosModules.nvim

        self.nixosModules.syncthing
        self.nixosModules.rebootWindows
      ];

      nixpkgs.config = {
        allowUnfree = true;
      };

      environment.sessionVariables = {
        NH_FLAKE = "github:lamentedCauliflower/luna-config";
      };

      programs.nix-index-database.comma.enable = true;

      networking.hostName = "yurolaptop";

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
                path: guid(38d503da-d75e-43e1-ab43-0751700db854):/EFI/Microsoft/Boot/bootmgfw.efi
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

      swapDevices = [
        {
          device = "/swapfile";
          size = 16 * 1024;
        }
      ];

      home-manager.users.${username}.monitors = {
        left = "eDP-1";
        middle = "DP-1";
        right = "DP-2";
      };
    };

}
