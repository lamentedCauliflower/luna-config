{ self, username, ... }:
{
  flake.nixosModules.mewoSteamdeckConfiguration =
    { pkgs, ... }:
    {
      _module.args.dnsName = "mewo";

      imports = [
        self.nixosModules.mewoSteamdeckHardware

        self.nixosModules.sopsBase

        self.nixosModules.sshServer
        self.nixosModules.tailscale

        self.nixosModules.ukLocalisation
        self.nixosModules.fonts
        self.nixosModules.basicUtils

        self.nixosModules.pipewire

        self.nixosModules.steam
        self.nixosModules.steamShortcuts
        self.nixosModules.minecraft

        self.nixosModules.nfsMount
        self.nixosModules.gnome
        self.nixosModules.isaacHomeManager

        self.nixosModules.nixDev
        self.nixosModules.nvim
        self.nixosModules.syncthing

        self.nixosModules.bootUpdate

        self.nixosModules.allEmulators
      ];

      # SteamOS-like behaviour: boot straight into Gaming Mode as isaac, no
      # display manager. "Switch to Desktop" in the Steam menu launches GNOME.
      jovian = {
        devices.steamdeck = {
          enable = true;
          autoUpdate = true;
          enableGyroDsuService = true;
        };

        steam = {
          enable = true;
          autoStart = true;
          user = username;
          desktopSession = "gnome";
        };

        decky-loader.enable = true;
      };

      # Jovian's pipewire-sysconf does `rm -rf /run/pipewire` at boot to stage
      # the Deck's hardware profile, which deletes the system-wide daemon's
      # socket, and the speaker DSP filter-chain only runs as a user service
      # (BindsTo the user pipewire.service). PipeWire must run per-user here.
      services.pipewire.systemWide = false;

      hostConfig.bootUpdate = {
        enable = true;
        flakePath = "github:lamentedCauliflower/luna-config";
      };

      # Only the built-in screen; hyprland is not used on this host but its
      # home module requires monitor names.
      home-manager.users.${username}.monitors = {
        left = "eDP-1";
        middle = "eDP-1";
        right = "eDP-1";
      };

      nixpkgs.config = {
        allowUnfree = true;
        # decky-loader builds its frontend with this pnpm; bump the version
        # here if a jovian input update starts failing on a newer pnpm.
        permittedInsecurePackages = [
          "pnpm-9.15.9"
        ];
      };

      environment.sessionVariables = {
        NH_FLAKE = "github:lamentedCauliflower/luna-config";
      };

      programs.nix-index-database.comma.enable = true;

      networking.hostName = "mewosteamdeck";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      boot.loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      # Gaming Mode's network settings manage wifi through NetworkManager.
      networking.networkmanager.enable = true;

      users.users.isaac = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "pipewire"
          "networkmanager"
        ];
        shell = pkgs.zsh;
      };
      nix.settings.trusted-users = [ username ];

      system.stateVersion = "25.11";
    };

}
