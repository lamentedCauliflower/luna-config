#!/usr/bin/env -S nix shell nixpkgs#jq --command bash
# Re-pins every Chrome Web Store CRX in chromium-extensions.json to the version
# the store serves right now. The store only ever serves the latest CRX, so a
# pin breaks on any fresh fetch once upstream ships; run this after every
# `nix flake update`.
set -euo pipefail
cd "$(dirname "$0")"

# The same prodversion chromium.nix fetches with, so the store answers with the
# same CRX. Its hash_sha256 is the flat file hash fetchurl checks.
chromium=$(nix eval --raw --inputs-from ../../.. nixpkgs#ungoogled-chromium.version)

for id in $(jq -r 'keys[]' chromium-extensions.json); do
  check=$(curl -fsS "https://clients2.google.com/service/update2/crx?response=updatecheck&acceptformat=crx3&prodversion=$chromium&x=id%3D$id%26uc" |
    grep -o '<updatecheck [^>]*>')
  version=$(grep -oP ' version="\K[^"]+' <<<"$check")
  hash=$(nix hash convert --hash-algo sha256 --to sri "$(grep -oP ' hash_sha256="\K[^"]+' <<<"$check")")
  jq --arg id "$id" --arg version "$version" --arg hash "$hash" \
    '.[$id] += {$version, $hash}' chromium-extensions.json >chromium-extensions.json.new
  mv chromium-extensions.json.new chromium-extensions.json
done
