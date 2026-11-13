{ ... }:
let
  # Commonly used agent tools. One list for both module kinds: home-manager
  # for agents running as a user, NixOS for the Paperclip VM's agents.
  agentPackages =
    pkgs: with pkgs; [
      skills

      bash
      zsh
      tmux
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      less
      file
      which
      gnutar
      gzip
      bzip2
      xz
      zip
      unzip
      ripgrep
      fd
      fzf
      bat
      eza
      tree
      git
      diffutils
      gnupatch
      gnumake
      gh
      jq
      yq-go
      sqlite
      csvkit
      curl
      wget
      openssh
      rsync
      netcat-openbsd
      bind.dnsutils
      inetutils
      procps
      htop
      lsof
      iproute2
      psmisc
      python3
      nodejs
      pnpm
      perl
      gcc
      docker
      docker-compose
    ];
in
{
  flake.homeModules.agentTools =
    { pkgs, ... }:
    {
      home.packages = agentPackages pkgs;
    };

  flake.nixosModules.agentTools =
    { pkgs, ... }:
    {
      environment.systemPackages = agentPackages pkgs;
    };
}
