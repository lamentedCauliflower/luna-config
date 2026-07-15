{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Merges a JSON list of Non-Steam Shortcuts into every Steam account's
      # shortcuts.vdf (see steam-shortcuts.nix for the systemd unit that runs
      # it). Pure python + vdf, so no platform pin.
      packages.steam-shortcuts-writer = lib.addMetaAttrs {
        description = "Merge declarative non-Steam shortcuts into Steam's shortcuts.vdf";
        mainProgram = "steam-shortcuts-writer";
      } (
        pkgs.writers.writePython3Bin "steam-shortcuts-writer" {
          libraries = [ pkgs.python3Packages.vdf ];
          flakeIgnore = [ "E501" ];
        } (builtins.readFile ./steam-shortcuts-writer.py)
      );
    };
}
