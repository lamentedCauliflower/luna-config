{ self, ... }:

{
  flake.nixosModules.dockerFullStack =
    {
      ...
    }:
    {
      imports = [
        self.nixosModules.dockerMediaStack
        self.nixosModules.docker
        self.nixosModules.piholeContainer
        self.nixosModules.fourgetContainer
        # Obselete
        # self.nixosModules.frigateContainer
        self.nixosModules.rommContainer
        self.nixosModules.octoprintContainer
        self.nixosModules.giteaContainer
        self.nixosModules.minecraftContainer
        self.nixosModules.litellmContainer
      ];

    };

}
