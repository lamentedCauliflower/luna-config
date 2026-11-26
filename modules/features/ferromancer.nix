{ inputs, ... }:
{
  # Ferromancer (gitea.luna.monkeymeat.xyz/isaac/ferromancer): a code factory
  # in its own microVM with its own private Gitea, separate from the docker
  # Gitea. Fronted by caddy (LAN-only, https); the VM's own forward is
  # loopback-only and ROOT_URL is forced to the caddy name.
  flake.nixosModules.ferromancer =
    { config, lib, pkgs, ... }:
    let
      port = 8081;
      host = "ferromancer.${config.hostConfig.lanVhosts.httpsDomain}";
    in
    {
      imports = [ inputs.ferromancer.nixosModules.default ];

      sops.secrets = {
        ferromancerOperatorPassword = { };
        ferromancerDeepseekKey = { };
        ferromancerAnthropicKey = { };
        braveSearchAPIKey = { };
      };

      # The VM runs on the nixpkgs Ferromancer is tested against (its gt needs
      # a newer Go than luna's), not luna's. A bump of that pin starts a fresh
      # Nix store image (see the module's volume naming).
      microvm.vms.ferro.pkgs =
        inputs.ferromancer.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};

      services.ferromancer = {
        enable = true;
        address = host;
        inherit port;
        operator = {
          username = "isaac";
          email = "isaac.birchall@googlemail.com";
          passwordFile = "/run/secrets/ferromancerOperatorPassword";
        };
        providers.deepseek.apiKeyFile = "/run/secrets/ferromancerDeepseekKey";
        providers.anthropic.apiKeyFile = "/run/secrets/ferromancerAnthropicKey";
        # For the research skill's web_search.
        webSearch.apiKeyFile = "/run/secrets/braveSearchAPIKey";

        # Names picked in pi: the DeepSeek Agents chose their own; DeepSeek named the Claude ones.
        agents =
          let
            research = {
              github = {
                owner = "mattpocock";
                repo = "skills";
                rev = "6f7f7831a625f040a8e06a0e7954826b87ce775a";
                hash = "sha256-kM/OK6+kbTHzlN5d6wjL9hM80lolcSCoO8A1oRvEJEU=";
                path = "skills/engineering/research";
              };
            };
            ponytail = {
              github = {
                owner = "DietrichGebert";
                repo = "ponytail";
                rev = "ebd8654c2c627f721eb8f9c0d1bd4090a29f9e10";
                hash = "sha256-5m6JW3U6EMYUg4YVLh7nRRTWGY3shrFQ0wK0bediVFc=";
                path = "skills/ponytail";
              };
            };
            # Claude subscription OAuth: shapes requests when the key is an sk-ant-oat token.
            anthropicAuth = {
              npm = {
                name = "@gotgenes/pi-anthropic-auth";
                version = "3.6.0";
                hash = "sha512-kO1oMOlPa4d78RmZVBZUdjidpOmyLouSg6ny19YwDBsOwYWutSKi+5vCABqN6X7Mn0W+zBXd4noPjGnm0Fw4Sg==";
              };
            };
            # Planners cannot push, so research lands where they can write.
            plannerResearch = ''
              Before planning, research the open questions with the research skill and post the
              findings, with their sources, as a comment on the PRD issue: you cannot push files.
              Name on every ticket the reviewers vesper (scope) then mira (code quality), in that order.
            '';
          in
          {
            arlo = {
              role = "owner";
              title = "Chief Executive";
              description = "Turns the Operator's ideas into PRDs, researches and proposes direction, creates repositories.";
              model = "anthropic/claude-opus-5-5";
              thinking = "xhigh";
              extensions = [ anthropicAuth ];
              chat.enable = true;
              skills = [ research ];
              dailyCostCap = 30;
              prompt = ''
                Data PRDs go to orion, backend PRDs to ferris. Propose, with research behind it, before you decide.
              '';
            };

            orion = {
              role = "planner";
              title = "Data Architect";
              description = "Plans data models and schemas (DKNF and 5NF) and tickets them for jory.";
              model = "anthropic/claude-opus-5-5";
              thinking = "high";
              extensions = [ anthropicAuth ];
              reportsTo = "arlo";
              skills = [ research ];
              dailyCostCap = 20;
              prompt = ''
                Every schema you plan is in domain-key normal form and fifth normal form: state each
                table's keys, domains and the join dependencies you checked. Constraints live in the
                database, not in application code. Assign data-layer tickets to jory.
              '' + plannerResearch;
            };

            ferris = {
              role = "planner";
              title = "Systems Architect";
              description = "Plans the backend, preferring Rust, and tickets it for juno.";
              model = "anthropic/claude-opus-5-5";
              thinking = "high";
              extensions = [ anthropicAuth ];
              reportsTo = "arlo";
              skills = [ research ];
              dailyCostCap = 20;
              prompt = ''
                Prefer Rust for the backend unless research shows a clear reason not to, and say it
                on the plan. Build on orion's schemas; never redesign them. Assign backend tickets
                to juno and documentation tickets to quill.
              '' + plannerResearch;
            };

            jory = {
              role = "implementer";
              title = "Data Engineer";
              description = "Implements data-layer tickets: migrations, schemas, queries.";
              model = "deepseek/deepseek-flash";
              thinking = "high";
              reportsTo = "orion";
              prompt = ''
                Implement the schema exactly as planned, keys and constraints included, as migrations.
              '';
            };

            juno = {
              role = "implementer";
              title = "Systems Engineer";
              description = "Implements backend tickets in Rust with the least code that works.";
              model = "deepseek/deepseek-flash";
              thinking = "high";
              reportsTo = "ferris";
              skills = [ ponytail ];
              prompt = ''
                Load the ponytail skill before writing code. Run `cargo test` and `cargo clippy` before every push.
              '';
            };

            vesper = {
              role = "reviewer";
              title = "Scope Reviewer";
              description = "Reviews pull requests for scope: does it do what its ticket asked, no more, no less.";
              model = "deepseek/deepseek-flash";
              thinking = "high";
              reportsTo = "arlo";
              tools.exclude = [ "edit" "write" ];
              prompt = ''
                Review scope only: request changes for anything missing from the ticket or added beyond it.
              '';
            };

            mira = {
              role = "reviewer";
              title = "Code Quality Reviewer";
              description = "Reviews pull requests for correctness, clarity and needless complexity, after scope review.";
              model = "deepseek/deepseek-flash";
              thinking = "high";
              reportsTo = "arlo";
              tools.exclude = [ "edit" "write" ];
              prompt = ''
                Review code quality only: correctness, tests, clarity, and code that need not exist.
              '';
            };

            quill = {
              role = "implementer";
              title = "Docs Writer";
              description = "Writes and maintains the project's documentation.";
              model = "anthropic/claude-sonnet-5-5";
              thinking = "high";
              extensions = [ anthropicAuth ];
              reportsTo = "arlo";
              prompt = ''
                Your pull requests change documentation only, so skip test-first; check that every
                command and path you document exists in the repository.
              '';
            };
          };
      };

      # The module pins ROOT_URL to http://address:port (clone URLs, login
      # redirects); browsers arrive via caddy on https with no port, and Gitea
      # refuses a form POST whose Origin differs. The backend reaches Gitea on
      # the guest's loopback, so only browsers and clone URLs see this.
      microvm.vms.ferro.config = {
        ferromancer.rootUrl = lib.mkForce "https://${host}/gitea/";
        # Reached by caddy on luna only, not the LAN.
        microvm.forwardPorts = lib.mkForce [
          {
            host = {
              address = "127.0.0.1";
              inherit port;
            };
            guest.port = 80;
          }
        ];
      };

      hostConfig.lanVhosts.services.ferromancer.upstream = "127.0.0.1:${toString port}";
    };
}
