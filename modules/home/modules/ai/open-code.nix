{ self, inputs, ... }:
{
  flake.homeModules.openCode =
    { pkgs, ... }:
    {
      imports = [ self.homeModules.agentTools ];

      home.packages = [
        inputs.open-code.packages.${pkgs.stdenv.hostPlatform.system}.opencode
      ];

    };

}
