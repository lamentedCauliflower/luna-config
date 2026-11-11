{ inputs, ... }:
{
  flake.nixosModules.sopsBase =
    { ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      };

      # sops-install-secrets is built from the sops-nix input, not nixpkgs, so
      # cache.nixos.org lacks it; nix-community's cache has it. Key from the
      # Cachix API (app.cachix.org/api/v1/cache/nix-community).
      nix.settings = {
        extra-substituters = [ "https://nix-community.cachix.org" ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
}
