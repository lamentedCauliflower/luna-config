{ ... }:
{
  flake.nixosModules.scanning =
    { pkgs, ... }:
    {
      hardware.sane = {
        enable = true;

        # The scanner half of the OfficeJet Pro 7740 speaks driverless eSCL
        # (AirScan) — advertised ScannerCapabilities pwg:Version 2.5, Platen
        # and ADF, RGB24/Grayscale8 — so airscan replaces HPLIP entirely.
        extraBackends = [ pkgs.sane-airscan ];

        # sane-backends 1.4.0 ships its own `escl` backend enabled in
        # dll.conf, which discovers the same eSCL device airscan does: every
        # scan dialog would list this printer twice with no way to tell the
        # entries apart. airscan wins — better ADF/duplex handling, and it
        # speaks WSD as well as eSCL.
        disabledDefaultBackends = [ "escl" ];

        # openFirewall is left at false deliberately: it exists for Canon's
        # BJNP, whereas airscan is client-initiated HTTP plus avahi discovery
        # over D-Bus. Nothing needs to listen.
      };

      # Discovery, same as printing.nix — see the nssmdns4 comment there for
      # why nss-mdns stays off. Both modules setting these to equal values is
      # safe: types.bool merges via mergeEqualOption.
      services.avahi = {
        enable = true;
        nssmdns4 = false;
        nssmdns6 = false;
      };

      # Network eSCL means there is no USB device, so no scanner/lp group
      # membership is needed to reach it.
      environment.systemPackages = [ pkgs.simple-scan ];
    };
}
