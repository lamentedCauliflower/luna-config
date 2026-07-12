{ self, ... }:
{
  # Aggregator: a host imports allEmulators to pull in (and enable) every
  # bundled emulator. Per-emulator enable flags also gate each emulator's Steam
  # Game Mode tile (see steam-shortcuts.nix), so a tile can never appear on a
  # host where its emulator isn't enabled.
  flake.nixosModules.allEmulators =
    { ... }:
    {
      imports = [
        self.nixosModules.ryujinxCanary
        self.nixosModules.nxOptimizer
        self.nixosModules.eden
      ];

      hostConfig.emulators.ryujinx.enable = true;
      hostConfig.emulators.nxOptimizer.enable = true;
      hostConfig.emulators.eden.enable = true;
    };
}
