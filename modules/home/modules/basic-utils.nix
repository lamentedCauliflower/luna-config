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

    };
}
