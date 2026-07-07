{ inputs, ... }:
{
  flake.homeModules.agentTools =
    { pkgs, ... }:
    {

      home.packages = with pkgs; [
        skills

        # Commonly used agent tools
        bash
        zsh
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
        beads
      ];

    };

}
