{ inputs, ... }:
{
  # Ferromancer (gitea.luna.monkeymeat.xyz/isaac/ferromancer): a code factory
  # in its own microVM with its own private Gitea, separate from the docker
  # Gitea. Fronted by caddy (LAN-only, https); the VM's own forward is
  # loopback-only and ROOT_URL is forced to the caddy name.
  flake.nixosModules.ferromancer =
    { config, lib, pkgs, ... }:
    let
      port = 8081;
      host = "ferromancer.${config.hostConfig.lanVhosts.httpsDomain}";
    in
    {
      imports = [ inputs.ferromancer.nixosModules.default ];

      sops.secrets = {
        ferromancerOperatorPassword = { };
        ferromancerDeepseekKey = { };
      };

      # The VM runs on the nixpkgs Ferromancer is tested against (its gt needs
      # a newer Go than luna's), not luna's. A bump of that pin starts a fresh
      # Nix store image (see the module's volume naming).
      microvm.vms.ferro.pkgs =
        inputs.ferromancer.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};

      services.ferromancer = {
        enable = true;
        address = host;
        inherit port;
        operator = {
          username = "isaac";
          email = "isaac.birchall@googlemail.com";
          passwordFile = "/run/secrets/ferromancerOperatorPassword";
        };
        providers.deepseek.apiKeyFile = "/run/secrets/ferromancerDeepseekKey";
        agents.owner = {
          role = "owner";
          description = "Owns the Ferro: specs and grills ideas on DeepSeek.";
          model = "deepseek/deepseek-flash";
          thinking = "max";
        };
      };

      # The module pins ROOT_URL to http://address:port (clone URLs, login
      # redirects); browsers arrive via caddy on https with no port, and Gitea
      # refuses a form POST whose Origin differs. The backend reaches Gitea on
      # the guest's loopback, so only browsers and clone URLs see this.
      microvm.vms.ferro.config = {
        ferromancer.rootUrl = lib.mkForce "https://${host}/gitea/";
        # Reached by caddy on luna only, not the LAN.
        microvm.forwardPorts = lib.mkForce [
          {
            host = {
              address = "127.0.0.1";
              inherit port;
            };
            guest.port = 80;
          }
        ];
      };

      hostConfig.lanVhosts.services.ferromancer.upstream = "127.0.0.1:${toString port}";
    };
}
