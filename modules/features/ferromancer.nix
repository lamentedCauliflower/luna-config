{ inputs, ... }:
{
  # Ferromancer (gitea.luna.monkeymeat.xyz/isaac/ferromancer): a code factory
  # in its own microVM with its own private Gitea, separate from the docker
  # Gitea. Reached over plain http on `port`: the VM pins that URL into
  # Gitea's ROOT_URL (clone URLs, OIDC), so it is not fronted by caddy.
  flake.nixosModules.ferromancer =
    { pkgs, ... }:
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
        address = "ferromancer.luna.monkeymeat.xyz"; # pihole wildcard -> luna
        port = 8081; # 80 is caddy's
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

      # Hosts' br0 is already trusted; this covers tailscale clients too.
      networking.firewall.allowedTCPPorts = [ 8081 ];
    };
}
