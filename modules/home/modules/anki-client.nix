{ username, ... }:
{
  flake.homeModules.ankiClient =
    { ... }:
    {
      programs.anki = {
        enable = true;
        style = "native";
        theme = "dark";

        profiles.${username}.sync = {
          url = "http://anki.luna.local";
          username = username;
          # provisioned by the system-side sops declaration in isaacHomeManager
          keyFile = "/run/secrets/ankiSyncKey";
        };

      };
    };
}
