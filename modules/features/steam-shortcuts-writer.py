"""Merge declarative non-Steam shortcuts into every Steam account's
shortcuts.vdf, preserving any manually-added entries.

argv[1] is a JSON file: a list of { AppName, Exe, StartDir, icon } objects.
Run before Steam starts (Steam rewrites this file from memory on exit).
"""
import json
import os
import sys
import zlib

import vdf


def steam_appid(exe, appname):
    # Stable signed 32-bit id so re-runs are idempotent and grid art sticks.
    top = (zlib.crc32((exe + appname).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF
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
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
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


def main():
    with open(sys.argv[1]) as fh:
        desired_list = json.load(fh)

    home = os.path.expanduser("~")
    roots = [
        os.path.join(home, ".local/share/Steam"),
        os.path.join(home, ".steam/steam"),
    ]
    seen = set()
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


if __name__ == "__main__":
    main()
