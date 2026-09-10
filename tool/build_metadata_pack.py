#!/usr/bin/env python3
"""Builds one metadata pack per console for the app's "Stremio de jogos" grid.

Sources, all public and without accounts:
  - libretro-database (CC BY-SA 4.0): the No-Intro and Redump DATs under
    metadat/, plus the per-field side files (genre, developer, publisher,
    releaseyear, franchise, esrb, serial) that key on CRC32.
  - OpenVGDB v29.0: synopsis and a fallback cover, joined by CRC32.
  - libretro-thumbnails: the preferred cover URL, checked for existence via
    the GitHub tree API so the pack never ships a dead link.

Output: <pack>.json.gz per system plus an index.json, both meant to be
uploaded to a GitHub release with the fixed tag "packs". The pack stores the
cover URL, never the image bytes.
"""
import gzip
import io
import json
import os
import re
import sqlite3
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

LIBRETRO_RAW = "https://raw.githubusercontent.com/libretro/libretro-database/master"
THUMBS_API = "https://api.github.com/repos/libretro-thumbnails/{repo}/git/trees/master:Named_Boxarts"
THUMBS_RAW = "https://raw.githubusercontent.com/libretro-thumbnails/{repo}/master/Named_Boxarts/{name}"
OPENVGDB_URL = "https://github.com/OpenVGDB/OpenVGDB/releases/download/v29.0/openvgdb.zip"

# Os side files por campo só existem para sistemas No-Intro. Para Redump o
# builder recebe 404 e segue em frente com o OpenVGDB.
SIDE_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "releaseyear": "releaseyear",
    "franchise": "franchise",
    "esrb": "esrb_rating",
    "serial": "serial",
}

# system: nome do sistema no libretro-database, e também o que vira o pack id.
# group: qual pasta de metadat tem o DAT principal.
# thumbs: repositório do libretro-thumbnails, que nem sempre casa com o nome
#         do sistema (Wii U Digital usa o repo do Wii U).
# aliases: como o console pode se chamar no catálogo do usuário.
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
# O md5 é capturado só para o grupo do sha1 cair na posição certa. Ele não vai
# para o pacote: nenhum dos três eixos de identidade da fatia 2 usa md5, e
# guardar um hash a mais por dump inflaria o pacote sem comprador.
ROM_RE = re.compile(
    r'rom \( name "([^"]+)"(?:\s+size \d+)?\s+crc (\w+)'
    r"(?:\s+md5 (\w+))?(?:\s+sha1 (\w+))?"
)
CRC_RE = re.compile(r"crc (\w+)")


def normalize(value):
    """Mesma regra do CatalogService._nameToId no app."""
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9]+", "_", value.lower()))


def parse_dat(text):
    """DAT principal do No-Intro ou do Redump para uma lista de dumps.

    Só a primeira linha rom de cada bloco entra: em jogos de disco as demais
    são faixas de áudio, cujo CRC não serve para identificar o arquivo que o
    usuário baixa.

    O crc e o sha1 sobem para maiúsculas porque são hexadecimais e a comparação
    precisa ser estável. O serial não: ele é uma string de catálogo do
    fabricante e vai para o pacote exatamente como o DAT emite.
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
    """Side file por campo para um mapa CRC32 em maiúsculas para valor."""
    field_re = re.compile(field + r' "([^"]+)"')
    out = {}
    for block in GAME_RE.findall(text):
        crc = CRC_RE.search(block)
        value = field_re.search(block)
        if crc and value:
            out[crc.group(1).upper()] = value.group(1)
    return out


def main():
    raise SystemExit("CLI ainda nao implementada, ver Task 10")


if __name__ == "__main__":
    main()
