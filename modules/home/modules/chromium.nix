{ username, ... }:
{
  flake.homeModules.chromium =
    { pkgs, ... }:
    let
      # ponytail: pinned CRXs; bump version/hash when Chrome Web Store updates them.
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
          (chromiumExtension {
            id = "enamippconapkdmgfgjchkhakpfinmaj"; # DeArrow
            version = "2.3.10";
            hash = "sha256-TDLGuKJs6KdnwGkjrnwAFgPxSj/uAwBE6CHZPYaclYA=";
          })
          (chromiumExtension {
            id = "mnjggcdmjocbbbhaepdhchncahnbgone"; # SponsorBlock
            version = "6.1.6";
            hash = "sha256-VYf+K2qZRhAcoN3nxu/nanVcXuW21uY9/EjH9zbNtP8=";
          })
          (chromiumExtension {
            id = "gnfldmcodokkpcejgdlffnjakifemick"; # Imgur Unblocker
            version = "2.0.2";
            hash = "sha256-yPZ+1wnoWsCxjubw3DHXgmrra76Li0HDXdyzMPgWsQA=";
          })
          (chromiumExtension {
            id = "oboonakemofpalcgghocfoadofidjkkk"; # KeePassXC-Browser
            version = "1.10.4";
            hash = "sha256-VueAiAgfIO058jvmBujYOPgr1Go8fJGHtNzBvXYcA7k=";
          })
        ];
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
