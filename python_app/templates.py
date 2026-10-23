"""Template PNGs for the user's own screen art and kits, zipped with a README.

Each file is a slot's canvas in mid grey with a 2 px red box (and a small red
label) around every region the game shows, so the user paints inside the
boxes and nothing of theirs lands where the game never looks. Geometry comes
from the library where it has it (WE2002's `SLOTS`, each game's kit texture
page) and from the known screen sizes for PES 2013; a guide source the library
does not have yet is skipped, never a reason to fail the zip.
"""
import io
import os
import zipfile

_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rrp_assets')
FONT = os.path.join(_ASSETS, 'ChakraPetch-Bold.ttf')

GREY = (128, 128, 128, 255)
RED = (255, 0, 0, 255)

NOTE = ('Keep your content inside the red boxes; the red lines are guides, do not '
        'paint them. A PNG with transparency is fine.')


def _boxes(img, guides):
    """Draw a 2 px red box and label per guide (x, y, w, h, label) on img."""
    from PIL import ImageDraw, ImageFont
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 12)
    for x, y, w, h, label in guides:
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline=RED, width=2)
    # Labels last, on a grey backing, so a neighbour's line never cuts through
    # them; one wider than its box goes to the bottom-left, clear of the
    # neighbour's own top-left label.
    for x, y, w, h, label in guides:
        l, t, r, b = draw.textbbox((0, 0), label, font=font)
        ly = y + 3 if r - l + 8 <= w else y + h - (b - t) - 4
        draw.rectangle((x + 3, ly - 1, x + 5 + r - l, ly + b - t + 1), fill=GREY)
        draw.text((x + 4, ly - t), label, font=font, fill=RED)


def _png(img):
    buf = io.BytesIO()
    img.save(buf, 'PNG')
    return buf.getvalue()


def render(width, height, guides):
    """A width x height grey PNG (bytes) with a red box and label per guide."""
    from PIL import Image
    img = Image.new('RGBA', (width, height), GREY)
    _boxes(img, guides)
    return _png(img)


def outline(png, regions):
    """png (bytes) with a red box per region ({label: (x, y, w, h)}); the
    bytes untouched when there are none."""
    from PIL import Image
    if not regions:
        return png
    img = Image.open(io.BytesIO(png)).convert('RGBA')
    _boxes(img, [(x, y, w, h, label) for label, (x, y, w, h) in regions.items()])
    return _png(img)


def we2002_guides(slot):
    """(x, y, w, h, label) per region of a WE2002 slot: its `guides` when the
    library has them, else every piece the game draws, labelled by index."""
    guides = getattr(slot, 'guides', None)
    if guides:
        return [(g.x, g.y, g.w, g.h, g.label) for g in guides]
    return [(p.x, p.y, p.w, p.h, f'piece {i}')
            for i, p in enumerate(slot.pieces) if not getattr(p, 'clear', False)]


def we2002_screens(slots):
    """[(file name, png, description)] for WE2002's slots ({name: Slot})."""
    return [(f'{name}.png', render(s.width, s.height, we2002_guides(s)),
             f'The {name} screen art canvas, {s.width}x{s.height} pixels. Each box is one '
             'region the game draws somewhere on screen; a PNG of another size is stretched '
             'to this canvas, so keep the size.')
            for name, s in slots.items()]


def pes_screens():
    """[(file name, png, description)] for PES 2013's four full-screen textures
    (the PS2 stretches each square over the 4:3 frame)."""
    from pes_art import SIZES
    out = []
    for name, size in SIZES.items():
        guides = [(0, 0, size, size, 'whole screen, shown stretched to 4:3')]
        if name == 'title':
            guides.append((round(size * .06), round(size * .45), round(size * .24), round(size * .08),
                           'PRESS ANY BUTTON (game text)'))
        out.append((f'{name}.png', render(size, size, guides),
                    f'The {name} texture, {size}x{size} pixels: the whole square is shown stretched '
                    f'over the 4:3 screen, so draw it as if it were {size}x{size * 3 // 4}. A smaller '
                    'PNG is pasted centred (letterboxed), never enlarged, so keep the exact size.'))
    return out


def nhl07_screens():
    """[(file name, png, description)] for NHL 07's screen slots, from the
    library's `screens.SLOTS` and their guides."""
    from retro_roster_patcher.games.nhl07_psp.screens import SLOTS
    return [(f'{s.name}.png', render(s.size[0], s.size[1], [(g.x, g.y, g.w, g.h, g.label) for g in s.guides]),
             f'The {s.name} picture, {s.size[0]}x{s.size[1]} pixels: {s.description}. A box marked '
             '"game" is where the game draws over your picture, so keep it plain there. A PNG of '
             'another size is stretched to this size.')
            for s in SLOTS]


