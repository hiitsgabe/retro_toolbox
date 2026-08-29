#!/usr/bin/env python3
"""Regenerates assets/boxarts/xbox_360.json.

Joins two public XboxUnity dumps (no accounts/API keys):
- names:  github.com/UncreativeXenon/XboxUnity-Scraper metadata.json (TitleID -> Name)
- covers: archive.org/details/xboxunity-covers-fulldump_202311 file index
          (TitleID -> <coverid>/front.png, ~440x600)

Output shape is the app's generic boxarts JSON-map format: [{name, image}].
"""
import json
import re
import urllib.request

NAMES_URL = "https://raw.githubusercontent.com/UncreativeXenon/XboxUnity-Scraper/master/metadata.json"
COVERS_META_URL = "https://archive.org/metadata/xboxunity-covers-fulldump_202311"
COVERS_BASE = "https://archive.org/download/xboxunity-covers-fulldump_202311/"
OUT = "assets/boxarts/xbox_360.json"


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return json.load(r)


def main():
    names = {i["TitleID"]: i["Name"] for i in fetch_json(NAMES_URL)["Items"] if i.get("Name") and i.get("TitleID")}
    best = {}  # tid -> (coverid, path); lowest coverid = original upload
    for f in fetch_json(COVERS_META_URL).get("files", []):
        m = re.match(r"xboxunity-covers-fulldump/([0-9A-F]{8})/(\d+)/front\.png$", f["name"])
        if m and (m.group(1) not in best or int(m.group(2)) < best[m.group(1)][0]):
            best[m.group(1)] = (int(m.group(2)), f["name"])
    out = [{"name": names[t], "image": COVERS_BASE + p} for t, (_, p) in sorted(best.items()) if t in names]
    with open(OUT, "w") as fh:
        json.dump(out, fh, indent=0)
    print(f"{len(out)} entries -> {OUT}")


if __name__ == "__main__":
    main()
