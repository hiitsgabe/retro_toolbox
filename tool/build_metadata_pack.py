#!/usr/bin/env python3
"""Builds one metadata pack per console for the app's game grid.

Usage:
  python3 tool/build_metadata_pack.py --built YYYY-MM-DD [--out DIR] [--only ID]

Writes <pack>.json.gz per system plus an index.json, meant for a GitHub
release with the tag "packs". Sources: libretro-database, OpenVGDB v29.0,
libretro-thumbnails.
"""
import argparse
import gzip
import io
import json
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile

LIBRETRO_RAW = "https://raw.githubusercontent.com/libretro/libretro-database/master"
THUMBS_API = "https://api.github.com/repos/libretro-thumbnails/{repo}/git/trees/master:{folder}"
THUMBS_RAW = "https://raw.githubusercontent.com/libretro-thumbnails/{repo}/master/{folder}/{name}"

# The three folders every libretro-thumbnails repository publishes under the
# same filenames, mapped to the pack field each one fills. Snaps are in-game
# captures and Titles are title screens; they are listed separately because a
# game can have one without the other.
THUMB_FOLDERS = {
    "cover": "Named_Boxarts",
    "screenshot": "Named_Snaps",
    "titleScreen": "Named_Titles",
}
OPENVGDB_URL = "https://github.com/OpenVGDB/OpenVGDB/releases/download/v29.0/openvgdb.zip"

SIDE_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "releaseyear": "releaseyear",
    "franchise": "franchise",
    "esrb": "esrb_rating",
    "serial": "serial",
}

