# Secrets Migration: plaintext `secrets.nix` → sops-nix

> **Status**: migration complete. History re-initialised 2026-07-07 and
> published to github.com/lamentedCauliflower/luna-config (public).
> Remaining loose ends:
> - delete the old `luna-config` repo on gitea.luna.local (server still
>   holds the plaintext history until then)
> - lunaserver: re-clone (from GitHub or recreated gitea) + `nh os switch`
> - yurolaptop postponed: still on pre-sops config; add its recipient +
>   `sops updatekeys` + re-clone before rebuilding it
> - optional: `nix-collect-garbage -d` per host; delete
>   `~/luna-config-git-backup-20260707.tgz` when confident

Big-bang, single-day migration. Values are **kept byte-identical** (no rotation — see ADR 0002), so every service must see exactly the credential it sees today. History is destroyed at the end; nothing here changes any service-side password.

Hosts: `cleodesktop`, `lunaserver`, `yurolaptop` — all three are recipients.

## 0. Prep (before the day)

- [ ] Add flake input:
  ```nix
  sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```
- [ ] Gather age recipients (pubkeys only, safe to handle anywhere):
  ```sh
  # per host (run on each, or ssh-keyscan <host>):
  nix run nixpkgs#ssh-to-age -- < /etc/ssh/ssh_host_ed25519_key.pub
  # admin key:
  nix run nixpkgs#ssh-to-age -- < modules/features/ssh/isaac_ed25519.pub
  ```
- [ ] Write `.sops.yaml` at repo root: one creation rule, `path_regex: secrets/.*`, all four recipients.
- [ ] Create `secrets/secrets.yaml` with `nix run nixpkgs#sops -- secrets/secrets.yaml`. sops picks up `~/.ssh/id_ed25519` automatically (passphrase prompt). Copy every value **byte-identical** from `modules/secrets.nix`, plus the three stragglers:
  - `frigateMqttPassword` (currently inline in `frigate.nix`)
  - `litellmUiPassword` (currently `admin` in `litellm.nix`)
  - `giteaDbPassword` (currently `gitea` in `gittea.nix`)
  Keep camelCase key names matching today's attr names; `screenscraper.username/password` may stay nested.
- [ ] Capture ground truth on lunaserver for the quoting hazard (romm compose uses `- KEY="${val}"` — the quotes may be part of the live value):
  ```sh
  for c in pihole litellm frigate romm romm-db; do docker exec $c env | sort > /root/pre-sops-$c.env; done
  # plus one arr container, e.g. sonarr
  ```
  After migration the same command must diff clean (minus PATH/HOSTNAME noise).
- [ ] Backup old history offline (rollback diff for the day; delete once verified):
  ```sh
  tar -C /mnt/isaac -czf ~/luna-config-git-backup.tgz luna-config/.git
  ```
- [ ] Bcrypt-hash the **current** syncthing password: `nix run nixpkgs#mkpasswd -- -m bcrypt`.

## 1. Base module

New `self.nixosModules.sopsBase`, imported by all three host configurations:

```nix
imports = [ inputs.sops-nix.nixosModules.sops ];
sops.defaultSopsFile = ../../secrets/secrets.yaml;
# sops-nix defaults age.sshKeyPaths to the openssh ed25519 host key — all hosts run sshServer, so no key config needed.
```

## 2. Per-module rewiring (one branch, no deploys yet)

Docker pattern everywhere: module declares its `sops.secrets.*` + a `sops.templates."<svc>.env"` whose content is `KEY=${config.sops.placeholder.<name>}` lines; compose service gains `env_file: [ <template>.path ]`; secret lines leave the compose text; template gets `restartUnits = [ "<svc>.service" ]` (fixes today's gap where a secret change wouldn't restart anything).

