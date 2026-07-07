{ username, ... }:
{
  flake.homeModules.chromium =
    { pkgs, ... }:
    let
      # ponytail: pinned CRXs; bump version/hash when Chrome Web Store updates them.
      chromiumExtension =
        { id, version, hash }:
        {
          inherit id version;
          crxPath = pkgs.fetchurl {
            name = "${id}.crx";
            url = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=${pkgs.ungoogled-chromium.version}&acceptformat=crx3&x=id%3D${id}%26installsource%3Dondemand%26uc";
            inherit hash;
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
            id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; # uBlock Origin
            version = "1.72.0";
            hash = "sha256-b18FKOXz5mGKbIMd5TvmXz95KQ7fTT44Qzk46xGCQ/I=";
          })
          (chromiumExtension {
            id = "enamippconapkdmgfgjchkhakpfinmaj"; # DeArrow
            version = "2.3.9";
            hash = "sha256-X501o/+rOGVkjkRbDCq0HU4g9kg8g+8bioPSHd+z4bc=";
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
        defaultSearchProviderSearchURL = "https://4get.luna.local/web?s={searchTerms}";
        extraOpts = {
          DefaultSearchProviderName = "4get";
          DefaultSearchProviderKeyword = "4get";
          BrowserThemeColor = config.home-manager.users.${username}.lib.stylix.colors.withHashtag.base00;
        };
      };
    };
}
