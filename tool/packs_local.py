#!/usr/bin/env python3
"""Builds metadata packs locally, checks them, and serves them over HTTP.

The app reads the packs from a fixed-tag GitHub release. That URL is
`MetadataPackService.releaseBase`, and a build that defines `PACKS_BASE` reads
from there instead, so a debug build can be pointed at this server:

    python3 tool/packs_local.py snes
    flutter run --dart-define=PACKS_BASE=http://localhost:8787

Nothing here writes to the repository: the output directory is `dist/`, which
is git-ignored, and no release is created or touched.
"""
import argparse
import gzip
import http.server
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

sys.path.insert(0, HERE)
import build_metadata_pack as builder  # noqa: E402

DEFAULT_SYSTEM = ["snes"]


def pack_ids():
    return [builder.normalize(s["system"]) for s in builder.SYSTEMS]


def names_to_ids():
    """Every name that stands for a pack id, including the builder's aliases.

    The aliases are the table the builder already ships and the index already
    publishes, which is where `snes`, `ps1` and `psx` live. None of those three
    appears anywhere inside its normalized id, so matching on the id alone
    rejects exactly the names a person is most likely to type.
    """
    names = {}
    for system in builder.SYSTEMS:
        pack_id = builder.normalize(system["system"])
        names[pack_id] = pack_id
        for alias in system.get("aliases", []):
            names[alias] = pack_id
    return names


def resolve(alias, names):
    """An id, one of the builder's aliases, or a substring of exactly one pack.

    Exact wins over substring so that a name the table defines always means
    what the table says: `xbox` is the original console there, even though it
    is also a substring of `microsoft_xbox_360`. A substring that reaches more
    than one pack is refused rather than resolved to the first hit, because
    building the wrong console only shows after a full download.
    """
    if alias in names:
        return names[alias]
    hits = sorted({pack for name, pack in names.items() if alias in name})
    if len(hits) == 1:
        return hits[0]
    if not hits:
        raise SystemExit(f"no pack matches {alias!r}. Known names:\n  "
                         + "\n  ".join(sorted(names)))
    raise SystemExit(f"{alias!r} is ambiguous, it matches:\n  "
                     + "\n  ".join(hits))


def build(out, built, selected):
    cmd = [sys.executable, os.path.join(HERE, "build_metadata_pack.py"),
           "--out", out, "--built", built]
    for pack_id in selected:
        cmd += ["--only", pack_id]
    print("$ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=ROOT)


def report(out, selected):
    """Reads the output back the way the app would, and prints what is in it.

    Reading through `gzip` and `json` is the point: the builder printing a game
    count proves the builder counted, not that a decodable pack landed on disk.
    """
    index_path = os.path.join(out, "index.json")
    if not os.path.exists(index_path):
        raise SystemExit(f"{index_path} does not exist, the build produced no index")
    with open(index_path, encoding="utf-8") as f:
        index = json.load(f)

    listed = [p["pack"] for p in index["packs"]]
    if sorted(listed) != sorted(selected):
        raise SystemExit(f"index.json lists {listed}, expected {selected}")

    print(f"\nindex.json: {len(listed)} pack(s), built {index['built']}")
    total = 0
    for entry in index["packs"]:
        path = os.path.join(out, f"{entry['pack']}.json.gz")
        if not os.path.exists(path):
            raise SystemExit(f"{entry['pack']} is in the index but {path} is missing")
        with gzip.open(path, "rt", encoding="utf-8") as f:
            pack = json.load(f)
        games = pack["games"]
        # The index carries its own game count. Two numbers from two files that
        # must agree is the cheapest way to catch a half-written pack.
        if entry["games"] != len(games):
            raise SystemExit(f"{entry['pack']}: index says {entry['games']} games, "
                             f"the pack holds {len(games)}")
        total += len(games)
        covers = sum(1 for g in games if g.get("cover"))
        synopses = sum(1 for g in games if g.get("synopsis"))
        size = os.path.getsize(path) / 1024
        unit = "KB" if size < 1024 else "MB"
        if unit == "MB":
            size /= 1024
        print(f"  {entry['pack']:<45} {len(games):>6} games  "
              f"{size:>6.1f} {unit}  {covers} covers  {synopses} synopses")
        for game in games[:3]:
            print(f"      {game['id']:<50} {game['title']}")
    print(f"  {'total':<45} {total:>6} games")


def serve(out, port):
    directory = os.path.abspath(out)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=directory, **kw)

    print(f"\nserving {directory} on http://localhost:{port}")
    print(f"  flutter run --dart-define=PACKS_BASE=http://localhost:{port}")
    print("  ctrl-c to stop")
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("system", nargs="*", default=DEFAULT_SYSTEM,
                        help="pack id, alias, or a substring of one, "
                             f"repeatable (default: {' '.join(DEFAULT_SYSTEM)})")
    parser.add_argument("--all", action="store_true",
                        help="build all 24 packs, slow and a large download")
    parser.add_argument("--out", default="dist/packs", help="output directory")
    parser.add_argument("--built", help="build date, YYYY-MM-DD (default: today, UTC)")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--no-serve", action="store_true",
                        help="build and report, then exit without serving")
    args = parser.parse_args()

    names = names_to_ids()
    selected = (pack_ids() if args.all
                else [resolve(a, names) for a in args.system])

    built = args.built
    if not built:
        import datetime
        built = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

    if not os.environ.get("GITHUB_TOKEN"):
        print("GITHUB_TOKEN is unset: the cover listings are unauthenticated "
              "and GitHub rate-limits them at 60 requests an hour.\n")

    out = os.path.join(ROOT, args.out) if not os.path.isabs(args.out) else args.out
    build(args.out, built, selected)
    report(out, selected)
    if not args.no_serve:
        serve(out, args.port)


if __name__ == "__main__":
    main()
