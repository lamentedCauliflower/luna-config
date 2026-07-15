{ self, ... }:
{
  # Aggregator: a host imports allEmulators to pull in every bundled emulator
  # (importing a module enables it — repo standard). Each emulator module
  # declares its own Game Mode Tile, so a tile can never appear on a host
  # without its emulator — but the host must also import steamShortcuts or
  # evaluation fails loudly (see docs/adr/0003).
  flake.nixosModules.allEmulators =
    { ... }:
    {
      imports = [
        self.nixosModules.ryujinxCanary
        self.nixosModules.nxOptimizer
        self.nixosModules.eden
      ];
    };
}
