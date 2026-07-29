{ lib, ... }:
{
  flake.homeModules.voxtype =
    { pkgs, ... }:
    {
      services.voxtype = {
        enable = true;
        package = pkgs.voxtype-vulkan;
        # Downloaded at runtime by voxtype-model-loader.service.
        loadModels = [ "base.en" ];
        wayland.display = "wayland-1";
        environment.VOXTYPE_VULKAN_DEVICE = "nvidia";
        settings = {
          state_file = "auto";
          hotkey.enabled = false;
          audio.feedback = {
            enabled = true;
            theme = "default";
            volume = 0.7;
          };
          whisper = {
            model = "base.en";
            language = "en";
            context_window_optimization = true;
          };
          output = {
            mode = "type";
            fallback_to_clipboard = true;
          };
        };
      };

      home.sessionVariables.VOXTYPE_VULKAN_DEVICE = "nvidia";

      # Upstream module wants it on default.target; the daemon needs a compositor.
      systemd.user.services.voxtype = {
        Unit.After = [ "graphical-session.target" ];
        Unit.PartOf = lib.mkForce [ "graphical-session.target" ];
        Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
      };

      xdg.configFile."hypr/voxtype.lua".text = ''
        -- Voxtype speech-to-text keybinds
        hl.bind("Home", hl.dsp.exec_cmd("voxtype record start"))
        hl.bind("Home", hl.dsp.exec_cmd("voxtype record stop"), { release = true })
      '';

      programs.waybar.settings.main.modules-right = lib.mkAfter [ "custom/voxtype" ];

      programs.waybar.settings.main."custom/voxtype" = {
        exec = "voxtype status --follow --format json";
        "return-type" = "json";
        format = "{}";
        tooltip = true;
        "on-click" = "systemctl --user restart voxtype";
      };

      programs.waybar.style = lib.mkAfter ''
        #custom-voxtype {
          padding: 0 10px;
        }

        #custom-voxtype.recording {
          color: #ff5555;
          animation-name: pulse;
          animation-duration: 1s;
          animation-timing-function: ease-in-out;
          animation-iteration-count: infinite;
          animation-direction: alternate;
        }

        #custom-voxtype.transcribing {
          color: #f1fa8c;
        }

        #custom-voxtype.idle {
          color: #50fa7b;
        }

        #custom-voxtype.stopped {
          color: #6272a4;
        }

        @keyframes pulse {
          to {
            opacity: 0.5;
          }
        }
      '';
    };
}