- [ ] **pihole** — `FTLCONF_webserver_api_password` → env-file.
- [ ] **litellm** — `LITELLM_MASTER_KEY`, `UI_USERNAME`, `UI_PASSWORD` → env-file.
- [ ] **frigate** — `FRIGATE_RTSP_PASSWORD` and new `FRIGATE_MQTT_PASSWORD` → env-file; `config.yaml` mqtt password becomes `{FRIGATE_MQTT_PASSWORD}` (frigate substitutes any `FRIGATE_*` env var in its config).
- [x] **romm** — implemented via `docker compose --env-file` **interpolation** instead of `env_file:`: the compose text keeps its original quoted `- KEY="${VAR}"` entries, so container env stays byte-identical to the pre-sops deployment regardless of compose quote semantics (the mariadb volume was initialised with those exact bytes). Still verify against the captured `docker exec romm-db env`.
- [ ] **arrStack** — one env-file with `USER`, `PASS`, `PROWLARR__AUTH__APIKEY`, `SONARR__AUTH__APIKEY`, `RADARR__AUTH__APIKEY`, `LIDARR__AUTH__APIKEY`; attach per service. `PUID`/`PGID` stay inline.
- [ ] **gitea** — `GITEA__database__PASSWD`, `POSTGRES_PASSWORD` → env-file (value stays `gitea`; changing it would require a postgres-side change we're not doing).
- [ ] **samba** — activation script reads `$(cat ${config.sops.secrets.sambaPassword.path})`; add `deps = [ "setupSecrets" ]` so sops runs first.
- [ ] **anki-server** — switch user entry to `passwordFile = config.sops.secrets.ankiSyncServerPassword.path` (verify the nixpkgs option name at implementation; fall back to an env-file if absent).
- [ ] **syncthing** — `settings.gui.password = "<bcrypt hash>"` committed literal; secret entry not needed in sops.
- [ ] **isaacHomeManager** (`modules/home/users/isaac/default.nix`, already the nixos-side shim) — declare `sops.secrets.ankiSyncKey { owner = "isaac"; }` and `sops.templates."task-sync.rc" { owner = "isaac"; }` containing the three `sync.server.*` lines.
- [ ] **anki-client (hm)** — `keyFile = "/run/secrets/ankiSyncKey"`; delete the `home.file` that wrote the key into the store.
- [ ] **taskwarrior (hm)** — taskrc drops the `sync.server.*` lines, gains `include /run/secrets/rendered/task-sync.rc`.
- [ ] Delete `modules/secrets.nix`.
- [ ] Rewrite the Secrets section of `AGENTS.md` (it documents the plaintext scheme).

## 3. Deploy + verify (same day)

- [ ] **cleodesktop** first (this machine: fastest feedback, exercises hm path): rebuild; verify anki sync, `task sync`, syncthing GUI login with old password.
- [ ] **lunaserver**: rebuild; `docker exec … env` diff vs pre-sops captures; log into pihole/litellm/romm/arr UIs; `smbclient -U isaac` auth; anki client sync end-to-end.
- [ ] **yurolaptop**: was offline during migration — first `ssh-keyscan -t ed25519 <ip> | nix run nixpkgs#ssh-to-age`, add recipient to `.sops.yaml`, `nix run nixpkgs#sops -- updatekeys secrets/secrets.yaml`; then rebuild; verify anki, task, syncthing.
- [ ] Plaintext sweep of the working tree — every old literal value must return zero hits:
  ```sh
  grep -rF "<each value>" . --exclude-dir=.git
  ```

## 4. History destruction + re-init (only after §3 green)

- [ ] Confirm `secrets/secrets.yaml` shows only `ENC[...]` blobs; `.sops.yaml` holds pubkeys only.
- [ ] `rm -rf .git && git init && git add -A && git commit`.
- [ ] Delete the `luna-config` repo on gitea entirely (server retains old history otherwise); create fresh repo, push.
- [ ] Re-clone / hard-reset the other checkouts — `autoUpdate` paths on lunaserver (`/mnt/raidDrive/isaac/luna-config`) and yurolaptop hold the old history.
- [ ] Optional hygiene: `nix-collect-garbage -d` per host to purge old plaintext store paths.
- [ ] Delete `~/luna-config-git-backup.tgz` once confident.
- [ ] GitHub publish when ready — repo is now safe by construction.

## Open items (out of scope today)

- Which remote hosts pull from after GitHub exists (gitea vs github) — affects `autoUpdate`.
- LiteLLM UI: consider disabling instead of secreting if unused.
- New-host bootstrap procedure: install → grab host pubkey → `ssh-to-age` → add recipient to `.sops.yaml` → `sops updatekeys secrets/secrets.yaml`.
