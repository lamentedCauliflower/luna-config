"""Merge declarative non-Steam shortcuts into every Steam account's
shortcuts.vdf, preserving any manually-added entries. Shortcuts carrying
a CompatTool also get a CompatToolMapping entry upserted into the Steam
root's config.vdf, forcing that compatibility tool (Proton) for the tile
(see docs/adr/0004).

argv[1] is a JSON file: a list of
{ AppName, Exe, StartDir, icon, LaunchOptions?, AllowOverlay?, CompatTool? }
objects.
Run before Steam starts (Steam rewrites these files from memory on exit).
"""
import json
import os
import sys
import zlib

import vdf


def steam_appid_unsigned(exe, appname):
    # The id Steam derives for a non-Steam shortcut: it keys the shortcut's
    # compatdata prefix dir and its CompatToolMapping entry.
    return (zlib.crc32((exe + appname).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF


def steam_appid(exe, appname):
    # shortcuts.vdf stores the same id as a signed 32-bit int. Stable so
    # re-runs are idempotent and grid art sticks.
    top = steam_appid_unsigned(exe, appname)
    if top >= 0x80000000:
        top -= 0x100000000
    return top


def load_shortcuts(path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        with open(path, "rb") as fh:
            return vdf.binary_load(fh).get("shortcuts", {})
    return {}


def make_entry(desired):
    exe = '"' + desired["Exe"] + '"'
    start = '"' + desired["StartDir"] + '"'
    return {
        "appid": steam_appid(exe, desired["AppName"]),
        "AppName": desired["AppName"],
        "Exe": exe,
        "StartDir": start,
        "icon": desired.get("icon", ""),
        "ShortcutPath": "",
        "LaunchOptions": desired.get("LaunchOptions", ""),
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": desired.get("AllowOverlay", 1),
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "tags": {},
    }


def upsert(shortcuts, desired_list):
    # Keep all existing entries; upsert ours keyed by AppName.
    entries = list(shortcuts.values())
    for desired in desired_list:
        fresh = make_entry(desired)
        for i, entry in enumerate(entries):
            if entry.get("AppName") == desired["AppName"]:
                entry.update(fresh)
                entries[i] = entry
                break
        else:
            entries.append(fresh)
    return {str(i): entry for i, entry in enumerate(entries)}


def write_shortcuts(path, shortcuts):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        vdf.binary_dump({"shortcuts": shortcuts}, fh)


def child_key(node, name):
    # config.vdf key casing varies between installs ("Valve" vs "valve"),
    # so resolve each level case-insensitively before creating it.
    for k in node:
        if k.lower() == name.lower():
            return k
    return name


def upsert_compat_mappings(root, desired_list):
    # Force a compat tool (Proton) for shortcuts that declare CompatTool, via
    # InstallConfigStore > Software > Valve > Steam > CompatToolMapping in the
    # root's config.vdf — keyed by the same appid as the shortcut. config.vdf
    # is text VDF (shortcuts.vdf is binary). Like shortcuts.vdf it is
    # rewritten from memory when Steam exits, hence the run-before-Steam rule.
    wanted = {}
    for desired in desired_list:
        tool = desired.get("CompatTool")
        if not tool:
            continue
        exe = '"' + desired["Exe"] + '"'
        appid = steam_appid_unsigned(exe, desired["AppName"])
        wanted[str(appid)] = {"name": tool, "config": "", "priority": "250"}
    if not wanted:
        return

    path = os.path.join(root, "config", "config.vdf")
    if not os.path.exists(path):
        # No config.vdf means Steam has never initialised this root; nothing
        # to merge into, and inventing one could confuse Steam's first run.
        # The next boot after Steam has run will pick the mapping up.
        print("skipped (no config.vdf yet) " + path)
        return

    with open(path, encoding="utf-8") as fh:
        data = vdf.load(fh)
    node = data
    for name in ("InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"):
        key = child_key(node, name)
        node = node.setdefault(key, {})

    if all(node.get(appid) == entry for appid, entry in wanted.items()):
        return
    node.update(wanted)
    with open(path, "w", encoding="utf-8") as fh:
        vdf.dump(data, fh, pretty=True)
    print("updated " + path)


def main():
    with open(sys.argv[1]) as fh:
        desired_list = json.load(fh)

    home = os.path.expanduser("~")
    roots = [
        os.path.join(home, ".local/share/Steam"),
        os.path.join(home, ".steam/steam"),
    ]
    seen = set()
    seen_roots = set()
    for root in roots:
        userdata = os.path.join(root, "userdata")
        if not os.path.isdir(userdata):
            continue
        for account in os.listdir(userdata):
            if account in ("0", "anonymous"):
                continue
            path = os.path.realpath(
                os.path.join(userdata, account, "config", "shortcuts.vdf")
            )
            if path in seen:
                continue
            seen.add(path)
            write_shortcuts(path, upsert(load_shortcuts(path), desired_list))
            print("updated " + path)

        # ~/.steam/steam usually symlinks to ~/.local/share/Steam — dedupe.
        real_root = os.path.realpath(root)
        if real_root in seen_roots:
            continue
        seen_roots.add(real_root)
        upsert_compat_mappings(real_root, desired_list)


if __name__ == "__main__":
    main()
