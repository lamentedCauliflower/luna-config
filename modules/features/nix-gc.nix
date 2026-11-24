{ ... }:
{
  flake.nixosModules.nixGc =
    { ... }:
    {
      # Weekly GC of anything older than 14 days, plus an on-demand GC
      # whenever free space drops below 20 GiB (freeing up to 60 GiB).
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      nix.settings = {
        min-free = 20 * 1024 * 1024 * 1024;
        max-free = 60 * 1024 * 1024 * 1024;
      };
    };
}
