#!/usr/bin/env python3
"""Gera o golden de paridade entre o norm/canon do builder e o do app.

O app reimplementa norm, display_title e canon em Dart, porque precisa
normalizar em runtime nomes que nunca passaram pelo builder. As duas
implementações têm que concordar caso a caso. Este script congela o que o
Python responde, e test/pack_naming_parity_test.dart cobra o Dart.

Uso:
    python3 tool/dump_naming_golden.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_metadata_pack as b  # noqa: E402

SYSTEM = "Nintendo - Super Nintendo Entertainment System"
STRIDE = 50
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test", "fixtures", "naming_golden.json",
)

# Casos que o DAT não produz e o app vai ver: nome de arquivo com extensão,
# fonte que troca espaço por underscore, título com acento, artigo invertido,
# vírgula sobrando, e o nome que é só tag.
HANDPICKED = [
    "Chrono Trigger (USA).sfc",
    "Chrono Trigger (USA).zip",
    "Chrono_Trigger_(USA).zip",
    "chrono trigger (usa)",
    "Legend of Zelda, The (USA).smc",
    "Blue Crystalrod, The (Japan)",
    "Addams Family, (USA)",
    "Pokémon Rojo (Spain).gb",
    "Astérix & Obélix (Europe)",
    "Dig & Spike Volleyball (USA)",
    "Super Mario World 2 - Yoshi's Island (USA)",
    "Zero 4 Champ RR-Z (Japan)",
    "Jikkyou Powerful Pro Yakyuu - Basic Ban '98 (Japan)",
    "Vol. 3",
    "(USA)",
    "---",
    "",
]


def main():
    url = "{}/metadat/no-intro/{}.dat".format(
        b.LIBRETRO_RAW, b.urllib.parse.quote(SYSTEM)
    )
    names = [e["name"] for e in b.parse_dat(b.fetch_text(url))]
    sampled = names[::STRIDE]
    cases = []
    for name in sampled + HANDPICKED:
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
    print("{} casos em {}".format(len(cases), OUT))


if __name__ == "__main__":
    main()
