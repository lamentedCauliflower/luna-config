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
        device = "/dev/disk/by-uuid/258983d8-ab67-4984-96df-af4b8ce36478";
        fsType = "xfs";
        options = [
          "defaults"
          "noatime"
          "nofail"
        ];
      };

      swapDevices = [ ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };

}
