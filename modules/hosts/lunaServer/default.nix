{
  self,
  inputs,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  flake.nixosConfigurations.lunaserver = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.lunaServerConfiguration
      inputs.hermes-agent.nixosModules.default
      inputs.nix-index-database.nixosModules.default
      inputs.nixvirt.nixosModules.default
    ];
  };
}
