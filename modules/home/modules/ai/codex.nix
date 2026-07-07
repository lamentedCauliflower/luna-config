{ self, ... }:
{
  flake.homeModules.codex =
    { pkgs, ... }:
    {

      imports = [ self.homeModules.agentTools ];

      home.packages = [
        pkgs.codex
      ];

    };

}
