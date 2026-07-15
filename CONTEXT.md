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
A key that can unlock the encrypted secrets. Recipients are each host's Host Key plus the Admin Key.

**Host Key**:
A host's pre-existing SSH ed25519 identity (`/etc/ssh/ssh_host_ed25519_key`). Each host unlocks secrets with its own Host Key at activation; no extra key material is provisioned.

**Admin Key**:
Isaac's personal SSH ed25519 key (pubkey tracked as `isaac_ed25519.pub`). The only key used by a human to edit secrets.

**Gaming Mode**:
The gamescope Steam Deck UI session that mewoSteamdeck boots straight into, with no display manager or login screen.
_Avoid_: big picture, gamescopeSession (the vanilla nixpkgs option — mewoSteamdeck uses Jovian's session instead)

**Desktop Mode**:
The GNOME session reached via "Switch to Desktop" in the Steam menu on mewoSteamdeck; logging out returns to Gaming Mode.
_Avoid_: desktop environment session, KDE mode

**Non-Steam Shortcut**:
An entry in a Steam account's `shortcuts.vdf` that launches an arbitrary local program (browsers, Jellyfin, emulators) from the Steam library, including from Gaming Mode. Each entry belongs to one Steam account under `userdata/<accountID>/`; the account ID only exists after that account has logged into Steam once. Each shortcut is declared by the module that owns the program it launches: universal shortcuts (browsers, Jellyfin) by the steamShortcuts module itself, an emulator's shortcut by that emulator's module.
_Avoid_: "non-steam game", conflating with an installed Steam app.

**Game Mode Tile**:
A Non-Steam Shortcut as it appears in Gaming Mode's library grid. A tile exists only where its program is installed — an emulator's tile can never appear on a host without that emulator.
_Avoid_: treating the tile as a separate thing from its Non-Steam Shortcut (one entry, two surfaces).

**Default Browser**:
The browser that owns the system's html/http(s) handlers and the `DEFAULT_BROWSER` session variable. Chromium (ungoogled) is the Default Browser on every host; librewolf is installed alongside but never claims these handlers.
_Avoid_: assuming the browser a user launches most is the Default Browser — default is specifically the mime/scheme handler owner.

## Relationships

- The **Hermes VM** runs the Hermes Agent gateway on port 5678.
- lunaServer reverse-proxies `hermes.luna.local` to the **Hermes VM**.
- mewoSteamdeck boots into **Gaming Mode**; **Desktop Mode** is only reachable from inside it.
- chromium and librewolf are each surfaced as a **Non-Steam Shortcut** on every Steam host (mewoSteamdeck, cleoDesktop, yuroLaptop).
- each installed emulator surfaces its own **Game Mode Tile**; a host without the emulator gets no tile.
- chromium is the **Default Browser**; librewolf mirrors chromium's config (extensions, 4get search, stylix theme) but does not take default handlers.

## Example Dialogue

> **Dev:** "Should the Hermes Agent run in a container or the Hermes VM?"
> **Domain expert:** "Use the Hermes VM because it needs systemd, hard memory limits, snapshots, and its own LAN IP."

## Flagged Ambiguities

- "microvm" originally referred to a small Debian VM, but the chosen implementation is a libvirt/qemu Debian VM named **Hermes VM**.
- "hernes-vm" was used once as a typo; the canonical component name is **Hermes VM** and the implementation name is `hermes-vm`.
- "LTS" was used while discussing the guest OS; resolved to Debian stable, not Ubuntu LTS.
