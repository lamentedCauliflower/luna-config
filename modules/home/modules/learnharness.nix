{ self, ... }:
{
  flake.homeModules.learnharness =
    { pkgs, ... }:
    {
      home.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.learnharness ];
    };
}