SYSTEMS = [
    {"system": "Coleco - ColecoVision", "group": "no-intro",
     "thumbs": "Coleco_-_ColecoVision", "aliases": ["colecovision", "coleco"]},
    {"system": "Mattel - Intellivision", "group": "no-intro",
     "thumbs": "Mattel_-_Intellivision", "aliases": ["intellivision"]},
    {"system": "Nintendo - Game Boy", "group": "no-intro",
     "thumbs": "Nintendo_-_Game_Boy", "aliases": ["game_boy", "gb"]},
    {"system": "Nintendo - Game Boy Color", "group": "no-intro",
     "thumbs": "Nintendo_-_Game_Boy_Color", "aliases": ["game_boy_color", "gbc"]},
    {"system": "Nintendo - Game Boy Advance", "group": "no-intro",
     "thumbs": "Nintendo_-_Game_Boy_Advance", "aliases": ["game_boy_advance", "gba"]},
    {"system": "Nintendo - Nintendo DS", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_DS", "aliases": ["nintendo_ds", "nds", "ds"]},
    {"system": "Nintendo - Nintendo 3DS", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_3DS", "aliases": ["nintendo_3ds", "3ds"]},
    {"system": "Nintendo - Nintendo 64", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_64", "aliases": ["nintendo_64", "n64"]},
    {"system": "Nintendo - Nintendo Entertainment System", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_Entertainment_System",
     "aliases": ["nintendo_entertainment_system", "nes", "famicom"]},
    {"system": "Nintendo - Super Nintendo Entertainment System", "group": "no-intro",
     "thumbs": "Nintendo_-_Super_Nintendo_Entertainment_System",
     "aliases": ["super_nintendo", "snes", "super_famicom", "sfc"]},
    {"system": "Nintendo - Wii U (Digital)", "group": "no-intro",
     "thumbs": "Nintendo_-_Wii_U", "aliases": ["nintendo_wii_u", "wii_u", "wiiu"]},
    {"system": "Sega - Game Gear", "group": "no-intro",
     "thumbs": "Sega_-_Game_Gear", "aliases": ["game_gear", "gamegear", "gg"]},
    {"system": "Sega - Mega Drive - Genesis", "group": "no-intro",
     "thumbs": "Sega_-_Mega_Drive_-_Genesis",
     "aliases": ["sega_genesis", "genesis", "mega_drive", "megadrive"]},
    {"system": "Microsoft - Xbox", "group": "redump",
     "thumbs": "Microsoft_-_Xbox", "aliases": ["xbox"]},
    {"system": "Microsoft - Xbox 360", "group": "redump",
     "thumbs": "Microsoft_-_Xbox_360", "aliases": ["xbox_360", "x360"]},
    {"system": "Nintendo - GameCube", "group": "redump",
     "thumbs": "Nintendo_-_GameCube",
     "aliases": ["nintendo_game_cube", "gamecube", "ngc", "gc"]},
    {"system": "Nintendo - Wii", "group": "redump",
     "thumbs": "Nintendo_-_Wii", "aliases": ["nintendo_wii", "wii"]},
    {"system": "Sega - Dreamcast", "group": "redump",
     "thumbs": "Sega_-_Dreamcast", "aliases": ["sega_dreamcast", "dreamcast", "dc"]},
    {"system": "Sega - Saturn", "group": "redump",
     "thumbs": "Sega_-_Saturn", "aliases": ["sega_saturn", "saturn"]},
    {"system": "Sony - PlayStation", "group": "redump",
     "thumbs": "Sony_-_PlayStation",
     "aliases": ["playstation_1", "playstation", "ps1", "psx"]},
    {"system": "Sony - PlayStation 2", "group": "redump",
     "thumbs": "Sony_-_PlayStation_2", "aliases": ["playstation_2", "ps2"]},
    {"system": "Sony - PlayStation 3", "group": "redump",
     "thumbs": "Sony_-_PlayStation_3", "aliases": ["playstation_3", "ps3"]},
    {"system": "Sony - PlayStation Portable", "group": "redump",
     "thumbs": "Sony_-_PlayStation_Portable", "aliases": ["playstation_portable", "psp"]},
    {"system": "The 3DO Company - 3DO", "group": "redump",
     "thumbs": "The_3DO_Company_-_3DO", "aliases": ["panasonic_3do", "3do"]},
]

GAME_RE = re.compile(r"game \(\s*(.*?)\n\)", re.S)
NAME_RE = re.compile(r'^\s*name "([^"]+)"', re.M)
SERIAL_RE = re.compile(r'^\s*serial "([^"]+)"', re.M)
REGION_RE = re.compile(r'^\s*region "([^"]+)"', re.M)
# md5 is captured only so the sha1 group lands in the right position; it is
# discarded.
ROM_RE = re.compile(
    r'rom \( name "([^"]+)"(?:\s+size \d+)?\s+crc (\w+)'
    r"(?:\s+md5 (\w+))?(?:\s+sha1 (\w+))?"
)
CRC_RE = re.compile(r"crc (\w+)")


def normalize(value):
    """Same rule as CatalogService._nameToId in the app."""
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9]+", "_", value.lower()))


def parse_dat(text):
    """Parses a No-Intro or Redump main DAT into a list of dumps.

    Only the first rom line of each block is kept; crc and sha1 are uppercased.
    """
    entries = []
    for block in GAME_RE.findall(text):
        name = NAME_RE.search(block)
        if not name:
            continue
        rom = ROM_RE.search(block)
        serial = SERIAL_RE.search(block)
        region = REGION_RE.search(block)
        entries.append({
            "name": name.group(1),
            "crc": rom.group(2).upper() if rom else None,
            "sha1": rom.group(4).upper() if rom and rom.group(4) else None,
            "serial": serial.group(1) if serial else None,
            "region": region.group(1) if region else None,
        })
    return entries


def parse_side_dat(text, field):
    """Parses a per-field side file into an uppercase-CRC32 to value map."""
    field_re = re.compile(field + r' "([^"]+)"')
    out = {}
    for block in GAME_RE.findall(text):
        crc = CRC_RE.search(block)
        value = field_re.search(block)
        if crc and value:
            out[crc.group(1).upper()] = value.group(1)
    return out


ROM_EXTS = (".zip", ".7z", ".sfc", ".smc", ".fig", ".swc", ".bin", ".rar", ".gz",
            ".nes", ".gb", ".gbc", ".gba", ".nds", ".3ds", ".n64", ".z64", ".v64",
            ".md", ".gen", ".gg", ".iso", ".cue", ".chd", ".col", ".int")
ARTICLE_RE = re.compile(
    r"^(.*?), (the|a|an|le|la|les|el|los|das|der|die)$", re.I)
TAG_RE = re.compile(r"\([^)]*\)|\[[^\]]*\]")


def strip_ext(name):
    low = name.lower()
    for ext in sorted(ROM_EXTS, key=len, reverse=True):
        if low.endswith(ext):
            return name[: -len(ext)]
    return name


def norm(value):
    """Comparable form of a filename: no extension, accents, or punctuation,
    but region and revision tags preserved."""
    value = strip_ext(value)
    value = unicodedata.normalize("NFKD", value)
    value = "".join(c for c in value if not unicodedata.combining(c))
    value = value.lower().replace("&", " and ")
    value = re.sub(r"[^a-z0-9()\[\]]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def display_title(dat_name):
    """Display title from a DAT name: no extension, no region or revision tags,
    with the trailing article moved to the front."""
    value = TAG_RE.sub(" ", strip_ext(dat_name))
    value = re.sub(r"\s+", " ", value).strip().strip(",").strip()
    match = ARTICLE_RE.match(value)
    if match:
        value = f"{match.group(2)} {match.group(1)}"
    return value


def canon(value):
    """Canonical game title, the grouping key: the display title run through
    norm."""
    return norm(display_title(value))


def slug(value):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", value.lower()))


def collapse(entries, pack_id):
    """Collapses DAT dumps into canonical games, in order of appearance."""
    games = []
    by_canon = {}
    used_slugs = {}
    for entry in entries:
        key = canon(entry["name"])
        if not key:
            continue
        game = by_canon.get(key)
        if game is None:
            base = slug(key)
            count = used_slugs.get(base, 0) + 1
            used_slugs[base] = count
            game_slug = base if count == 1 else f"{base}-{count}"
            game = {
                "id": f"{pack_id}/{game_slug}",
                "title": display_title(entry["name"]),
                "dumps": [],
            }
            by_canon[key] = game
            games.append(game)
        dump = {"name": entry["name"]}
        for field in ("crc", "sha1", "serial", "region"):
            if entry.get(field):
                dump[field] = entry[field]
        game["dumps"].append(dump)
    return games


GAME_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "franchise": "franchise",
    "esrb": "esrb",
}


def enrich_from_side(games, side_maps):
    """Fills game fields from the CRC-to-value maps; the first dump with a
    value for a field wins."""
    for game in games:
        for source, target in GAME_FIELDS.items():
            table = side_maps.get(source)
            if not table:
                continue
            for dump in game["dumps"]:
                value = table.get(dump.get("crc"))
                if value:
                    game[target] = value
                    break
        years = side_maps.get("releaseyear")
        if years:
            for dump in game["dumps"]:
                value = years.get(dump.get("crc"))
                if value and value.isdigit():
                    game["year"] = int(value)
                    break
        serials = side_maps.get("serial")
        if serials:
            for dump in game["dumps"]:
                if dump.get("serial"):
                    continue
                value = serials.get(dump.get("crc"))
                if value:
                    dump["serial"] = value


# libretro-thumbnails replaces these characters with "_" in the filename.
THUMB_FORBIDDEN_RE = re.compile(r"[&*/:`<>?\\|]")
REGION_ORDER = ["(usa", "(world", "(europe", "(japan"]
YEAR_RE = re.compile(r"(19|20)\d{2}")


def thumb_name(dat_name):
    return THUMB_FORBIDDEN_RE.sub("_", dat_name) + ".png"


def region_rank(dat_name):
    low = dat_name.lower()
    for index, marker in enumerate(REGION_ORDER):
        if marker in low:
            return index
    return len(REGION_ORDER)


def attach_thumbnails(games, available, repo, folder, field):
    """Picks the image of the best-region dump that exists in the repository.

    Each folder is resolved on its own rather than reusing the dump the cover
    landed on: the three folders do not hold the same set of files, so a game
    whose USA cover is missing can still have a USA screenshot.
    """
    for game in games:
        best = None
        for dump in sorted(game["dumps"], key=lambda d: region_rank(d["name"])):
            name = thumb_name(dump["name"])
            if name in available:
                best = name
                break
        if best is None:
            continue
        game[field] = THUMBS_RAW.format(
            repo=repo, folder=folder, name=urllib.parse.quote(best, safe="")
        )


OPENVGDB_FIELDS = ("synopsis", "cover", "developer", "publisher", "genre", "year")


def _openvgdb_rows(conn, key_column):
    """Maps an uppercase key to the useful OpenVGDB fields, skipping the rows
    that carry no key and the rows where every field is empty."""
    rows = conn.execute(
        f"SELECT r.{key_column}, rel.releaseDescription, rel.releaseCoverFront, "
        "rel.releaseDeveloper, rel.releasePublisher, rel.releaseGenre, rel.releaseDate "
        "FROM ROMs r JOIN RELEASES rel ON rel.romID = r.romID"
    )
    index = {}
    for key, synopsis, cover, developer, publisher, genre, date in rows:
        if not key:
            continue
        year = None
        if date:
            match = YEAR_RE.search(date)
            if match:
                year = int(match.group(0))
        record = {"synopsis": synopsis, "cover": cover, "developer": developer,
                  "publisher": publisher, "genre": genre, "year": year}
        if not any(record.values()):
            continue
        index.setdefault(key.strip().upper(), record)
    return index


def openvgdb_index(conn):
    """Maps uppercase CRC32 to the useful OpenVGDB fields."""
    return _openvgdb_rows(conn, "romHashCRC")


def openvgdb_serial_index(conn):
    """Maps uppercase media serial to the same fields.

    The disc systems need this. Their DAT records the CRC of the disc image,
    while OpenVGDB records the CRC of a different dump of the same disc, so the
    two never meet: joining PlayStation by CRC alone matched 0 of 6366 games.
    The serial (`SLUS-01272`) is printed on the disc and both sides agree on it.
    """
    return _openvgdb_rows(conn, "romSerial")


def enrich_from_openvgdb(games, index, serial_index=None):
    """Fills gaps only; libretro-database always wins over OpenVGDB.

    CRC is tried across every dump before serial is tried at all. CRC names one
    exact dump while a serial names a release, so preferring it keeps the
    cartridge systems on the more precise key and leaves serial as the fallback
    that only the disc systems ever reach.
    """
    for game in games:
        record = _first_match(game, index, "crc")
        if record is None and serial_index:
            record = _first_match(game, serial_index, "serial")
        if record is None:
            continue
        for field in OPENVGDB_FIELDS:
            if record.get(field) and not game.get(field):
                game[field] = record[field]


def _first_match(game, index, dump_key):
    for dump in game["dumps"]:
        value = dump.get(dump_key)
        if not value:
            continue
        record = index.get(value.strip().upper())
        if record:
            return record
    return None


def build_pack(system, dat_text, side_texts, thumbs, openvgdb, built,
               serial_index=None):
    """Assembles everything into a pack document ready to serialize.

    `thumbs` maps a pack field to the filenames available in that field's
    folder, so a repository missing one folder costs only that field.
    """
    pack_id = normalize(system["system"])
    games = collapse(parse_dat(dat_text), pack_id)
    side_maps = {
        source: parse_side_dat(text, SIDE_FIELDS[source])
        for source, text in side_texts.items()
    }
    enrich_from_side(games, side_maps)
    for field, folder in THUMB_FOLDERS.items():
        attach_thumbnails(games, thumbs.get(field, set()), system["thumbs"],
                          folder, field)
    enrich_from_openvgdb(games, openvgdb, serial_index)
    return {"pack": pack_id, "system": system["system"], "built": built, "games": games}


def pack_bytes(pack):
    """Compact JSON in deterministic gzip: mtime zeroed so an unchanged
    rebuild produces identical bytes."""
    raw = json.dumps(pack, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", mtime=0) as out:
        out.write(raw)
    return buffer.getvalue()


def build_index(packs, aliases, built):
    return {
        "built": built,
        "packs": [{
            "pack": pack["pack"],
            "system": pack["system"],
            "games": len(pack["games"]),
            "aliases": aliases.get(pack["pack"], []),
        } for pack in packs],
    }


def fetch_text(url, optional=False):
    """Downloads text. With optional=True a 404 returns None."""
    try:
        with urllib.request.urlopen(url, timeout=180) as response:
            return response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        if optional and error.code == 404:
            return None
        raise


def fetch_json(url, token=None):
    request = urllib.request.Request(url)
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode("utf-8"))


def thumbnail_names(repo, folder, token=None):
    """Filenames in one thumbnail folder; a truncated tree returns an empty set."""
    try:
        tree = fetch_json(THUMBS_API.format(repo=repo, folder=folder), token)
    except urllib.error.HTTPError as error:
        print(f"  {folder} for {repo} unavailable: HTTP {error.code}", file=sys.stderr)
        return set()
    if tree.get("truncated"):
        print(f"  tree for {repo}/{folder} truncated, skipping it", file=sys.stderr)
        return set()
    return {entry["path"] for entry in tree.get("tree", [])}


def download_openvgdb(dest_dir):
    """Downloads and unzips openvgdb.sqlite, returning the connection."""
    zip_path = os.path.join(dest_dir, "openvgdb.zip")
    urllib.request.urlretrieve(OPENVGDB_URL, zip_path)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(dest_dir)
    return sqlite3.connect(os.path.join(dest_dir, "openvgdb.sqlite"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="dist/packs", help="output directory")
    parser.add_argument("--built", required=True, help="build date, YYYY-MM-DD")
    parser.add_argument("--only", action="append", default=[],
                        help="build only these pack ids, repeatable")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    token = os.environ.get("GITHUB_TOKEN")
    selected = [s for s in SYSTEMS
                if not args.only or normalize(s["system"]) in args.only]
    if not selected:
        raise SystemExit(f"no system matches {args.only}")

    with tempfile.TemporaryDirectory() as tmp:
        conn = download_openvgdb(tmp)
        openvgdb = openvgdb_index(conn)
        serial_index = openvgdb_serial_index(conn)
        conn.close()
        print(f"OpenVGDB: {len(openvgdb)} CRCs, {len(serial_index)} serials")

        packs = []
        aliases = {}
        for system in selected:
            pack_id = normalize(system["system"])
            print(f"{system['system']}")
            dat_url = "{}/metadat/{}/{}.dat".format(
                LIBRETRO_RAW, system["group"],
                urllib.parse.quote(system["system"]))
            dat_text = fetch_text(dat_url)
            side_texts = {}
            for source in SIDE_FIELDS:
                url = "{}/metadat/{}/{}.dat".format(
                    LIBRETRO_RAW, source, urllib.parse.quote(system["system"]))
                text = fetch_text(url, optional=True)
                if text is not None:
                    side_texts[source] = text
            thumbs = {field: thumbnail_names(system["thumbs"], folder, token)
                      for field, folder in THUMB_FOLDERS.items()}
            pack = build_pack(system, dat_text, side_texts, thumbs, openvgdb,
                              args.built, serial_index)
            counts = ", ".join(
                f"{sum(1 for g in pack['games'] if g.get(field))} {field}"
                for field in ("cover", "screenshot", "titleScreen", "synopsis"))
            print(f"  {len(pack['games'])} games, {counts}")
            path = os.path.join(args.out, f"{pack_id}.json.gz")
            with open(path, "wb") as out:
                out.write(pack_bytes(pack))
            packs.append(pack)
            aliases[pack_id] = system["aliases"]

        index = build_index(packs, aliases, args.built)
        with open(os.path.join(args.out, "index.json"), "w", encoding="utf-8") as out:
            json.dump(index, out, ensure_ascii=False, indent=2)
        print(f"{len(packs)} packs in {args.out}")


if __name__ == "__main__":
    main()
