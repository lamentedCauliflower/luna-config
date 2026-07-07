{ ... }:
{
  flake.nixosModules.rebootWindows =
    { pkgs, ... }:
    {

      environment.systemPackages = [ pkgs.efibootmgr ];

      programs.zsh.interactiveShellInit = ''
        reboot-windows() {
          local entry
          entry=$(efibootmgr | grep -i 'Windows Boot Manager' | sed -n 's/^Boot\([0-9A-F]\{4\}\).*/\1/p')
          if [[ -n "$entry" ]]; then
            sudo efibootmgr --bootnext "$entry" && sudo reboot
          else
            echo "Windows Boot Manager not found in EFI boot entries" >&2
            return 1
          fi
        }
      '';

    };
}