def iss_screens():
    """[(file name, png, description)] for ISS's screen slots, from the
    library's `screens.SLOTS` and their guides."""
    from retro_roster_patcher.games.iss_snes.screens import SLOTS
    return [(f'{s.name}.png', render(s.size[0], s.size[1], [(g.x, g.y, g.w, g.h, g.label) for g in s.guides]),
             f'The {s.name} picture, {s.size[0]}x{s.size[1]} pixels: {s.description}. A box marked '
             'as the game\'s is where the game draws over your picture, so keep it plain there. '
             'The cartridge has few colours and tiles: a photo is reduced to fit, so bold, flat art '
             'looks best. A PNG of another size is stretched to this size.')
            for s in SLOTS]


def kit_photo_guide():
    """(file name, png, description) of the layout a picked kit picture should have."""
    w, h = 96, 128
    shirt, shorts = round(h * .55), round(h * .80)
    guides = [(0, 0, w, shirt, 'shirt'), (0, shirt, w, shorts - shirt, 'shorts'), (0, shorts, w, h - shorts, 'socks')]
    return ('kit-photo-guide.png', render(w, h, guides),
            'How a kit picture you pick should be laid out, 96x128 pixels (any size with the same '
            'proportions works): the app reads the shirt colour and pattern from the top band, '
            'the shorts from the middle band and the socks from the bottom one.')


def files_for(game_id, supports_kits):
    """[(file name, png, description)] of game_id's screen templates, plus
    the kit photo guide when it takes kits (a team's own kit page comes from
    the per-team kit zip, `build_kits`, since it needs the disc)."""
    if game_id == 'we2002':
        from retro_roster_patcher.games.we2002.screen_art import SLOTS
        files = we2002_screens(SLOTS)
    elif game_id == 'pes2013-ps2':
        files = pes_screens()
    elif game_id == 'nhl07-psp':
        files = nhl07_screens()
    elif game_id == 'iss-snes':
        files = iss_screens()
    else:
        raise ValueError(f'No templates for {game_id}')
    if supports_kits:
        files.append(kit_photo_guide())
    return files


def write_zip(out_dir, stem, files, intro=''):
    """`<out_dir>/<stem>.zip` holding files plus a README (intro, then a
    paragraph per file); returns (zip path, [names])."""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f'{stem}.zip')
    readme = (intro + '\n\n' if intro else '') + '\n\n'.join(f'{name}\n{desc} {NOTE}' for name, _, desc in files) + '\n'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for name, png, _ in files:
            zf.writestr(name, png)
        zf.writestr('README.txt', readme)
    return path, [name for name, _, _ in files] + ['README.txt']


def build(game_id, out_dir, supports_kits):
    return write_zip(out_dir, f'{game_id}-templates', files_for(game_id, supports_kits))


# -- one team's current kit pages, to paint over -----------------------------

KIT_PAGE_SIZE = {'we2002': '128x256', 'pes2013-ps2': '512x256'}


def we2002_tex(slot):
    """The TEX index a WE2002 slot's kit is read from: TEX 0-62 are the
    national and all-star teams, 63-94 the Master League clubs, and a mapped
    slot below 32 owns both TEX slot and 63 + slot (the patch writes the same
    kit to both), so its page comes from the club copy."""
    slot = int(slot)
    return 63 + slot if slot < 32 else slot


def _we2002_lib():
    """The WE2002 kit texture functions this library exposes, or None: a
    namespace with read_tex_files, apply_spec, page_png, template_preview and
    KitSpec. Isolated so the tests can stand it in."""
    import types
    try:
        from retro_roster_patcher.core.kits import KitSpec
        from retro_roster_patcher.games.we2002.jersey_tex import apply_spec, page_png, template_preview
        from retro_roster_patcher.games.we2002.rom_writer import read_tex_files
    except Exception:
        return None
    return types.SimpleNamespace(KitSpec=KitSpec, apply_spec=apply_spec, page_png=page_png,
                                 template_preview=template_preview, read_tex_files=read_tex_files)


def we2002_kit_files(patcher, rom, slot, whiches, template=None):
    """[(name, png, description)] for a WE2002 slot (or, with template, that
    design): each kit's page outlined by the library's `kit_page_png`, its
    mounted look from `kit_preview_png`, and one example pair (the page
    painted red/white stripes with `apply_spec`, and how that comes out).
    Whatever this library does not expose yet, or fails, is left out."""
    from pathlib import Path
    tex_slot = we2002_tex(slot)
    tex = tex_slot if template is None else int(template)
    source = f'template {template}' if template is not None else f'slot {slot}'
    page, preview = getattr(patcher, 'kit_page_png', None), getattr(patcher, 'kit_preview_png', None)
    files = []
    for which in whiches:
        if page:
            try:
                files.append((f'{which}.png', page(Path(rom), tex_slot, which, template=template),
                              f'The current {which} kit texture page of {source}, 128x256 pixels.'))
            except Exception:
                pass
        if preview:
            try:
                files.append((f'{which}-preview.png', preview(Path(rom), tex, which, None),
                              f'How {which}.png looks on the player.'))
            except Exception:
                pass
    lib = _we2002_lib()
    if lib:
        try:
            which = whiches[0]
            spec = lib.KitSpec(shirt=(220, 0, 0), secondary=(255, 255, 255), pattern='stripes',
                               shorts=(255, 255, 255), socks=(220, 0, 0))
            painted = lib.apply_spec(lib.read_tex_files(str(rom))[tex], which, spec)
            files.append(('example-page.png', lib.page_png(painted, which, guides=False),
                          f'An example: the {which} page of {source} painted with red and white stripes.'))
            files.append(('example-preview.png', lib.template_preview(painted, which),
                          'How example-page.png comes out on the player, so you can see which part of '
                          'the page goes where.'))
        except Exception:
            pass
    return files


