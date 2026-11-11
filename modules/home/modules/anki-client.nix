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
          url = "https://anki.luna.monkeymeat.xyz";
          username = username;
          # provisioned by the system-side sops declaration in isaacHomeManager
          keyFile = "/run/secrets/ankiSyncKey";
        };

      };
    };
}
