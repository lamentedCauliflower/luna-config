{ self, inputs, ... }:
{
  flake.homeModules.claudeCode =
    { pkgs, ... }:
    {

      imports = [ self.homeModules.agentTools ];

      home.packages = [
        inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

    };

}