def _pes_lib():
    """The PES 2013 kit texture modules this library exposes, or None: a
    namespace with kit_textures, kits and RomReader. Isolated for the tests."""
    import types
    try:
        from retro_roster_patcher.games.pes2013_ps2 import kit_textures, kits
        from retro_roster_patcher.games.pes2013_ps2.rom_reader import RomReader
    except Exception:
        return None
    return types.SimpleNamespace(kit_textures=kit_textures, kits=kits, RomReader=RomReader)


def pes_kit_files(rom, slot, whiches):
    """[(name, png, description)] of a PES slot's licensed kit textures,
    outlined with the library's REGIONS; nothing when the library lacks them,
    its REGIONS are still empty (a page without boxes would mislead), the
    image does not load, or the slot's kits are parametric (drawn from
    colours, no texture)."""
    lib = _pes_lib()
    regions = getattr(lib.kit_textures, 'REGIONS', None) if lib else None
    if not regions:
        return []
    reader = lib.RomReader(str(rom))
    if not reader.load():
        return []
    files = []
    for which in whiches:
        try:
            png = lib.kit_textures.read_kit_png(reader, slot, getattr(lib.kits, which.upper()))
        except Exception:
            continue
        files.append((f'{which}.png', outline(png, regions),
                      f'The current {which} kit texture page of slot {slot}, 512x256 pixels.'))
    return files


def iss_kit_files(patcher, rom, slot, whiches):
    """[(name, png, description)]: an ISS slot's kits as the game draws them
    (`kit_preview_png`); ISS has no page to paint, its kits are colours and a
    chest design."""
    from pathlib import Path
    files = []
    for which in whiches:
        try:
            files.append((f'{which}-preview.png', patcher.kit_preview_png(Path(rom), int(slot), which, None),
                          f'The current {which} kit of slot {slot} on the Team Colors player.'))
        except Exception:
            pass
    return files


def build_kits(game_id, out_dir, patcher, rom, slot, which=None, template=None):
    """`<out_dir>/<game_id>-kit-template-slot<slot>.zip`: the team's current
    home/away kit pages (which=None for both), their mounted previews and a
    painted example where the library provides them, the kit photo guide, and
    a README; returns (zip path, [names])."""
    whiches = [which] if which else ['home', 'away']
    if game_id == 'we2002':
        files = we2002_kit_files(patcher, rom, slot, whiches, template)
    elif game_id == 'pes2013-ps2':
        files = pes_kit_files(rom, slot, whiches)
    elif game_id == 'iss-snes':
        files = iss_kit_files(patcher, rom, slot, whiches)
        files.append(kit_photo_guide())
        intro = ('ISS kits are colours: the shirt, shorts and socks, plus a chest design. Upload a kit photo '
                 '(shirt at the top, shorts in the middle, socks at the bottom, see kit-photo-guide.png): its '
                 'colours are read, and stripes or hoops pick the cartridge\'s striped or banded chest design. '
                 'The design is the team\'s, so the away shirt wears the home kit\'s. home-preview.png and '
                 'away-preview.png show the kits the slot has now.')
        return write_zip(out_dir, f'{game_id}-kit-template-slot{slot}', files, intro)
    else:
        raise ValueError(f'No kit templates for {game_id}')
    files.append(kit_photo_guide())
    size = KIT_PAGE_SIZE[game_id]
    intro = (f'Paint over home.png / away.png keeping the exact size ({size} pixels) and the red boxes: '
             'the red lines are guides and are not painted. Upload the result as the team\'s kit PNG. '
             'A PNG of any other size is read as a kit photo instead (shirt at the top, shorts in the '
             'middle, socks at the bottom, see kit-photo-guide.png). home-preview.png shows how home.png '
             'looks on the player; example-page.png is a painted page and example-preview.png how it '
             'comes out, so you can see which part of the page goes where.')
    return write_zip(out_dir, f'{game_id}-kit-template-slot{slot}', files, intro)


if __name__ == '__main__':
    import sys
    for game in ('we2002', 'pes2013-ps2', 'nhl07-psp', 'iss-snes'):
        print(*build(game, sys.argv[1], supports_kits=True))
