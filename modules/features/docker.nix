{ username, ... }:
{
  flake.nixosModules.docker =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        docker-client
      ];

      virtualisation.docker.enable = true;
        
      users.users.${username}.extraGroups = [ "docker" ];

      # Primarily to cause error if module enabled with podman module.
      virtualisation.podman.enable = false;
    };

}
