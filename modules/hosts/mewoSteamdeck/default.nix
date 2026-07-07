{
  self,
  inputs,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  flake.nixosConfigurations.mewosteamdeck = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.mewoSteamdeckConfiguration
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-index-database.nixosModules.default
      inputs.stylix.nixosModules.stylix
      inputs.jovian.nixosModules.default
    ];
  };
}
