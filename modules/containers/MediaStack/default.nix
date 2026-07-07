{ self, ... }:

{
  flake.nixosModules.dockerMediaStack =
    {
      ...
    }:
    {
      imports = [
        self.nixosModules.arrStackContainer
        self.nixosModules.jellyfinContainer
        self.nixosModules.navidromeContainer
      ];

    };

}
