{ ... }:

{
  flake.nixosModules.frigateContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/frigate";
    in
    {

      virtualisation.docker.enable = true;

      sops.secrets.frigateRSTPPassword = { };
      sops.secrets.frigateMqttPassword = { };
      sops.templates."frigate.env" = {
        content = ''
          FRIGATE_RTSP_PASSWORD=${config.sops.placeholder.frigateRSTPPassword}
          FRIGATE_MQTT_PASSWORD=${config.sops.placeholder.frigateMqttPassword}
        '';
        restartUnits = [ "frigate.service" ];
      };

      environment.etc."${dir}/compose.yaml".text = /* yaml */ ''
        services:
          frigate:
            privileged: true # this may not be necessary for all setups
            restart: unless-stopped
            stop_grace_period: 30s # allow enough time to shut down the various services
            image: ghcr.io/blakeblackshear/frigate:stable
            shm_size: "512mb" # update for your cameras based on calculation above

            volumes:
              - /etc/localtime:/etc/localtime:ro
              - /etc/${dir}/config:/config
              - /mnt/raidDrive/NVRRecordings:/media/frigate
            ports:
              # - "8971:8971"
              - "5000:5000" # Internal unauthenticated access. Expose carefully.
              - "8554:8554" # RTSP feeds
              - "8555:8555/tcp" # WebRTC over tcp
              - "8555:8555/udp" # WebRTC over udp
            env_file:
              - ${config.sops.templates."frigate.env".path}


      '';

      environment.etc."${dir}/config/config.yaml" = {
        text = ''
          mqtt:
            host: homeassistant
            user: mqtt_user2
            # frigate substitutes any FRIGATE_-prefixed env var into its config
            password: "{FRIGATE_MQTT_PASSWORD}"
            topic_prefix: frigate
            client_id: frigate

          tls:
            enabled: false

          cameras:
            FrontDrive: # <------ Name the camera
              enabled: true
              ffmpeg:
                inputs:
                  - path: rtsp://192.168.0.200:80/live/0/h264.sdp # <----- The stream you want to use for detection
                    roles:
                      - detect
                      - record
              detect:
                enabled: true # <---- disable detection until you have a working camera feed
                width: 1280
                height: 720
              motion:
                mask:
                  - 0,0.039,0.243,0.041,0.243,0,0,0
                  - 0,0.418,0.323,0.041,0.329,0.101,0.349,0.077,1,0.307,1,0,0,0
                threshold: 30
                contour_area: 10
                improve_contrast: true
              zones:
                Drive:
                  coordinates: 0,0.517,0.35,0.076,1,0.307,1,1,0.253,1,0,0.686
                  loitering_time: 0
                  inertia: 3
                  objects: person
              record:
                enabled: true
                retain:
                  days: 3
                  mode: all
                alerts:
                  retain:
                    days: 30
                    mode: motion
                detections:
                  retain:
                    days: 30
                    mode: motion

              snapshots:
                enabled: true
                retain:
                  default: 30
              review:
                alerts:
                  required_zones: Drive
                detections:
                  required_zones: Drive
          detect:
            enabled: true
          version: 0.16-0

          go2rtc:
            streams:
              FrontDrive:
                - rtsp://192.168.0.200:80/live/0/h264.sdp
          semantic_search:
            enabled: true
            model_size: small
          face_recognition:
            enabled: false
            model_size: small
          lpr:
            enabled: true
          classification:
            bird:
              enabled: false
        '';
        mode = "444";
      };

      systemd.services.frigate = {
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

      services.caddy.virtualHosts."frigate.${dnsName}.local".extraConfig = ''
        reverse_proxy 127.0.0.1:5000
      '';

      networking.firewall = {
        allowedTCPPorts = [
          5000
          8554
          8555
        ];

        allowedUDPPorts = [
          8555
        ];
      };

    };

}
