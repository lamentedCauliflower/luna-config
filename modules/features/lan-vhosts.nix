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
            domain = lib.mkOption {
              type = lib.types.str;
              default = "${dnsName}.local";
              description = ''
                Suffix every LAN vhost hangs off, always over plain http.

                RFC 6762 reserves `.local` for mDNS, so no public CA will ever issue
                for it, and caddy's fallback is its own local CA, which no client
                trusts without per-device installation. Serving https from an
                untrusted CA trains everyone to click through certificate warnings
                and buys nothing, so a service that wants https sets `https` and
                moves to `httpsDomain` instead.

                The cost of http is that credentials cross the LAN in clear —
                hermes' dashboard auth, the pihole admin password, gitea tokens.
                With the remote_ip gate that narrows to hosts already inside the
                network, which is the tradeoff being made deliberately here.
              '';
            };

            httpsDomain = lib.mkOption {
              type = lib.types.str;
              default = "${dnsName}.monkeymeat.xyz";
              description = ''
                Real-zone suffix for services with `https` set. Their names get no
                public DNS record — pihole answers them for the LAN and the
                tailnet — so Let's Encrypt can't reach them for an HTTP challenge.
                One wildcard cert, issued over Cloudflare DNS-01 by
                nixosModules.caddy, covers them all.
              '';
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

                      https = lib.mkEnableOption ''
                        serving on `<subdomain>.<httpsDomain>` over https, leaving the
                        `.local` name as nothing but a redirect to it
                      '';
                    };
                  }
                )
              );
            };
          };

          config.services.caddy.virtualHosts = lib.concatMapAttrs (
            _: svc:
            let
              local = "http://${svc.subdomain}.${cfg.domain}";
              secure = "${svc.subdomain}.${cfg.httpsDomain}";

              # Two mutually exclusive `handle` blocks rather than a trailing bare
              # `respond`: caddy sorts directives by its own table, and handle/handle
              # states the precedence outright instead of depending on that order.
              #
              # `remote_ip` reads the actual peer address. Do not add `forwarded` —
              # that switches it to X-Forwarded-For, which is attacker-controlled on
              # a request arriving from the WAN and would undo the whole gate.
              gated = ''
                @lan remote_ip ${lib.concatStringsSep " " cfg.allowedRanges}
                handle @lan {
                  reverse_proxy ${svc.upstream}
                }
                handle {
                  respond "Not available outside the LAN" 403
                }
              '';
            in
            if svc.https then
              {
                ${secure} = {
                  useACMEHost = cfg.httpsDomain;
                  extraConfig = gated;
                };
                # 308, not 301: an API client still pointed at the old name (an
                # arr app, a subsonic player) keeps its method and body across
                # the hop instead of having a POST turned into a GET.
                ${local}.extraConfig = "redir https://${secure}{uri} 308";
              }
            else
              { ${local}.extraConfig = gated; }
          ) cfg.services;
        }
      )
    ];
  };
}
