{ ... }:
{
  flake.nixosModules.taskchampionSyncServer =
    { pkgs, config, dnsName, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8666 ];

      systemd.services.taskchampion-sync-server = {
        description = "TaskChampion Sync Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.taskchampion-sync-server}/bin/taskchampion-sync-server --listen 127.0.0.1:8666 --data-dir /var/lib/taskchampion-sync-server";
          StateDirectory = "taskchampion-sync-server";
          DynamicUser = true;
          Restart = "on-failure";
        };
      };

      services.caddy.virtualHosts."tasksync.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:8666
        '';
      };
    };
}
