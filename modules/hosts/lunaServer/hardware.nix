{ username, ... }:
{
  flake.nixosModules.lunaServerHardware =
    {
      config,
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot.initrd.availableKernelModules = [
        "uhci_hcd"
        "ehci_pci"
        "ata_piix"
        "megaraid_sas"
        "usb_storage"
        "usbhid"
        "sd_mod"
        "sr_mod"
        "ipmi_si"
        "ipmi_devintf"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-intel" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/c9f15969-8a25-4298-96ec-41d31c758dfa";
        fsType = "btrfs";
        options = [
          "subvol=root"
          "compress=zstd"
        ];
      };

      fileSystems."/home" = {
        device = "/dev/disk/by-uuid/c9f15969-8a25-4298-96ec-41d31c758dfa";
        fsType = "btrfs";
        options = [
          "subvol=home"
          "compress=zstd"
        ];
      };

      fileSystems."/nix" = {
        device = "/dev/disk/by-uuid/c9f15969-8a25-4298-96ec-41d31c758dfa";
        fsType = "btrfs";
        options = [
          "subvol=nix"
          "compress=zstd"
          "noatime"
        ];
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/0E15-0CCD";
        fsType = "vfat";
        options = [
          "fmask=0022"
          "dmask=0022"
        ];
      };

      fileSystems."/mnt/raidDrive" = {
        device = "/dev/disk/by-uuid/c851e16a-f6e5-4eea-8eb8-d05d44ae0897";
        fsType = "btrfs";
        options = [
          "subvol=base"
          "compress=zstd"
        ];
      };

      fileSystems."/mnt/raidDrive/${username}" = {
        device = "/dev/disk/by-uuid/c851e16a-f6e5-4eea-8eb8-d05d44ae0897";
        fsType = "btrfs";
        options = [
          "subvol=isaac"
          "compress=zstd"
        ];
      };

      fileSystems."/mnt/raidDrive/media" = {
        device = "/dev/disk/by-uuid/c851e16a-f6e5-4eea-8eb8-d05d44ae0897";
        fsType = "btrfs";
        options = [
          "subvol=media"
          "compress=zstd"
        ];
      };

      swapDevices = [ ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };

}
