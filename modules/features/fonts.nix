{ ... }:
{
  flake.nixosModules.fonts =
    { pkgs, ... }:
    {
      fonts = {
        packages = with pkgs; [
          # icon fonts
          material-design-icons

          # normal fonts
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji

          # nerdfonts
          # https://github.com/NixOS/nixpkgs/blob/nixos-unstable-small/pkgs/data/fonts/nerd-fonts/manifests/fonts.json
          nerd-fonts.symbols-only # symbols icon only
          nerd-fonts.fira-code
          nerd-fonts.jetbrains-mono
          nerd-fonts.iosevka
        ];

        # use fonts specified by user rather than default ones
        enableDefaultPackages = false;

        # user defined fonts
        # the reason there's Noto Color Emoji everywhere is to override DejaVu's
        # B&W emojis that would sometimes show instead of some Color emojis
        fontconfig.defaultFonts = {
          serif = [
            "Noto Serif"
            "Noto Color Emoji"
          ];
          sansSerif = [
            "Noto Sans"
            "Noto Color Emoji"
          ];
          monospace = [
            "JetBrainsMono Nerd Font"
            "Noto Color Emoji"
          ];
          emoji = [ "Noto Color Emoji" ];
        };
      };

    };

}
