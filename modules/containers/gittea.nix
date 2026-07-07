{ ... }:

{
  flake.nixosModules.giteaContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/gitea";
      webUiPort = 3000;
    in
    {

      virtualisation.docker.enable = true;

      sops.secrets.giteaDbPassword = { };
      sops.templates."gitea.env" = {
        content = ''
          GITEA__database__PASSWD=${config.sops.placeholder.giteaDbPassword}
          POSTGRES_PASSWORD=${config.sops.placeholder.giteaDbPassword}
        '';
        restartUnits = [ "gitea.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        networks:
          gitea:
            external: false

        services:
          gitea:
            image: docker.gitea.com/gitea:1.25.4

            env_file:
              - ${config.sops.templates."gitea.env".path}
            environment:
              - USER_UID=1000
              - USER_GID=1000
              - GITEA__database__DB_TYPE=postgres
              - GITEA__database__HOST=gitea-db:5432
              - GITEA__database__NAME=gitea
              - GITEA__database__USER=gitea
            restart: always
            networks:
              - gitea
            volumes:
              - /var/lib/${dir}/data:/data
              - /etc/timezone:/etc/timezone:ro
              - /etc/localtime:/etc/localtime:ro
            ports:
              - "${toString webUiPort}:3000"
              - "222:22"
            depends_on:
              - gitea-db

          gitea-db:
            image: docker.io/library/postgres:14
            restart: always
            env_file:
              - ${config.sops.templates."gitea.env".path}
            environment:
              - POSTGRES_USER=gitea
              - POSTGRES_DB=gitea
            networks:
              - gitea
            volumes:
              - /var/lib/${dir}/postgres:/var/lib/postgresql/data


      '';

      systemd.services.gitea = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        path = [ pkgs.docker ];
        script = ''
          docker compose -f /etc/${dir}/compose.yaml up
        '';
        restartTriggers = [
          config.environment.etc."${dir}/compose.yaml".source
        ];
      };

      services.caddy.virtualHosts."gitea.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString webUiPort}
        '';
      };

      networking.firewall = {
        allowedTCPPorts = [
          webUiPort
          222
        ];
      };

    };

}
