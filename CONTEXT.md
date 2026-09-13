# Luna Config

NixOS flake configuration for lunaServer and related host services.

## Language

**Hermes Stack**:
The docker compose stack on lunaServer that runs the Hermes Agent, from the upstream `nousresearch/hermes-agent` image. Exactly one container, holding every **Hermes Profile**; all mutable state is the single host directory bind-mounted at `/opt/data`.
_Avoid_: "the hermes container**s**" — the plural is the shape this deliberately does not have; also microvm, hernes-vm.

**Hermes Profile**:
One independently-configured agent inside the **Hermes Stack** — its own config, sessions, memories, skills and optionally its own OpenAI-compatible API port, supervised as its own s6 service slot. A profile is created by `hermes profile create` at runtime, never by adding a container. `default` is the profile Hermes ships with.
_Avoid_: treating a profile as a deployment unit; two gateway processes sharing a data dir corrupt it, which is exactly what "a container per profile" would do.

**Hermes VM**:
The retired Debian virtual machine on lunaServer that used to run the Hermes Agent gateway. Deprecated by docs/adr/0007; `modules/features/hermes-vm.nix` still exists but no host imports it, and it survives only until its qcow2 is drained.
_Avoid_: using it for the current deployment — that is the **Hermes Stack**; also microvm, hernes-vm.

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
A reimplementation of `openvr_api` that translates OpenVR calls to OpenXR, so a Steam VR game written against OpenVR can run on Monado. Selected by the `runtime` entry of `~/.config/openvr/openvrpaths.vrpath`, not by anything inside the game. Covers scene apps only: an OpenVR *overlay* app aborts with `unsupported apptype 2`, so overlays must talk OpenXR directly.
_Avoid_: calling it a compatibility layer for Windows titles — it is orthogonal to Proton and sits on the API boundary, not the OS boundary.

**Async Reprojection**:
The **XR Runtime**'s compositor re-warping the last rendered frame to the current head pose when the scene app misses its 90Hz deadline. Needs `CAP_SYS_NICE` on the compositor, which is why the runtime choice changes how it is granted: Monado gets it declaratively via `security.wrappers`, whereas SteamVR's compositor is a mutable file in the Steam library and needed a setcap re-applied on every update.
_Avoid_: reading `0 reprojected` in a compositor log as healthy — it means the feature is off, not that no frame needed it.

**Stream Session**:
The `streamer` user's headless Plasma session on cleoDesktop, started at boot by lingering with nobody logged in, that Sunshine captures and streams to Moonlight. Distinct from every session a human uses: it holds no seat, no VT and no connector, and its Steam library and Steam login are its own.
_Avoid_: calling it a "remote desktop" (nothing is being mirrored — the session exists only to be streamed), or conflating it with **Desktop Mode**, which is mewoSteamdeck's GNOME session.

**Virtual Output**:
The framebuffer `kwin_wayland --virtual` renders into, fixed at 1920x1080 when the compositor starts. It is not a display: no DRM device, no CRTC, no EDID, nothing a monitor could ever show. Its geometry cannot change without restarting the compositor, and Sunshine's `output_name` is global, so there is exactly one per **Stream Session**.
_Avoid_: "dummy plug", "fake monitor", "headless display" — all three imply a connector that this deliberately does not use.

## Relationships

- The **Hermes Stack** runs every **Hermes Profile** in one container; its dashboard on 9119 fronts all of them at once, and each profile's API server gets its own port.
- lunaServer reverse-proxies `hermes.luna.local` to the **Hermes Stack**'s dashboard. Every published port binds `127.0.0.1`, so caddy is the only way in and an API server with no `API_SERVER_KEY` is not LAN-reachable.
- The **Hermes Stack**'s API keys live in its data dir's `.env`, not in `secrets/secrets.yaml` — the one service credential on lunaServer that is not a **Secret** in the sops sense (docs/adr/0007).
- `nixosModules.hermesVm` and `nixosModules.hermesContainer` are mutually exclusive: both declare the `hermes.luna.local` caddy vhost, so importing both is an eval conflict rather than a silently wrong backend.
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
- cleoDesktop runs a **Stream Session** for game streaming; Sunshine captures its **Virtual Output** through KDE screencasting and Moonlight on mewoSteamdeck consumes it.
- the **Stream Session** cannot capture a GNOME session: Sunshine has no xdg-desktop-portal backend, which is the whole reason it is Plasma (docs/adr/0006).
- `nixosModules.gameStreaming` forces `services.displayManager.defaultSession = "hyprland"`, because enabling Plasma would otherwise move ly's default login session away from Hyprland.
- mewoSteamdeck is the streaming client: `nixosModules.moonlight` installs Moonlight and surfaces it as a **Game Mode Tile**, so the **Stream Session** on cleoDesktop is reachable from Gaming Mode without entering **Desktop Mode**.
- the **Stream Session** runs as `streamer`, never as isaac, because Steam is single-instance per user and would otherwise capture a `steam` launched at the desk.
- `steamShortcuts` is bound to isaac, so the **Stream Session** has no **Non-Steam Shortcuts** and no **Proton Tiles**.

## Example Dialogue

> **Dev:** "I need a second agent with its own config. Do I add a second Hermes container?"
> **Domain expert:** "No — add a **Hermes Profile**. The stack is one container on purpose; two gateways on one data dir shred the sessions. Give it a port in the module's `profiles` attrset and the s6 slot is created for you."

## Flagged Ambiguities

- "microvm" originally referred to a small Debian VM; that became the libvirt/qemu **Hermes VM**, which is now retired in favour of the **Hermes Stack**.
- "hernes-vm" was used once as a typo; the canonical retired component is **Hermes VM**, implementation name `hermes-vm`.
- "LTS" was used while discussing the guest OS; resolved to Debian stable, not Ubuntu LTS. Moot since docs/adr/0007 — the image is `debian:13.4`-based, so the guest OS is the same either way.
- "profile" is overloaded across this repo's tooling; in any Hermes context it means a **Hermes Profile** and never a shell, browser or nix profile.
