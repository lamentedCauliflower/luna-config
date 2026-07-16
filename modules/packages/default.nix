{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # perSystem packages otherwise get nixpkgs' vanilla legacyPackages,
      # which refuses unfree derivations (votv is unfree freeware).
      # Instantiate pkgs once here with allowUnfree, mirroring the hosts'
      # nixpkgs.config.allowUnfree.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
}
