{
  self,
  inputs,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  flake.nixosConfigurations.yurolaptop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.yuroLaptopConfiguration
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-index-database.nixosModules.default
      inputs.stylix.nixosModules.stylix
    ];
  };
}
