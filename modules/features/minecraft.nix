{ ... }:
{
  flake.nixosModules.minecraft =
    { pkgs, ... }:
    {

      environment.systemPackages = with pkgs; [
        (
          (prismlauncher.override {

            # Change Java runtimes available to Prism Launcher
            jdks = [
              zulu25
              zulu21
              zulu17
              # JDKs < 17 link gtk2 for Swing's GTK look-and-feel, and nixpkgs
              # now refuses to evaluate gtk2. Minecraft never touches Swing.
              (zulu8.override { gtkSupport = false; })

              graalvmPackages.graalvm-ce
            ];
          }).overrideAttrs
          (old: {
            # Drop all MIME associations (it grabs application/zip by default,
            # plus the curseforge:// and prismlauncher:// scheme handlers).
            # symlinkJoin bakes postBuild into buildCommand, so append there.
            buildCommand = old.buildCommand + ''
              desktop=$out/share/applications/org.prismlauncher.PrismLauncher.desktop
              cp --remove-destination "$(readlink -f "$desktop")" "$desktop"
              chmod +w "$desktop"
              sed -i '/^MimeType=/d' "$desktop"
            '';
          })
        )
        jdk
        packwiz

      ];

    };
}
