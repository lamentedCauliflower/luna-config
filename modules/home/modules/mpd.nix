{ ... }:
{
  flake.homeModules.mpd = {

    home.sessionVariables = {
      MPD_HOST = "localhost";
      MPD_PORT = "6600";
    };

    services.mpd = {
      enable = true;
      musicDirectory = "/mnt/media/Music";
      network.startWhenNeeded = true;
      network.listenAddress = "any";
      extraConfig = ''
        audio_output {
          type            "pipewire"
          name            "Pipewire Output"
        }
      '';
    };

    programs.rmpc = {
      enable = true;
      config = ''
        (
          address: "127.0.0.1:6600",
          password: None,
          enable_mouse: true,
        )
      '';
    };
  };
}
