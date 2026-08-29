#!/usr/bin/env python3
"""Regenerates GameTDB-based boxart maps (PS3, Wii U) in the app's generic
boxarts JSON-map format: [{name, image}]. No accounts/API keys.

Sources: gametdb.com <sys>tdb.txt (serial = name), covers served from
art.gametdb.com/<sys>/cover/<REGION>/<serial>.jpg. The region directory is
derived from the serial's region letter; when several serials share a name,
US > EN > JA wins.
"""
import json
import urllib.request

SYSTEMS = {
    # system: (tdb name, region-letter index in serial, cover extension, output file)
    "ps3": ("ps3tdb", 2, "jpg", "assets/boxarts/playstation_3.json"),
    "wiiu": ("wiiutdb", 3, "jpg", "assets/boxarts/wii_u.json"),
    "wii": ("wiitdb", 3, "png", "assets/boxarts/wii.json"),  # wii covers are png
}
REGION_DIR = {"U": "US", "E": None, "P": "EN", "J": "JA", "K": "KO", "A": "ZH", "W": "ZH"}
REGION_PRIORITY = {"US": 0, "EN": 1, "JA": 2, "KO": 3, "ZH": 4}


def region_for(system, serial, idx):
    letter = serial[idx] if len(serial) > idx else ""
    if system == "ps3":
        # PS3: U=US, E=Europe(EN), J=JA, K=KO, A=Asia(ZH)
        return {"U": "US", "E": "EN", "J": "JA", "K": "KO", "A": "ZH"}.get(letter)
    # Nintendo: E=US, P=PAL(EN), J=JA, K=KO, W=ZH
    return {"E": "US", "P": "EN", "J": "JA", "K": "KO", "W": "ZH"}.get(letter)


def main():
    for system, (tdb, idx, ext, out_path) in SYSTEMS.items():
        url = f"https://www.gametdb.com/{tdb}.txt?LANG=EN"
        with urllib.request.urlopen(url, timeout=120) as r:
            lines = r.read().decode("utf-8", "replace").splitlines()
        # Every serial is emitted (id-based matching needs them all); entries are
        # ordered worst-region-first per name so the preferred region is written
        # last and wins the name key in the app's map.
        rows = []
        for line in lines[1:]:
            if " = " not in line:
                continue
            serial, name = line.split(" = ", 1)
            serial, name = serial.strip(), name.strip()
            region = region_for(system, serial, idx)
            if not name or not region:
                continue
            image = f"https://art.gametdb.com/{system}/cover/{region}/{serial}.{ext}"
            rows.append((name.lower(), -REGION_PRIORITY[region], {"name": name, "id": serial, "image": image}))
        out = [e for _, _, e in sorted(rows, key=lambda x: (x[0], x[1]))]
        with open(out_path, "w") as fh:
            json.dump(out, fh, indent=0)
        print(f"{system}: {len(out)} entries -> {out_path}")


if __name__ == "__main__":
    main()
