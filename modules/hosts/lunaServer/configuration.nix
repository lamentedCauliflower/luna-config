{ self, username, ... }:
{
  flake.nixosModules.lunaServerConfiguration =
    { pkgs, ... }:
    let
      flakePath = "/mnt/raidDrive/${username}/luna-config";
    in
    {

      _module.args.dnsName = "luna";

      imports = [
        self.nixosModules.lunaServerHardware

        self.nixosModules.sopsBase

        self.nixosModules.autoUpdate

        self.nixosModules.dockerFullStack

        self.nixosModules.lunaNFSServer
        self.nixosModules.lunaSambaServer

        self.nixosModules.sshServer
        self.nixosModules.caddy
        self.nixosModules.tailscale

        self.nixosModules.ukLocalisation
        self.nixosModules.basicUtils
        self.nixosModules.nixDev
        self.nixosModules.libVirt
        self.nixosModules.hermesVm

        self.nixosModules.ankiServer
        self.nixosModules.syncthing

        self.nixosModules.honcho
        self.nixosModules.taskchampionSyncServer

      ];

      nixpkgs.config = {
        allowUnfree = true;
      };

      hostConfig.autoUpdate.flakePath = flakePath;

      environment.sessionVariables = {
        NH_FLAKE = flakePath;
      };

      programs.nix-index-database.comma.enable = true;

      networking.hostName = "lunaserver";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      boot.loader = {
        grub = {
          enable = true;
          device = "nodev";
          efiSupport = true;
        };
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot/efi";
        };
      };

      networking.networkmanager = {
        enable = true;
        dns = "none";
      };
      users.users.${username} = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        shell = pkgs.zsh;
      };
      nix.settings.trusted-users = [ username ];

      system.stateVersion = "25.11";

      networking = {
        interfaces.eno1.useDHCP = false;

        bridges."br0".interfaces = [ "eno1" ];

        interfaces.br0 = {
          ipv4.addresses = [
            {
              address = "192.168.0.12";
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
          "1.1.1.1"
          "8.8.8.8"
        ];

        firewall.trustedInterfaces = [ "br0" ];
      };

      services.caddy.virtualHosts."homeassistant.luna.local".extraConfig = ''
        reverse_proxy 192.168.0.10:8123
      '';

      services.caddy.virtualHosts."homeassistant.monkeymeat.xyz".extraConfig = ''
        reverse_proxy 192.168.0.10:8123
      '';

      swapDevices = [
        {
          device = "/swapfile";
          size = 16 * 1024;
        }
      ];
    };

}
