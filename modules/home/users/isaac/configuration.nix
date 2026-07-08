{ self, inputs, ... }:
{
  flake.homeModules.isaacConfiguration = {
    imports = [
      self.homeModules.hyprland
      self.homeModules.discord
      self.homeModules.mpd
      self.homeModules.mpv
      self.homeModules.musicOrganisation
      self.homeModules.basic-utils
      self.homeModules.chromium
      self.homeModules.librewolf
      self.homeModules.jellyfin
      self.homeModules.stylix
      self.homeModules.voxtype
      self.homeModules.threeDPrinting

      self.homeModules.ankiClient
      self.homeModules.taskwarrior

      self.homeModules.allAgents

      inputs.stylix.homeModules.stylix
    ];

    home.username = "isaac";
    home.homeDirectory = "/home/isaac";
    home.stateVersion = "25.11";

    programs.home-manager.enable = true;

  };
}
