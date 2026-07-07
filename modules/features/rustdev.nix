{ ... }:
{
  flake.nixosModules.rustDev =
    { pkgs, ... }:
    {

      environment.systemPackages = with pkgs; [
        # Core Rust toolchain
        cargo
        rustc
        rustfmt
        clippy
        rust-analyzer

        # Useful cargo subcommands
        cargo-watch
        cargo-audit
        cargo-expand

        # Database tooling
        sqlx-cli

        # Common C dependencies & build tools
        gcc
        pkg-config
        openssl
      ];
    };

}
