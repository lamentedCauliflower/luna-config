{ username, ... }:
{
  flake.nixosModules.lunaNFSServer =
    { ... }:
    {
      fileSystems."/export/${username}" = {
        device = "/mnt/raidDrive/${username}";
        fsType = "none";
        options = [ "bind" ];
      };

      fileSystems."/export/media" = {
        device = "/mnt/raidDrive/media";
        fsType = "none";
        options = [ "bind" ];
      };

      services.nfs.server = {
        enable = true;
        lockdPort = 4001;
        mountdPort = 4002;
        statdPort = 4000;
        exports = ''
          /export 192.168.0.0/24(fsid=0,crossmnt,rw,nohide,no_subtree_check,async) 100.0.0.0/8(fsid=0,crossmnt,rw,nohide,no_subtree_check,async)
          /export/${username} 192.168.0.0/24(fsid=456,rw,nohide,no_subtree_check,async) 100.0.0.0/8(fsid=456,crossmnt,rw,nohide,no_subtree_check,async)
          /export/media 192.168.0.0/24(fsid=789,rw,nohide,insecure,no_subtree_check,async) 100.0.0.0/8(fsid=789,crossmnt,rw,nohide,insecure,no_subtree_check,async)
        '';
      };

      networking.firewall = {
        allowedTCPPorts = [
          111
          2049
          4000
          4001
          4002
        ];

        allowedUDPPorts = [
          111
          2049
          4000
          4001
          4002
        ];
      };

    };

}
