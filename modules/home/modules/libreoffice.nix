{ ... }:
{
  flake.homeModules.libreoffice =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          libreoffice

          # libreoffice ships no dictionaries, so spellcheck is silently a
          # no-op without one. en_GB-ise matches the spelling used everywhere
          # else in this repo.
          hunspellDicts.en_GB-ise
        ];
      };
    };
}
