# Luna Config

NixOS flake configuration for lunaServer and related host services.

## Language

**Hermes VM**:
A Debian virtual machine on lunaServer dedicated to running the Hermes Agent gateway.
_Avoid_: microvm, hernes-vm

**Secret**:
A credential (password, API key, sync key) that must never appear in the git repo unencrypted nor in any host's world-readable nix store.
_Avoid_: calling nix-store-visible values "secrets" — once interpolated into a built config they are public to every local user.

**Recipient**:
A key that can unlock the encrypted secrets. Recipients are the three Host Keys plus the Admin Key.

**Host Key**:
A host's pre-existing SSH ed25519 identity (`/etc/ssh/ssh_host_ed25519_key`). Each host unlocks secrets with its own Host Key at activation; no extra key material is provisioned.

**Admin Key**:
Isaac's personal SSH ed25519 key (pubkey tracked as `isaac_ed25519.pub`). The only key used by a human to edit secrets.

## Relationships

- The **Hermes VM** runs the Hermes Agent gateway on port 5678.
- lunaServer reverse-proxies `hermes.luna.local` to the **Hermes VM**.

## Example Dialogue

> **Dev:** "Should the Hermes Agent run in a container or the Hermes VM?"
> **Domain expert:** "Use the Hermes VM because it needs systemd, hard memory limits, snapshots, and its own LAN IP."

## Flagged Ambiguities

- "microvm" originally referred to a small Debian VM, but the chosen implementation is a libvirt/qemu Debian VM named **Hermes VM**.
- "hernes-vm" was used once as a typo; the canonical component name is **Hermes VM** and the implementation name is `hermes-vm`.
- "LTS" was used while discussing the guest OS; resolved to Debian stable, not Ubuntu LTS.
