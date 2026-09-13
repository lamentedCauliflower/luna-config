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
        # Obselete
        # self.nixosModules.frigateContainer
        # self.nixosModules.rommContainer
        # self.nixosModules.litellmContainer
        # self.nixosModules.fourgetContainer # 4get dead, back to google
        self.nixosModules.octoprintContainer
        self.nixosModules.giteaContainer
        self.nixosModules.hermesContainer
        self.nixosModules.minecraftContainer
      ];

    };

}
