{ ... }:
{
  flake.homeModules.basic-utils =
    { ... }:
    {
      services.kdeconnect.enable = true;

      programs.kitty.enable = true;
      # Enabling keepassxc also links its native messaging manifest into
      # chromium and librewolf, which is the other half of the KeePassXC-Browser
      # extension those modules force-install. The matching "Enable browser
      # integration" checkbox stays a one-time GUI step on purpose: declaring
      # programs.keepassxc.settings makes keepassxc.ini a read-only store
      # symlink, so KeePassXC can no longer write its own state (recent
      # databases, window geometry) and nags about it on every launch
      # (home-manager #8257).
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
