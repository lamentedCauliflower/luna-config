{
  self,
  inputs,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  flake.nixosConfigurations.cleodesktop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.cleoDesktopConfiguration
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-index-database.nixosModules.default
      inputs.stylix.nixosModules.stylix
    ];
  };
}
