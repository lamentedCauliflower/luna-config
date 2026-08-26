{ ... }:
{
  flake.homeModules.basic-utils =
    { ... }:
    {
      services.kdeconnect.enable = true;

      programs.kitty.enable = true;
      programs.keepassxc.enable = true;
      programs.zed-editor.enable = true;
      programs.vscode.enable = true;

      xdg.desktopEntries.kitty-open-here = {
        name = "Open in Kitty";
        exec = "kitty --directory %f";
        terminal = false;
        type = "Application";
        mimeType = [ "inode/directory" ];
        noDisplay = true;
      };

      xdg.mimeApps = {
        enable = true;
        defaultApplications."inode/directory" = "kitty-open-here.desktop";
        associations.added."inode/directory" = "kitty-open-here.desktop";
      };

    };
}
