{ config, ... }:
{
  flake.nixosModules.basicUtils =
    { pkgs, ... }:
    {

      programs.git = {
        enable = true;
      };

      programs.yazi.enable = true;

      programs.zsh = {
        enable = true;

        shellAliases = {
          nos-update = "nh os boot --update";
        };

        # nix-shell and nix develop otherwise drop into bash.
        interactiveShellInit = ''
          ${pkgs.nix-your-shell}/bin/nix-your-shell zsh | source /dev/stdin
        '';

        # Name what a nix shell added, on the right. `nix shell` sets no marker
        # and only prepends store paths to PATH, so diff against the outermost
        # shell's PATH (agent/editor wrappers already carry store paths).
        # Dev shells set IN_NIX_SHELL and pull in all of stdenv: label only.
        promptInit = ''
          export __ZSH_OUTER_PATH=''${__ZSH_OUTER_PATH-$PATH}
          () {
            local -a outer=(''${(s.:.)__ZSH_OUTER_PATH})
            local -a added=(''${''${(M)path:#/nix/store/*}:|outer})
            if [[ -n $IN_NIX_SHELL ]]; then
              RPROMPT='[nix-shell]'
            elif (( $#added )); then
              # /nix/store/<hash>-jq-1.8.2-bin/bin -> jq
              added=(''${(u)''${''${added#/nix/store/*-}%/bin}%%-[0-9]*})
              RPROMPT="[nix: $added]"
            fi
          }
        '';

        ohMyZsh = {
          enable = true;
          theme = "darkblood";
          plugins = [
            "github"
            "git"
            "tailscale"
            "sudo"
            "docker"
            "docker-compose"
            "ssh"
            "rsync"
            "podman"
            "lxd"
            "npm"
            "nvm"
          ];
        };
      };

      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          # List by default
          zlib
          zstd
          stdenv.cc.cc
          curl
          openssl
          attr
          libssh
          bzip2
          libxml2
          acl
          libsodium
          util-linux
          xz
          systemd

          # My own additions
          libxcomposite
          libxtst
          libxrandr
          libxext
          libx11
          libxfixes
          libGL
          libva
          pipewire
          libxcb
          libxdamage
          libxshmfence
          libxxf86vm
          libelf

          # Required
          glib
          gtk2

          # Inspired by steam
          # https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/st/steam/package.nix#L36-L85
          networkmanager
          vulkan-loader
          libgbm
          libdrm
          libxcrypt
          coreutils
          pciutils
          zenity
          # glibc_multi.bin # Seems to cause issue in ARM

          # # Without these it silently fails
          libxinerama
          libxcursor
          libxrender
          libxscrnsaver
          libxi
          libSM
          libICE
          # gnome2.GConf removed upstream (deprecated); no nix-ld replacement needed
          nspr
          nss
          cups
          libcap
          SDL2
          libusb1
          dbus-glib
          ffmpeg
          # Only libraries are needed from those two
          libudev0-shim

          # needed to run unity
          gtk3
          icu
          libnotify
          gsettings-desktop-schemas
          # https://github.com/NixOS/nixpkgs/issues/72282
          # https://github.com/NixOS/nixpkgs/blob/2e87260fafdd3d18aa1719246fd704b35e55b0f2/pkgs/applications/misc/joplin-desktop/default.nix#L16
          # log in /home/leo/.config/unity3d/Editor.log
          # it will segfault when opening files if you don’t do:
          # export XDG_DATA_DIRS=/nix/store/0nfsywbk0qml4faa7sk3sdfmbd85b7ra-gsettings-desktop-schemas-43.0/share/gsettings-schemas/gsettings-desktop-schemas-43.0:/nix/store/rkscn1raa3x850zq7jp9q3j5ghcf6zi2-gtk+3-3.24.35/share/gsettings-schemas/gtk+3-3.24.35/:$XDG_DATA_DIRS
          # other issue: (Unity:377230): GLib-GIO-CRITICAL **: 21:09:04.706: g_dbus_proxy_call_sync_internal: assertion 'G_IS_DBUS_PROXY (proxy)' failed

          # Verified games requirements
          libxt
          libxmu
          libogg
          libvorbis
          SDL
          SDL2_image
          glew_1_10
          libidn
          tbb

          # Other things from runtime
          flac
          freeglut
          libjpeg
          libpng
          libpng12
          libsamplerate
          libmikmod
          libtheora
          libtiff
          pixman
          speex
          SDL_image
          SDL_ttf
          SDL_mixer
          SDL2_ttf
          SDL2_mixer
          libcaca
          libcanberra
          libgcrypt
          libvpx
          librsvg
          libxft
          libvdpau
          # ...
          # Some more libraries that I needed to run programs
          pango
          cairo
          atk
          gdk-pixbuf
          fontconfig
          freetype
          dbus
          alsa-lib
          expat
          # for blender
          libxkbcommon

          libxcrypt-legacy # For natron
          libGLU # For natron

          # Appimages need fuse, e.g. https://musescore.org/fr/download/musescore-x86_64.AppImage
          fuse
          e2fsprogs

          fribidi
          harfbuzz
          libgpg-error
          gmp

        ];
      };

      environment.systemPackages = with pkgs; [
        steam-run
        rsync
        wget
        git-agecrypt
        htop
        tree
        kitty
        curl
        nh
        neovim
        gh
        nixos-firewall-tool
        tea
      ];

      security.polkit.enable = true;

      programs.direnv.enable = true;

    };

}
