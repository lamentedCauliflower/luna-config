{ username, ... }:
{
  flake.homeModules.chromium =
    { pkgs, lib, ... }:
    let
      chromiumExtension =
        {
          id,
          version,
          hash,
          url ? "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=${pkgs.ungoogled-chromium.version}&acceptformat=crx3&x=id%3D${id}%26installsource%3Dondemand%26uc",
        }:
        {
          inherit id version;
          crxPath = pkgs.fetchurl {
            name = "${id}.crx";
            inherit url hash;
          };
        };
    in
    {
      home.sessionVariables.DEFAULT_BROWSER = "${pkgs.ungoogled-chromium}/bin/chromium";

      programs.chromium = {
        enable = true;
        package = pkgs.ungoogled-chromium;
        extensions = [
          (chromiumExtension {
            # uBlock Origin (MV2) is gone from the Chrome Web Store; gorhill's
            # GitHub CRX is signed with its own key, hence the different ID.
            id = "fkgkibajhfbepljeaefdnfnegdcjomkh";
            version = "1.75.0";
            url = "https://github.com/gorhill/uBlock/releases/download/1.75.0/uBlock0_1.75.0.chromium.crx";
            hash = "sha256-1ojtPwJi7E+L3NTI9lmHxURMVgrrOHqeAqyh+s36cEY=";
          })
        ]
        # ponytail: the Chrome Web Store only serves each extension's latest CRX
        # (old blob URLs go 400), so these pins fail any fresh fetch once upstream
        # ships. update-chromium-extensions.sh re-pins them all and runs with
        # every flake update; vendoring the CRXs is the fix if the gap ever bites.
        ++ lib.mapAttrsToList (
          id: ext:
          chromiumExtension {
            inherit id;
            inherit (ext) version hash;
          }
        ) (lib.importJSON ./chromium-extensions.json);
      };

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = "chromium-browser.desktop";
          "x-scheme-handler/http" = "chromium-browser.desktop";
          "x-scheme-handler/https" = "chromium-browser.desktop";
          "x-scheme-handler/about" = "chromium-browser.desktop";
          "x-scheme-handler/unknown" = "chromium-browser.desktop";
        };
      };
    };

  flake.nixosModules.chromium =
    { config, ... }:
    {
      programs.chromium = {
        enable = true;
        defaultSearchProviderEnabled = true;
        defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
        extraOpts = {
          DefaultSearchProviderName = "Google";
          DefaultSearchProviderKeyword = "google";
          BrowserThemeColor = config.home-manager.users.${username}.lib.stylix.colors.withHashtag.base00;
        };
      };
    };
}
