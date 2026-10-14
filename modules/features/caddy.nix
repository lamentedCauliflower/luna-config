{ self, ... }:
{
  flake.nixosModules.caddy =
    { config, ... }:
    let
      inherit (config.hostConfig.lanVhosts) httpsDomain;
    in
    {
      # Brings in hostConfig.lanVhosts, which every LAN-only service declares
      # itself through. Importing caddy without it would let a service fall
      # back to a bare virtualHosts entry and quietly lose the remote_ip gate.
      imports = [ self.nixosModules.lanVhosts ];

      services.caddy.enable = true;

      # The one wildcard cert behind every lanVhost with `https` set. Those
      # names are LAN-only, so DNS-01 is the only challenge that can work; it
      # needs nothing inbound. The token is scoped to Zone:Read + DNS:Edit on
      # monkeymeat.xyz alone.
      sops.secrets.cloudflareApiToken = { };

      security.acme = {
        acceptTerms = true;
        certs.${httpsDomain} = {
          domain = "*.${httpsDomain}";
          dnsProvider = "cloudflare";
          credentialFiles.CF_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflareApiToken.path;
          # lego 5 also waits for the TXT record on the system resolvers, but
          # its own zone lookup just made them cache NXDOMAIN for that name for
          # Cloudflare's 30 min SOA minimum, so the wait always times out.
          # Checking the authoritative servers alone is what lego 4 did.
          extraLegoFlags = [ "--dns.propagation.disable-rns" ];
        };
      };

      networking.firewall = {
        allowedTCPPorts = [
          80
          443
        ];

        allowedUDPPorts = [
          80
          443
        ];
      };
    };
}
