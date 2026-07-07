# The vanilla nixpkgs gamescope session. Kept separate from the core steam
# module because mewoSteamdeck uses Jovian's gamescope session instead and
# the two must not coexist.
{ ... }:
{
  flake.nixosModules.steamGamescopeSession =
    { ... }:
    {
      programs.steam.gamescopeSession = {
        enable = true;
      };
    };

}
