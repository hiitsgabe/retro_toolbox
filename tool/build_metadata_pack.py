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
    """Forma comparável do nome do arquivo: sem extensão, sem acento, sem
    pontuação, mas com as tags de região e revisão preservadas."""
    value = strip_ext(value)
    value = unicodedata.normalize("NFKD", value)
    value = "".join(c for c in value if not unicodedata.combining(c))
    value = value.lower().replace("&", " and ")
    value = re.sub(r"[^a-z0-9()\[\]]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def display_title(dat_name):
    """Título de exibição a partir do nome do DAT: sem extensão, sem tags de
    região e revisão, com o artigo de volta na frente.

    A troca do artigo acontece aqui, no nome cru, e não depois de norm, porque
    norm come a vírgula que separa "Legend of Zelda" de "The".
    """
    value = TAG_RE.sub(" ", strip_ext(dat_name))
    value = re.sub(r"\s+", " ", value).strip().strip(",").strip()
    match = ARTICLE_RE.match(value)
    if match:
        value = f"{match.group(2)} {match.group(1)}"
    return value


def canon(value):
    """Título canônico do jogo, a chave de agrupamento: o título de exibição
    passado por norm."""
    return norm(display_title(value))


def slug(value):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", value.lower()))


def collapse(entries, pack_id):
    """Dumps do DAT para jogos canônicos, na ordem em que aparecem."""
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
                # O título vem do primeiro dump, que preserva a grafia e os
                # acentos do DAT. O canon serve só para agrupar e para o slug.
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


# Campo do side file para chave no JSON do jogo. O serial é o único que não
# descreve o jogo e sim o dump, então tem tratamento próprio.
GAME_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "franchise": "franchise",
    "esrb": "esrb",
}


def enrich_from_side(games, side_maps):
    """Preenche os campos do jogo a partir dos mapas CRC para valor.

    Um jogo tem vários dumps; o primeiro dump que tiver valor para o campo
    ganha, o que torna o resultado determinístico.
    """
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


# O libretro-thumbnails troca estes caracteres por "_" no nome do arquivo.
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


def attach_thumbnail_covers(games, available, repo):
    """Escolhe a capa do libretro-thumbnails do dump de melhor região que
    realmente existe no repositório."""
    for game in games:
        best = None
        for dump in sorted(game["dumps"], key=lambda d: region_rank(d["name"])):
            name = thumb_name(dump["name"])
            if name in available:
                best = name
                break
        if best is None:
            continue
        game["cover"] = THUMBS_RAW.format(
            repo=repo, name=urllib.parse.quote(best, safe="")
        )


def openvgdb_index(conn):
    """CRC32 em maiúsculas para os campos úteis do OpenVGDB."""
    rows = conn.execute(
        "SELECT r.romHashCRC, rel.releaseDescription, rel.releaseCoverFront, "
        "rel.releaseDeveloper, rel.releasePublisher, rel.releaseGenre, rel.releaseDate "
        "FROM ROMs r JOIN RELEASES rel ON rel.romID = r.romID"
    )
    index = {}
    for crc, synopsis, cover, developer, publisher, genre, date in rows:
        if not crc:
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
        index.setdefault(crc.upper(), record)
    return index


def enrich_from_openvgdb(games, index):
    """Só preenche buraco. O libretro-database sempre ganha do OpenVGDB, que
    não tem licença declarada e é a fonte menos confiável das duas."""
    for game in games:
        for dump in game["dumps"]:
            record = index.get(dump.get("crc"))
            if not record:
                continue
            for field in ("synopsis", "cover", "developer", "publisher", "genre", "year"):
                if record.get(field) and not game.get(field):
                    game[field] = record[field]
            break


def build_pack(system, dat_text, side_texts, thumbs, openvgdb, built):
    """Junta tudo num documento de pacote pronto para serializar."""
    pack_id = normalize(system["system"])
    games = collapse(parse_dat(dat_text), pack_id)
    side_maps = {
        source: parse_side_dat(text, SIDE_FIELDS[source])
        for source, text in side_texts.items()
    }
    enrich_from_side(games, side_maps)
    attach_thumbnail_covers(games, thumbs, system["thumbs"])
    enrich_from_openvgdb(games, openvgdb)
    return {"pack": pack_id, "system": system["system"], "built": built, "games": games}


def pack_bytes(pack):
    """JSON compacto em gzip determinístico: mtime zerado para que uma
    rebuild sem mudança produza bytes idênticos."""
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
    """Baixa texto. Com optional=True um 404 vira None, que é o caso normal
    dos side files: eles só existem para os sistemas No-Intro."""
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


def thumbnail_names(repo, token=None):
    """Nomes de arquivo em Named_Boxarts. A árvore de um diretório único cabe
    numa chamada; se vier truncada o builder devolve conjunto vazio em vez de
    inventar URL que não existe."""
    try:
        tree = fetch_json(THUMBS_API.format(repo=repo), token)
    except urllib.error.HTTPError as error:
        print(f"  thumbnails de {repo} indisponiveis: HTTP {error.code}", file=sys.stderr)
        return set()
    if tree.get("truncated"):
        print(f"  arvore de {repo} truncada, ignorando capas", file=sys.stderr)
        return set()
    return {entry["path"] for entry in tree.get("tree", [])}


def download_openvgdb(dest_dir):
    """Baixa e descompacta o openvgdb.sqlite, devolvendo a conexão."""
    zip_path = os.path.join(dest_dir, "openvgdb.zip")
    urllib.request.urlretrieve(OPENVGDB_URL, zip_path)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(dest_dir)
    return sqlite3.connect(os.path.join(dest_dir, "openvgdb.sqlite"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="dist/packs", help="diretorio de saida")
    parser.add_argument("--built", required=True, help="data da build, YYYY-MM-DD")
    parser.add_argument("--only", action="append", default=[],
                        help="constroi so estes pack ids, repetivel")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    token = os.environ.get("GITHUB_TOKEN")
    selected = [s for s in SYSTEMS
                if not args.only or normalize(s["system"]) in args.only]
    if not selected:
        raise SystemExit(f"nenhum sistema casa com {args.only}")

    with tempfile.TemporaryDirectory() as tmp:
        conn = download_openvgdb(tmp)
        openvgdb = openvgdb_index(conn)
        conn.close()
        print(f"OpenVGDB: {len(openvgdb)} CRCs")

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
            thumbs = thumbnail_names(system["thumbs"], token)
            pack = build_pack(system, dat_text, side_texts, thumbs, openvgdb, args.built)
            with_cover = sum(1 for g in pack["games"] if g.get("cover"))
            with_synopsis = sum(1 for g in pack["games"] if g.get("synopsis"))
            print(f"  {len(pack['games'])} jogos, {with_cover} com capa, "
                  f"{with_synopsis} com sinopse")
            path = os.path.join(args.out, f"{pack_id}.json.gz")
            with open(path, "wb") as out:
                out.write(pack_bytes(pack))
            packs.append(pack)
            aliases[pack_id] = system["aliases"]

        index = build_index(packs, aliases, args.built)
        with open(os.path.join(args.out, "index.json"), "w", encoding="utf-8") as out:
            json.dump(index, out, ensure_ascii=False, indent=2)
        print(f"{len(packs)} pacotes em {args.out}")


if __name__ == "__main__":
    main()
