{ ... }:
{
  flake.nixosModules.printing =
    { ... }:
    {
      services.printing = {
        enable = true;

        # cups-browsed's enable default is `config.services.avahi.enable`, so
        # turning avahi on below would otherwise start it implicitly. cupsd
        # 2.4 does its own DNS-SD browsing and materialises a temporary queue
        # when an app opens a print dialog, so browsed buys nothing here — it
        # only adds a second daemon and the UDP 631 listener behind the 2024
        # CUPS chain (CVE-2024-47176 and friends). cleoDesktop puts br0 in
        # firewall.trustedInterfaces, so anything listening is reachable by
        # the whole LAN. Pinned explicitly so a nixpkgs default flip cannot
        # quietly start it.
        browsed.enable = false;
      };

      # Discovery only. The printer (HP OfficeJet Pro 7740) advertises
      # IPP Everywhere / AirPrint — `urf-supported`, image/urf, image/pwg-raster
      # — so CUPS drives it with no PPD, no HPLIP and no unfree HP plugin.
      # Queues are created on demand from DNS-SD rather than declared with
      # hardware.printers.ensurePrinters: that runs `lpadmin -m everywhere` at
      # activation, which would make every `nh os switch` on yuroLaptop depend
      # on the printer being reachable. See docs/adr/0005.
      services.avahi = {
        enable = true;

        # cups and sane-airscan both link libavahi-client and browse DNS-SD
        # over D-Bus, so neither needs nss-mdns — it only affects glibc
        # hostname resolution. Leaving it off keeps /etc/nsswitch.conf
        # untouched. Enabling it inserts `mdns4_minimal [NOTFOUND=return]`
        # ahead of dns, which claims any *two-label* .local name; three-label
        # names like jellyfin.luna.local fall through safely, but the bare
        # `luna.local` record pihole serves (address=/.luna.local/ in
        # containers/pihole.nix) would resolve via mDNS, find no responder,
        # and stop there. /etc/mdns.allow cannot rescue it — the minimal
        # module does not read that file.
        nssmdns4 = false;
        nssmdns6 = false;
      };
    };
}
