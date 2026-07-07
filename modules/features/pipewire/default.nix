{ ... }:
{
  flake.nixosModules.pipewire ={pkgs, ...}:{
    environment.systemPackages = with pkgs; [
      pwvucontrol
    ];


    security.rtkit.enable = true;
    services.pipewire = {
      enable = true; # if not already enabled
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      systemWide = true;
      extraConfig = {
        pipewire-pulse."20-upmix" = {
          "stream.properties" = {
            "channelmix.upmix" = true;
            "channelmix.upmix-method" = "psd";
            "channelmix.lfe-cutoff" = 200;
            "channelmix.fc-cutoff" = 12000;
            "channelmix.rear-delay" = 12.0;
          };
        };
      };
    };
  };

}
