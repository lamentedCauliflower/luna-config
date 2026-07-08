{ username, ... }:
{
  flake.homeModules.librewolf =
    { pkgs, inputs, ... }:
    let
      ffAddons = inputs.nur.legacyPackages.${pkgs.stdenv.hostPlatform.system}.repos.rycee.firefox-addons;

      # LibreWolf ignores home-manager's profiles.<name>.extensions.packages at
      # runtime (HM #7948 / Firefox #1960117: it won't follow the symlink-to-
      # symlink chain HM builds). Force-install via the enterprise policy instead
      # — LibreWolf then copies the real xpi into its own profile, no symlink.
      # install_url points at the pinned NUR-built xpi (see lib/mozilla.nix for
      # the fixed store layout).
      forceInstall = pkg: {
        name = pkg.addonId;
        value = {
          installation_mode = "force_installed";
          install_url = "file://${pkg}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${pkg.addonId}.xpi";
        };
      };
    in
    {
      # Chromium is the Default Browser; librewolf installs alongside it but must
      # not claim DEFAULT_BROWSER or the html/http(s) mime handlers.
      programs.librewolf = {
        enable = true;

        # Mirror chromium's extension set. uBlock Origin ships built into
        # LibreWolf, so it is not declared here. Imgur Unblocker is absent from
        # the NUR set and is intentionally skipped.
        policies.ExtensionSettings = builtins.listToAttrs [
          (forceInstall ffAddons.dearrow)
          (forceInstall ffAddons.sponsorblock)
        ];

        settings = {
          "webgl.disabled" = false;
          "privacy.clearOnShutdown.history" = false;
          "privacy.clearOnShutdown.cookies" = false;
          "privacy.resistFingerprinting" = false;
          "network.cookie.lifetimePolicy" = 0;

          # Steam Deck Game Mode (gamescope): entering video fullscreen makes
          # Firefox spawn a separate fullscreen widget/window that gamescope
          # rescales badly (flicker/black/wrong size). Keeping fullscreen inside
          # the existing window avoids the window swap.
          "full-screen-api.ignore-widgets" = true;
        };
        profiles = {
          ${username} = {
            id = 0;
            name = username;
            isDefault = true;

            # Mirror chromium's 4get default search.
            search = {
              force = true;
              default = "4get";
              engines."4get" = {
                urls = [ { template = "https://4get.luna.local/web?s={searchTerms}"; } ];
                definedAliases = [ "@4g" ];
              };
            };
          };
        };
      };
    };
}
