{ ... }:
{
  # Shared shape for every caddy vhost that is meant to stay on the LAN.
  #
  # Caddy matches a vhost on hostname alone. lunaServer forwards 80/443 from
  # the WAN (homeassistant.monkeymeat.xyz holds a real Let's Encrypt cert, so
  # inbound ACME validation reaches it), and this repo is public, so every
  # service name here is already known to anyone who reads it. Declaring a
  # bare `services.caddy.virtualHosts."sonarr.luna.local"` therefore publishes
  # Sonarr to the internet to anyone willing to send that Host header at the
  # WAN IP. The remote_ip gate below is what makes these LAN-only in fact and
  # not merely by naming convention.
  flake.nixosModules.lanVhosts = {
    # Imported from more than one place: nixosModules.caddy pulls it in on
    # lunaServer, nixosModules.syncthing on the desktops that run no caddy. An
    # explicit key is what makes that idempotent — without one the module
    # system keys an anonymous function module by its import site, sees two
    # distinct modules, and fails with "hostConfig.lanVhosts.services is
    # already declared".
    key = "luna-config/lan-vhosts";

    imports = [
      (
        {
          config,
          lib,
          dnsName,
          ...
        }:
        let
          cfg = config.hostConfig.lanVhosts;
        in
        {
          options.hostConfig.lanVhosts = {
            scheme = lib.mkOption {
              type = lib.types.enum [
                "http"
                "https"
              ];
              default = "http";
              description = ''
                Scheme every LAN vhost is served on.

                http is the honest default while these names end in `.local`. RFC
                6762 reserves that suffix for mDNS, so no public CA will ever issue
                for it, and caddy's fallback is its own local CA, which no client
                trusts without per-device installation. Serving https from an
                untrusted CA trains everyone to click through certificate warnings
                and buys nothing. Flip this to "https" in one place once `domain`
                moves to a real zone and caddy can get real certificates.

                The cost of http is that credentials cross the LAN in clear —
                hermes' dashboard auth, the pihole admin password, gitea tokens.
                With the remote_ip gate that narrows to hosts already inside the
                network, which is the tradeoff being made deliberately here.
              '';
            };

            domain = lib.mkOption {
              type = lib.types.str;
              default = "${dnsName}.local";
              description = "Suffix every LAN vhost hangs off.";
            };

            allowedRanges = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "127.0.0.1/8"
                "::1/128"
                "192.168.0.0/24"
                "172.16.0.0/12"
                "100.64.0.0/10"
              ];
              description = ''
                Source ranges allowed to reach a LAN vhost; everything else gets a
                403. Covers loopback, the LAN itself, docker's bridge networks
                (containers resolve these names through pihole and so arrive from
                172.16/12, not from loopback) and tailscale's CGNAT range.
              '';
            };

            services = lib.mkOption {
              default = { };
              description = "LAN-only reverse proxies fronted by caddy.";
              type = lib.types.attrsOf (
                lib.types.submodule (
                  { name, ... }:
                  {
                    options = {
                      subdomain = lib.mkOption {
                        type = lib.types.str;
                        default = name;
                        description = "Label in front of `domain`; defaults to the attribute name.";
                      };

                      upstream = lib.mkOption {
                        type = lib.types.str;
                        example = "127.0.0.1:8989";
                        description = "host:port caddy reverse-proxies to.";
                      };
                    };
                  }
                )
              );
            };
          };

          config.services.caddy.virtualHosts = lib.mapAttrs' (
            _: svc:
            lib.nameValuePair "${cfg.scheme}://${svc.subdomain}.${cfg.domain}" {
              # Two mutually exclusive `handle` blocks rather than a trailing bare
              # `respond`: caddy sorts directives by its own table, and handle/handle
              # states the precedence outright instead of depending on that order.
              #
              # `remote_ip` reads the actual peer address. Do not add `forwarded` —
              # that switches it to X-Forwarded-For, which is attacker-controlled on
              # a request arriving from the WAN and would undo the whole gate.
              extraConfig = ''
                @lan remote_ip ${lib.concatStringsSep " " cfg.allowedRanges}
                handle @lan {
                  reverse_proxy ${svc.upstream}
                }
                handle {
                  respond "Not available outside the LAN" 403
                }
              '';
            }
          ) cfg.services;
        }
      )
    ];
  };
}
