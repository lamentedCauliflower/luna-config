{ username, ... }:

{
  flake.nixosModules.minecraftContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/minecraft";
      packwizPort = 25580;
      mcPort = 25565;
      pathPack = "/mnt/raidDrive/${username}/Minecraft/aeroPack";
    in
    {

      virtualisation.docker.enable = true;

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: packwizMcServer
        services:
          packwiz-server:
            image: getchoo/packwiz-serve
            restart: unless-stopped
            tty: true
            stdin_open: true
            ports:
              - "${toString packwizPort}:8080"
            volumes:
              - ${pathPack}/packwiz-modpack:/data


          minecraft-server:
            image: itzg/minecraft-server:java25-jdk
            pull_policy: daily
            tty: true
            stdin_open: true
            restart: unless-stopped

            ports:
              - "${toString mcPort}:25565"

            environment:
              EULA: "TRUE"
              TYPE: NEOFORGE
              VERSION: "1.21.1"
              PACKWIZ_URL: 'http://packwiz-server:8080/pack.toml'
              INIT_MEMORY: 1G
              MAX_MEMORY: 8G
            depends_on:
              packwiz-server:
                restart: true
                condition: service_started
            volumes:
              - ${pathPack}/server-data:/data
      '';

      systemd.services.minecraftServer = {
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

      services.caddy.virtualHosts."http://mc.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString packwizPort}
        '';
      };

      networking.firewall = {
        allowedTCPPorts = [
          packwizPort
          mcPort
        ];
      };

    };

}
