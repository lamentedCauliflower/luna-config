{ ... }:
{
  flake.nixosModules.litellmContainer =
    {
      pkgs,
      dnsName,
      config,
      ...
    }:
    let
      dir = "stacks/litellm";
      webUiPort = 4000;
    in
    {
      virtualisation.docker.enable = true;

      sops.secrets.liteLLMMasterKey = { };
      sops.secrets.litellmUiPassword = { };
      sops.templates."litellm.env" = {
        content = ''
          LITELLM_MASTER_KEY=${config.sops.placeholder.liteLLMMasterKey}
          UI_USERNAME=admin
          UI_PASSWORD=${config.sops.placeholder.litellmUiPassword}
        '';
        restartUnits = [ "litellm.service" ];
      };

      environment.etc."${dir}/config.yaml".text = # yaml
        ''
          model_list:
            - model_name: github_copilot/gpt-5.2
              litellm_params:
                model: github_copilot/gpt-5.2

          litellm_settings: {}

          general_settings:
            master_key: os.environ/LITELLM_MASTER_KEY
        '';

      environment.etc."${dir}/compose.yaml".text = # yaml
        ''
          services:
            litellm:
              image: ghcr.io/berriai/litellm:main-latest
              container_name: litellm
              ports:
                - "${toString webUiPort}:4000"
              volumes:
                - /etc/${dir}/config.yaml:/app/config.yaml
              env_file:
                - ${config.sops.templates."litellm.env".path}
              command:
                - "--config"
                - "/app/config.yaml"
                - "--port"
                - "4000"
                - "--num_workers"
                - "1"
              restart: unless-stopped
              healthcheck:
                test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
                interval: 30s
                timeout: 10s
                retries: 3
                start_period: 10s
        '';

      systemd.services.litellm = {
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
          config.environment.etc."${dir}/config.yaml".source
        ];
      };

      services.caddy.virtualHosts."litellm.${dnsName}.local" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString webUiPort}
        '';
      };

      networking.firewall = {
        allowedTCPPorts = [ webUiPort ];
      };
    };
}
