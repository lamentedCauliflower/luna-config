{ username, ... }:
{
  flake.nixosModules.nfsMount =
    { ... }:
    {
      systemd.tmpfiles.rules = [
        "d /mnt/media 0755 ${username} users -"
        "d /mnt/isaac 0700 ${username} users -"
      ];

      boot.supportedFilesystems = [ "nfs" ];

      fileSystems."/mnt/media" = {
        device = "192.168.0.12:/media";
        fsType = "nfs";
        options = [
          "rw"
          "nfsvers=4.2"
          "noatime"
          "nofail"
        ];
      };

      fileSystems."/mnt/${username}" = {
        device = "192.168.0.12:/${username}";
        fsType = "nfs";
        options = [
          "rw"
          "nfsvers=4.2"
          "noatime"
          "nofail"
        ];
      };
    };

}
