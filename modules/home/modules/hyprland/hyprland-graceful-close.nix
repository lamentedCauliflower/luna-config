{ ... }:
{
  flake.homeModules.hyprlandGracefullClose =
    { pkgs, ... }:
    let
      gracefulExit = pkgs.writeShellScript "hyprland-graceful-exit" ''
        ${pkgs.hyprland}/bin/hyprctl clients -j \
          | ${pkgs.jq}/bin/jq -r '.[].address' \
          | while read addr; do
              ${pkgs.hyprland}/bin/hyprctl dispatch closewindow "address:$addr"
            done
        sleep 5
        ${pkgs.hyprland}/bin/hyprctl dispatch exit
      '';
    in
    {
      home.packages = [ pkgs.jq ];

      xdg.configFile."hypr/graceful-close.lua".text = ''
        -- Graceful close: ask windows to close, then exit

        hl.bind("SUPER + M",         hl.dsp.exec_cmd("${gracefulExit}"))
        hl.bind("SUPER + SHIFT + M", hl.dsp.exit())
      '';
    };
}
