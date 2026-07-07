# AGENTS.md

NixOS flake managing multiple hosts (server + desktops). `flake-parts` + `import-tree`. No app code, no test suite — changes are validated by building the flake.

## Module system (read this first)

`flake.nix` imports `(import-tree ./modules)`: **every `.nix` file under `modules/` is auto-imported** as a flake-parts module. Adding a file wires it into the flake automatically — there is no central import list to edit.

Each module file has two layers, do not confuse their argument sets:

```nix
{ self, inputs, username, ... }:        # outer = flake-parts args
{
  flake.nixosModules.myThing =          # defines, does NOT enable
    { pkgs, config, dnsName, ... }:     # inner = NixOS module args
    { ... };                            # actual NixOS config
}
```

- Outer args: `self`, `inputs`, `username` (from `_module.args` in flake.nix).
- Defining a module ≠ enabling it. Modules are turned on explicitly by being listed in a host's `imports` (see `modules/hosts/<host>/configuration.nix`).
- Naming: files are kebab-case, but the `flake.nixosModules.<key>` / `flake.homeModules.<key>` keys are camelCase (e.g. `basic-utils.nix` → `basicUtils`). Match existing keys when referencing.
- `dnsName` is a per-host `_module.args` value (`"luna"` on lunaServer). Services build Caddy vhosts as `<svc>.${dnsName}.local`.

## Hosts

`nixosConfigurations` names are lowercase; directories are CamelCase.

| config name | dir | role |
|---|---|---|
| `lunaserver` | `modules/hosts/lunaServer` | home server, all containers/services |
| `cleodesktop` | `modules/hosts/cleoDesktop` | desktop |
| `yurolaptop` | `modules/hosts/yuroLaptop` | laptop |

Each `hosts/<h>/default.nix` declares `flake.nixosConfigurations.<name>` and pulls in `self.nixosModules.<h>Configuration`; `configuration.nix` is the per-host `imports` list that selects features.

## Directory map

- `modules/features/` — reusable NixOS feature modules (one concern each).
- `modules/containers/` — Docker containers, aggregated by `dockerFullStack` (`containers/default.nix`). Docker and Podman are mutually exclusive; `docker.nix` deliberately sets `virtualisation.podman.enable = false` to fail loudly if both load.
- `modules/home/` — Home Manager: `home/modules/` units, `home/users/isaac/` aggregates them.
- `modules/hosts/` — per-host wiring + hardware.
- `secrets/secrets.yaml` + `.sops.yaml` — see Secrets below.

## Build / apply

Uses `nh` (not raw `nixos-rebuild`). `NH_FLAKE` is set to `/mnt/raidDrive/isaac/luna-config` on the server — that is the deploy checkout path, **not** this repo's working dir.

- Build only (safe check): `nh os build` or `nixos-rebuild build --flake .#<host>`
- Validate flake: `nix flake check`
- Apply on next boot: `nh os boot` / switch now: `nh os switch`
- `nos-update` alias = `nh os boot --update` (also run by a systemd timer from the `bootUpdate` module).

There is no lint/format/typecheck/CI. Verify changes by building the affected host before committing.

## Hermes VM (domain term — get it right)

Hermes Agent gateway runs in a **Debian libvirt/qemu VM** named `hermes-vm` (`modules/features/hermes-vm.nix`), not a container or NixOS guest. Listens on port 5678; lunaServer reverse-proxies `hermes.luna.local` to it. Rationale: ADR `docs/adr/0001-use-debian-libvirt-vm-for-hermes-agent.md`. Canonical name is "Hermes VM"; avoid `microvm`, `hernes-vm`. See `CONTEXT.md` for the full glossary.

## Secrets

Managed by **sops-nix** (see `docs/adr/0002`). `secrets/secrets.yaml` is age-encrypted to the hosts' SSH ed25519 host keys plus Isaac's personal key (recipients in `.sops.yaml`). Never commit plaintext secrets anywhere — not in nix strings either, since interpolated values end up world-readable in `/nix/store`.

- Edit secrets: `nix run nixpkgs#sops -- secrets/secrets.yaml` (admin identity lives in `~/.config/sops/age/keys.txt`; sops finds it automatically).
- Each consumer module declares its own `sops.secrets.<name>` next to its usage; `sopsBase` (`modules/features/sops-base.nix`) sets the default sops file and is imported per host.
- Docker stacks consume secrets via `sops.templates."<svc>.env"` env-files referenced from the compose yaml (`env_file:`), with `restartUnits` so secret changes restart the service. Exception: romm uses `docker compose --env-file` interpolation to keep container env byte-identical to its pre-sops mariadb init (see comment in `romm.nix`).
- Home-manager consumers read `/run/secrets/...` paths; the system-side declarations live in `modules/home/users/isaac/default.nix` (`owner = username`).
- Adding a host: `ssh-keyscan -t ed25519 <host> | nix run nixpkgs#ssh-to-age`, add to `.sops.yaml`, run `sops updatekeys secrets/secrets.yaml`.

## Conventions

- One concern per module file; let `import-tree` pick it up rather than editing import lists.
- `nixos-unstable`; `system.stateVersion = "25.11"`.
- `flakePath` / deploy path is `/mnt/raidDrive/${username}/luna-config`.
