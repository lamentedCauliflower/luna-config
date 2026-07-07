{ ... }:
{
  flake.nixosModules.minecraft =
    { pkgs, ... }:
    {

      environment.systemPackages = with pkgs; [
        (prismlauncher.override {

          # Change Java runtimes available to Prism Launcher
          jdks = [
            zulu25
            zulu21
            zulu17
            zulu8

            graalvmPackages.graalvm-ce
          ];
        })
        jdk
        packwiz

      ];

    };
}
