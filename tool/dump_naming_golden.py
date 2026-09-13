#!/usr/bin/env python3
"""Freezes what Python's norm/display_title/canon answer, so the Dart port in
the app can be checked case by case by test/pack_naming_parity_test.dart.

Titles are sampled from the real No-Intro DAT, then pseudonymized in place so
no real game name lands in the fixture while the shapes the parser must handle
survive. Do not edit the JSON by hand; regenerate with this script.

Usage:
    python3 tool/dump_naming_golden.py
"""
import json
import os
import re
import sys
import unicodedata
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_metadata_pack as b  # noqa: E402

SYSTEM = "Nintendo - Super Nintendo Entertainment System"
STRIDE = 50
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test", "fixtures", "naming_golden.json",
)

# Cases the DAT does not produce: filename with extension, underscore source,
# accent, inverted article, dangling comma, tag-only name. Already pseudonymized,
# so used verbatim; do not pass through pseudonymize (it is not idempotent).
HANDPICKED = [
    "Crystal Vanguard (USA).sfc",
    "Crystal Vanguard (USA).zip",
    "Crystal_Vanguard_(USA).zip",
    "crystal vanguard (usa)",
    "Legend of Kaelis, The (USA).smc",
    "Zxia Gztqfevzem, The (Japan)",
    "Awsoht Dupalj, (USA)",
    "Prismón Moso (Spain).gb",
    "Aqtúveh & Atérap (Europe)",
    "Zuf & Lgari Lozbillesh (USA)",
    "Super Pixel World 2 - Yuki's Island (USA)",
    "Reso 4 Kkesv HQ-H (Japan)",
    "Nigfseu Wugezcal Kze Zosbue - Miqed Rew '98 (Japan)",
    "Vol. 3",
    "(USA)",
    "---",
    "",
]

# Runs the pipeline reads by meaning, not as title text; kept verbatim.
REGION = {"usa", "japan", "europe", "world", "spain", "germany", "france",
          "italy", "brazil", "korea", "china", "australia", "canada",
          "netherlands", "sweden", "asia"}
STATUS = {"beta", "demo", "proto", "sample", "rev", "unl", "pirate", "alt",
          "auto"}
LANG = {"en", "fr", "de", "es", "it", "pt", "ja", "nl", "sv", "da", "no",
        "fi", "zh", "ko"}
TAG_TOKENS = REGION | STATUS | LANG
ARTICLES = {"the", "a", "an", "le", "la", "les", "el", "los", "das", "der",
            "die"}

# Shared substitution table; these substitutes must match the ones the rest of
# the branch uses, or cross-file tests break.
TABLE = [
    ("Chrono Trigger 2 - Ressurection of the Ancients",
     "Crystal Vanguard 2 - Ressurection of the Ancients"),
    ("Chrono Triggr", "Crystal Vanguar"),
    ("Chrono Triger", "Crystal Vangard"),
    ("Chrono Trigger", "Crystal Vanguard"),
    ("chrono trigger", "crystal vanguard"),
    ("Chrono_Trigger", "Crystal_Vanguard"),
    ("Chrono", "Crystal"),
    ("Super Mario World 2 - Yoshi's Island", "Super Pixel World 2 - Yuki's Island"),
    ("Super Mario World", "Super Pixel World"),
    ("Super Mario", "Super Pixel"),
    ("Mario", "Pixel"),
    ("mario", "pixel"),
    ("Legend of Zelda, The", "Legend of Kaelis, The"),
    ("Legend of Zelda", "Legend of Kaelis"),
    ("Zelda", "Kaelis"),
    ("zelda", "kaelis"),
    ("Super Metroid", "Super Vectron"),
    ("Metroid", "Vectron"),
    ("metroid", "vectron"),
    ("Pokémon", "Prismón"),
    ("Pokemon", "Prismon"),
    ("pokémon", "prismón"),
    ("pokemon", "prismon"),
    ("Final Fantasy", "Fabled Frontier"),
    ("Street Fighter", "Steel Brawler"),
    ("Donkey Kong", "Dune Titan"),
    ("Mega Man", "Metal Rider"),
    ("Sonic", "Sprint"),
    ("sonic", "sprint"),
    ("Kirby", "Kobold"),
    ("Tetris", "Tilefall"),
    ("Castlevania", "Cryptmanor"),
    ("Pac-Man", "Pix-Man"),
    ("Pac Man", "Pix Man"),
    ("pac-man", "pix-man"),
    ("'96 Zenkoku Koukou Soccer Senshuken", "'96 Zenith Cup Soccer"),
    ("Advanced Dungeons & Dragons - Eye of the Beholder",
     "Guild & Dungeon - Eye of the Watcher"),
    ("Ratchet: Deadlocked", "Sprocket: Deadlocked"),
]

