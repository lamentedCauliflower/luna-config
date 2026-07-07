{ self, ... }:
{
  flake.homeModules.allAgents =
    { ... }:
    {
      imports = [
        self.homeModules.openCode
        self.homeModules.claudeCode
        self.homeModules.codex
        self.homeModules.piAgent
      ];

    };

}
