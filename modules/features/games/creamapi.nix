{ inputs, ... }:
{
  flake.nixosModules.creamapi =
    { pkgs, ... }:
    {
      # CreamLinux GUI for managing CreamAPI/SmokeAPI DLC ids. Upstream is not a
      # flake, so the input is a plain source tree with its own default.nix.
      environment.systemPackages = [
        (import inputs.creamlinux { inherit pkgs; })
      ];
    };
}
