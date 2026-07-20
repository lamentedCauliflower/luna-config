{ ... }:

{
  flake.nixosModules.piholeContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/pihole";
      piholeIp = "192.168.0.12";
    in
    {

      virtualisation.docker.enable = true;

      # Route every OTHER container on this host through pihole for DNS.
      # Declared only here, so importing the pihole module is what enables it.
      # Strict single entry (no fallback): pihole is the sole resolver, no bypass.
      virtualisation.docker.daemon.settings.dns = [ piholeIp ];

      sops.secrets.piholeWebPassword = { };
      sops.templates."pihole.env" = {
        content = ''
          FTLCONF_webserver_api_password=${config.sops.placeholder.piholeWebPassword}
        '';
        restartUnits = [ "pihole.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        name: pihole
        # More info at https://github.com/pi-hole/docker-pi-hole/ and https://docs.pi-hole.net/
        services:
          pihole:
            container_name: pihole
            image: pihole/pihole:latest
            env_file:
              - ${config.sops.templates."pihole.env".path}
            ports:
              # DNS Ports
              - "${piholeIp}:53:53/tcp"
              - "${piholeIp}:53:53/udp"
              # Default HTTP Port
              - "5380:80/tcp"
              # Default HTTPs Port. FTL will generate a self-signed certificate
              # - "53443:443/tcp"
              # Uncomment the below if using Pi-hole as your DHCP Server
              #- "67:67/udp"
              # Uncomment the line below if you are using Pi-hole as your NTP server
              #- "123:123/udp"
            # pihole must NOT resolve via the daemon-wide DNS (which points back at
            # pihole itself) or first-boot gravity/blocklist fetches would wait on
            # FTL being up. Give it a real upstream instead.
            dns:
              - 1.1.1.1
            environment:
              # Set the appropriate timezone for your location from
              # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones, e.g:
              TZ: "Europe/London"
              # Web interface password comes from the sops-rendered env_file above
              # If using Docker's default `bridge` network setting the dns listening mode should be set to 'ALL'
              FTLCONF_dns_listeningMode: "ALL"
            # Volumes store your data between container upgrades
            volumes:
              # For persisting Pi-hole's databases and common configuration file
              - "/etc/${dir}/data/:/etc/pihole"
              # Uncomment the below if you have custom dnsmasq config files that you want to persist. Not needed for most starting fresh with Pi-hole v6. If you're upgrading from v5 you and have used this directory before, you should keep it enabled for the first v6 container start to allow for a complete migration. It can be removed afterwards. Needs environment variable FTLCONF_misc_etc_dnsmasq_d: 'true'
              - "/etc/${dir}/dnsmasq.d/:/etc/dnsmasq.d"
            cap_add:
              # See https://github.com/pi-hole/docker-pi-hole#note-on-capabilities
              # Required if you are using Pi-hole as your DHCP server, else not needed
              - NET_ADMIN
              # Required if you are using Pi-hole as your NTP client to be able to set the host's system time
              # - SYS_TIME
              # Optional, if Pi-hole should get some more processing time
              # - SYS_NICE
            restart: unless-stopped
      '';

      environment.etc."${dir}/dnsmasq.d/01-luna.local.conf" = {
        text = ''
          server=/luna.local/#
          address=/.luna.local/${piholeIp}
        '';
        mode = "444";
      };

      systemd.services.pihole = {
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

      services.caddy.virtualHosts."pihole.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:5380
      '';

      networking.firewall = {
        allowedTCPPorts = [
          53
          5380
        ];

        allowedUDPPorts = [
          53
        ];
      };

    };

}
