{ ... }:
{
  flake.homeModules.discord = {

    programs.vesktop = {
      # enable = true; # pnpm-10.29.2 insecure (CVEs), vesktop build-time dep; re-enable when nixpkgs bumps pin

      vencord.settings = {
        autoUpdate = true;
        autoUpdateNotification = true;
        notifyAboutUpdates = true;

        plugins = {
          ClearURLs.enabled = true;
          FixYoutubeEmbeds.enabled = true;
        };
      };

    };
  };
}
