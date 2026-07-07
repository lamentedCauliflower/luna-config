{ username, ... }:
{
  flake.nixosModules.podman =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        docker-client
      ];

      virtualisation.podman.enable = true;

      users.users.${username}.extraGroups = [ "docker" ];

      # Primarily to cause error if module enabled with podman module.
      virtualisation.docker.enable = false;
    };

}