VOWELS = "aeiou"
CONSONANTS = "bcdfghjklmnpqrstvwxz"
ROM_EXTS = (".zip", ".7z", ".sfc", ".smc", ".fig", ".swc", ".bin", ".rar",
            ".gz", ".nes", ".gb", ".gbc", ".gba", ".nds", ".3ds", ".n64",
            ".z64", ".v64", ".md", ".gen", ".gg", ".iso", ".cue", ".chd",
            ".col", ".int")
LETTER_RUN = re.compile(r"[^\W\d_]+", re.UNICODE)


def _sub_letter(ch, run, pos):
    """One replacement letter: same vowel/consonant class, case, and accent."""
    decomposed = unicodedata.normalize("NFD", ch.lower())
    base = decomposed[0]
    mark = "".join(c for c in decomposed if unicodedata.combining(c))
    pool = VOWELS if (base in VOWELS or mark) else CONSONANTS
    # crc32, not hash(); hash() is salted per process and would drift.
    pick = pool[zlib.crc32("{}:{}".format(pos, run).encode("utf-8")) % len(pool)]
    out = unicodedata.normalize("NFC", pick + mark) if mark else pick
    return out.upper() if ch.isupper() else out


def _pseudo_run(run):
    return "".join(_sub_letter(ch, run, i) for i, ch in enumerate(run))


def _tag_spans(s):
    return [(m.start(), m.end())
            for m in re.finditer(r"\([^)]*\)|\[[^\]]*\]", s)]


def _fiction_spans(name):
    spans = []
    for _, fake in TABLE:
        start = 0
        while True:
            i = name.find(fake, start)
            if i < 0:
                break
            spans.append((i, i + len(fake)))
            start = i + len(fake)
    return spans


def _ext_span(s):
    low = s.lower()
    for ext in sorted(ROM_EXTS, key=len, reverse=True):
        if low.endswith(ext):
            return (len(s) - len(ext), len(s))
    return None


def _article_spans(s):
    spans = []
    for m in re.finditer(r",\s+([^\W\d_]+)", s, re.UNICODE):
        if m.group(1).lower() in ARTICLES:
            spans.append((m.start(1), m.end(1)))
    return spans


def pseudonymize(name):
    """Replaces title letter runs with same-shape fiction, keeping grammar
    tokens, articles, extensions, and shared-table substitutes verbatim."""
    for real, fake in TABLE:
        name = name.replace(real, fake)
    tags = _tag_spans(name)
    ext = _ext_span(name)
    arts = _article_spans(name)
    fic = _fiction_spans(name)

    def within(a, b, spans):
        return any(lo <= a and b <= hi for lo, hi in spans)

    out, idx = [], 0
    for m in LETTER_RUN.finditer(name):
        s, e, run = m.start(), m.end(), m.group()
        out.append(name[idx:s])
        low = run.lower()
        protect = (
            within(s, e, fic)
            or (within(s, e, tags) and low in TAG_TOKENS)
            or ((s, e) in arts and low in ARTICLES)
            or (low == "vol" and name[e:e + 1] == ".")
            or (ext is not None and ext[0] <= s and e <= ext[1])
        )
        out.append(run if protect else _pseudo_run(run))
        idx = e
    out.append(name[idx:])
    return "".join(out)


def main():
    url = "{}/metadat/no-intro/{}.dat".format(
        b.LIBRETRO_RAW, b.urllib.parse.quote(SYSTEM)
    )
    names = [e["name"] for e in b.parse_dat(b.fetch_text(url))]
    sampled = names[::STRIDE]
    inputs = [pseudonymize(n) for n in sampled] + HANDPICKED
    if len(set(inputs)) != len(inputs):
        raise SystemExit("pseudonymizer collapsed distinct inputs")
    cases = []
    for name in inputs:
        cases.append({
            "input": name,
            "norm": b.norm(name),
            "displayTitle": b.display_title(name),
            "canon": b.canon(name),
        })
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(
            {"system": SYSTEM, "stride": STRIDE, "cases": cases},
            fh, ensure_ascii=False, indent=1, sort_keys=True,
        )
        fh.write("\n")
    print("{} cases in {}".format(len(cases), OUT))


if __name__ == "__main__":
    main()
