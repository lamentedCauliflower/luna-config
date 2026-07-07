{ username, ... }:
{
  flake.homeModules.librewolf =
    { pkgs, ... }:
    {

      home.sessionVariables = {
        DEFAULT_BROWSER = "${pkgs.librewolf}/bin/librewolf";
      };

      programs.librewolf = {
        enable = true;
        settings = {
          "webgl.disabled" = false;
          "privacy.clearOnShutdown.history" = false;
          "privacy.clearOnShutdown.cookies" = false;
          "privacy.resistFingerprinting" = false;
          "network.cookie.lifetimePolicy" = 0;
        };
        profiles = {
          ${username} = {
            id = 0;
            name = username;
            isDefault = true;
          };
        };
      };

      xdg.mimeApps.defaultApplications = {
        "text/html" = "librewolf.desktop";
        "x-scheme-handler/http" = "librewolf.desktop";
        "x-scheme-handler/https" = "librewolf.desktop";
        "x-scheme-handler/about" = "librewolf.desktop";
        "x-scheme-handler/unknown" = "librewolf.desktop";
      };
    };
}
