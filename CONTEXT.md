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

**Proton Tile**:
A Game Mode Tile whose program is a Windows exe, launched through Steam's Proton via a declarative CompatToolMapping entry in config.vdf (see docs/adr/0004). Its wine prefix — and so its saves — lives in Steam's compatdata keyed by the tile's appid, which is derived from the tile's Exe path and name; both must stay stable or the prefix is orphaned.
_Avoid_: "wine game", "lutris/bottles game" — Proton Tiles run through Steam's own compat layer, no separate wine install exists.

**Default Browser**:
The browser that owns the system's html/http(s) handlers and the `DEFAULT_BROWSER` session variable. Chromium (ungoogled) is the Default Browser on every host; librewolf is installed alongside but never claims these handlers.
_Avoid_: assuming the browser a user launches most is the Default Browser — default is specifically the mime/scheme handler owner.

**Printing**:
Paper printing through CUPS, defined by `nixosModules.printing`. Unqualified "printing" in a NixOS module context always means this.
_Avoid_: using it for slicing/3D work — that is **3D Printing**, a separate home module.

**3D Printing**:
The slicer and 2D-art toolchain (orca-slicer, inkscape, gimp) in `homeModules.threeDPrinting`. Fleet-wide, since it rides `isaacConfiguration`. Shares no code, host set or vocabulary with **Printing**.
_Avoid_: "printing" unqualified.

**Driverless**:
A printer or scanner driven purely by its advertised IPP Everywhere/AirPrint (printing) or eSCL/AirScan (scanning) capabilities — no PPD, no vendor backend, no `hplip`. The OfficeJet Pro 7740 is Driverless on both halves; see docs/adr/0005.
_Avoid_: calling a queue Driverless because it needed no manual setup — the test is that no driver package is installed, not that discovery was automatic.

**Discovered Queue**:
A CUPS print queue cupsd materialises on demand from DNS-SD, as opposed to one declared by `hardware.printers.ensurePrinters`. Its name is generated and may vary, so nothing may hardcode it.
_Avoid_: assuming a queue name is stable enough for `lp -d`.

**XR Runtime**:
The process that owns the headset — drives its panel, tracks poses, composites submitted frames. Exactly one is active per host, selected by `/etc/xdg/openxr/1/active_runtime.json`. cleoDesktop's is Monado; SteamVR is still installed in the Steam library but no longer drives anything.
_Avoid_: treating "SteamVR is installed" as "SteamVR is the runtime" — installation and activation are unrelated here.

**OpenComposite**:
A reimplementation of `openvr_api` that translates OpenVR calls to OpenXR, so a Steam VR game written against OpenVR can run on Monado. Selected by the `runtime` entry of `~/.config/openvr/openvrpaths.vrpath`, not by anything inside the game.
_Avoid_: calling it a compatibility layer for Windows titles — it is orthogonal to Proton and sits on the API boundary, not the OS boundary.

**Async Reprojection**:
The **XR Runtime**'s compositor re-warping the last rendered frame to the current head pose when the scene app misses its 90Hz deadline. Needs `CAP_SYS_NICE` on the compositor, which is why the runtime choice changes how it is granted: Monado gets it declaratively via `security.wrappers`, whereas SteamVR's compositor is a mutable file in the Steam library and needed a setcap re-applied on every update.
_Avoid_: reading `0 reprojected` in a compositor log as healthy — it means the feature is off, not that no frame needed it.

## Relationships

- The **Hermes VM** runs the Hermes Agent gateway on port 5678.
- lunaServer reverse-proxies `hermes.luna.local` to the **Hermes VM**.
- mewoSteamdeck boots into **Gaming Mode**; **Desktop Mode** is only reachable from inside it.
- chromium and librewolf are each surfaced as a **Non-Steam Shortcut** on every Steam host (mewoSteamdeck, cleoDesktop, yuroLaptop).
- each installed emulator surfaces its own **Game Mode Tile**; a host without the emulator gets no tile.
- chromium is the **Default Browser**; librewolf mirrors chromium's config (extensions, 4get search, stylix theme) but does not take default handlers.
- Voices of the Void is a **Proton Tile** on cleoDesktop only.
- cleoDesktop is the only VR host (the HTC Vive and its base stations are wired to it). Its **XR Runtime** is Monado, via `nixosModules.monado`.
- `nixosModules.monado` and `nixosModules.steamVr` are mutually exclusive: both declare `/etc/xdg/openxr/1/active_runtime.json`, so importing both is an eval conflict rather than a silently wrong runtime. Switching runtime is one line in a host's `imports`. Either layers on `nixosModules.steam` and never replaces it.
- Monado reaches the Vive's lighthouse tracking through libsurvive, which `pkgs.monado` is built against. This is the tradeoff of the switch: SteamVR's lighthouse driver is more robust on this exact hardware.
- **OpenComposite** is what lets OpenVR-era Steam VR titles run on Monado; without it they find no runtime at all.
- The HMD's DP output is left out of the Hyprland monitor rules on purpose — Hyprland excludes non-desktop displays so the **XR Runtime** can take the panel directly.
- **Printing** and scanning are enabled on cleoDesktop and yuroLaptop only; lunaServer is headless and mewoSteamdeck is opt-in.
- the HP OfficeJet Pro 7740 is reached as a **Discovered Queue**; no host declares it by address.
- `nssmdns4` is deliberately off wherever **Printing** is enabled, so `.local` names keep resolving through pihole (docs/adr/0005).

## Example Dialogue

> **Dev:** "Should the Hermes Agent run in a container or the Hermes VM?"
> **Domain expert:** "Use the Hermes VM because it needs systemd, hard memory limits, snapshots, and its own LAN IP."

## Flagged Ambiguities

- "microvm" originally referred to a small Debian VM, but the chosen implementation is a libvirt/qemu Debian VM named **Hermes VM**.
- "hernes-vm" was used once as a typo; the canonical component name is **Hermes VM** and the implementation name is `hermes-vm`.
- "LTS" was used while discussing the guest OS; resolved to Debian stable, not Ubuntu LTS.
