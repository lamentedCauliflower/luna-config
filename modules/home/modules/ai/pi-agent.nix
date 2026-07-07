{ self, inputs, ... }:
{
  flake.homeModules.piAgent =
    { pkgs, ... }:
    {
      imports = [ self.homeModules.agentTools ];

      home.packages = [
        pkgs.pi-coding-agent
      ];

    };

}
