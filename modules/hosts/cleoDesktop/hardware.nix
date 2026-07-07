{ ... }:
{
  flake.nixosModules.cleoDesktopHardware =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/79a48e83-ee7a-4e99-896c-f39d3a953f07";
        fsType = "btrfs";
        options = [ "subvol=@" ];
      };

      fileSystems."/home" = {
        device = "/dev/disk/by-uuid/79a48e83-ee7a-4e99-896c-f39d3a953f07";
        fsType = "btrfs";
        options = [ "subvol=@home" ];
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/8473-CADC";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        modesetting.enable = true;
        # RTX 2080 (Turing) supports NVIDIA's current production branch.
        open = false;
        package = config.boot.kernelPackages.nvidiaPackages.production;
      };

      hardware.opentabletdriver.enable = true;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          vulkan-loader
          vulkan-validation-layers
          vulkan-extension-layer
          nvidia-vaapi-driver
          libva-vdpau-driver
          libvdpau-va-gl
        ];
      };

      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        # Helps with Wayland/NVIDIA flickering or mapping issues
        WLR_NO_HARDWARE_CURSORS = "1";
      };

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.xpadneo.enable = true;
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };

}
