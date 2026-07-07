{ ... }:
{
  flake.homeModules.mpv = {
    programs.mpv.enable = true;
    xdg.mimeApps = {
      defaultApplications = {
        "audio/mpeg" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";
        "audio/vnd.wav" = "mpv.desktop";
        "audio/ogg" = "mpv.desktop";
        "audio/opus" = "mpv.desktop";
        "video/mp4" = "mpv.desktop";
      };
    };
  };
}
