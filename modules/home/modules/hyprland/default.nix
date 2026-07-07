{ self, ... }:
{
  flake.homeModules.hyprland =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      wallpaperPath = "${config.home.homeDirectory}/.config/hypr/wallpaper.png";
      monitors = config.monitors;

      hyprlandLua = ''
        -- ── Variables ──
        local terminal = "kitty"
        local menu     = "rofi -show drun"

        -- ── Autostart ──
        hl.on("hyprland.start", function()
          hl.exec_cmd("waybar")
          hl.exec_cmd("hyprpaper")
        end)

        -- ── Monitors ──
        hl.monitor({ output = "${monitors.left}",   mode = "1920x1080@60", position = "0x0",    scale = 1 })
        hl.monitor({ output = "${monitors.middle}", mode = "1920x1080@60", position = "1920x0", scale = 1 })
        hl.monitor({ output = "${monitors.right}",  mode = "1920x1080@60", position = "3840x0", scale = 1 })

        -- ── General ──
        hl.config({
          ecosystem = { no_update_news = true },
          cursor    = { no_hardware_cursors = true, enable_hyprcursor = true },
          general   = {
            gaps_in  = 5,
            gaps_out = 20,
            border_size     = 2,
            resize_on_border = false,
            allow_tearing    = false,
            layout = "dwindle",
          },
          decoration = {
            rounding       = 10,
            rounding_power = 2,
            active_opacity   = 1.0,
            inactive_opacity = 1.0,
            shadow = {
              enabled      = true,
              range        = 4,
              render_power = 3,
            },
            blur = {
              enabled  = true,
              size     = 3,
              passes   = 1,
              vibrancy = 0.1696,
            },
          },
          dwindle = { preserve_split = true },
          master  = { new_status = "master" },
          misc = {
            force_default_wallpaper = 0,
            disable_hyprland_logo  = true,
          },
          input = {
            kb_layout  = "us",
            kb_variant = "",
            kb_model   = "",
            kb_options = "",
            kb_rules   = "",
            follow_mouse   = 0,
            sensitivity    = 0,
            force_no_accel = false,
            touchpad = { natural_scroll = false },
          },
        })

        -- ── Curves ──
        hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 } } })
        hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
        hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })
        hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })
        hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })

        -- ── Animations ──
        hl.config({ animations = { enabled = true } })
        hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
        hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
        hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
        hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
        hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
        hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
        hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
        hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
        hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
        hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
        hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
        hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
        hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
        hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
        hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
        hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
        hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

        -- ── Workspaces ──
        hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
        hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
        hl.workspace_rule({ workspace = "1", monitor = "${monitors.left}",   default = true, persistent = true })
        hl.workspace_rule({ workspace = "2", monitor = "${monitors.left}",   persistent = true })
        hl.workspace_rule({ workspace = "3", monitor = "${monitors.left}",   persistent = true })
        hl.workspace_rule({ workspace = "4", monitor = "${monitors.middle}", default = true, persistent = true })
        hl.workspace_rule({ workspace = "5", monitor = "${monitors.middle}", persistent = true })
        hl.workspace_rule({ workspace = "6", monitor = "${monitors.middle}", persistent = true })
        hl.workspace_rule({ workspace = "7", monitor = "${monitors.right}",  default = true, persistent = true })
        hl.workspace_rule({ workspace = "8", monitor = "${monitors.right}",  persistent = true })
        hl.workspace_rule({ workspace = "9", monitor = "${monitors.right}",  persistent = true })

        -- ── Window Rules ──
        hl.window_rule({ name = "no-gaps-wtv1",   match = { float = false, workspace = "w[tv1]" }, border_size = 0, rounding = 0 })
        hl.window_rule({ name = "no-gaps-f1",      match = { float = false, workspace = "f[1]" },   border_size = 0, rounding = 0 })
        hl.window_rule({ name = "suppress-max",     match = { class = ".*" },                        suppress_event = "maximize" })
        hl.window_rule({ name = "no-focus-xwayland", match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false }, no_focus = true })
        hl.window_rule({ name = "zed-to-middle",    match = { class = "(?i)zed" },                  monitor = "${monitors.middle}" })
        hl.window_rule({ name = "chromium-right",   match = { class = "(?i)chromium" },             monitor = "${monitors.right}" })
        hl.window_rule({ name = "steam-tile",       match = { class = "steam" },                    tile = true })
        hl.window_rule({ name = "deadlock-fs",      match = { class = "deadlock" },                 fullscreen = true })

        -- ── Gestures ──
        hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

        -- ── Device ──
        hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })

        -- ── Keybinds ──
        hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal))
        hl.bind("SUPER + C",      hl.dsp.window.close())
        hl.bind("SUPER + V",      hl.dsp.window.float({ action = "toggle" }))
        hl.bind("SUPER + R",      hl.dsp.exec_cmd(menu))
        hl.bind("SUPER + P",      hl.dsp.window.pseudo())
        hl.bind("SUPER + F",      hl.dsp.window.fullscreen())

        require("graceful-close")
        require("voxtype")

        -- Focus
        hl.bind("SUPER + left",  hl.dsp.focus({ direction = "left" }))
        hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
        hl.bind("SUPER + up",    hl.dsp.focus({ workspace = "r+1" }))
        hl.bind("SUPER + down",  hl.dsp.focus({ workspace = "r-1" }))

        -- Move windows
        hl.bind("SUPER + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
        hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
        hl.bind("SUPER + SHIFT + up",    hl.dsp.window.move({ workspace = "r+1" }))
        hl.bind("SUPER + SHIFT + down",  hl.dsp.window.move({ workspace = "r-1" }))

        -- Workspaces 1-9
        for i = 1, 9 do
          hl.bind("SUPER + " .. i,             hl.dsp.focus({ workspace = i }))
          hl.bind("SUPER + SHIFT + " .. i,     hl.dsp.window.move({ workspace = i }))
        end

        -- Special workspace (scratchpad)
        hl.bind("SUPER + S",         hl.dsp.workspace.toggle_special("magic"))
        hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

        -- Scroll workspaces
        hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
        hl.bind("SUPER + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

        -- Mouse drag/resize
        hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
        hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

        -- Media / brightness (locked + repeating where appropriate)
        hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
        hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
        hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
        hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
        hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
        hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

        hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
        hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
        hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
        hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
      '';
    in
    {
      imports = [
        self.homeModules.hyprlandGracefullClose
      ];

      options.monitors = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          left = "HDMI-A-1";
          middle = "DP-5";
          right = "DP-3";
        };
        description = "Monitor mapping for Hyprland";
      };

      config = {

        # Copy wallpaper to hypr config directory
        xdg.configFile."hypr/wallpaper.png".source = ../../../../assets/wallpaper.png;
        services.hyprpaper = {
          enable = true;
          settings = {
            preload = [ wallpaperPath ];
            wallpaper = [ ", ${wallpaperPath}" ];
          };
        };

        wayland.windowManager.hyprland = {
          enable = true;
          configType = "lua";
        };

        xdg.configFile."hypr/hyprland.lua".text = hyprlandLua;

        xdg.portal.config.hyprland = {
          default = [
            "hyprland"
            "gtk"
          ];
        };

        programs.rofi.enable = true;

        programs.waybar = {
          enable = true;
          settings.main = {
            modules-right = [
              "mpd"
              "clock"
              "battery"
            ];
            modules-left = [ "hyprland/workspaces" ];
          };
        };

        xdg.portal = {
          enable = true;
          extraPortals = [
            pkgs.xdg-desktop-portal-hyprland
            pkgs.xdg-desktop-portal-gtk
          ];
        };
      };
    };

}
