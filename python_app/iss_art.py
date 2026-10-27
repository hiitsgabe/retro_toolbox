"""Retro Toolbox-branded screens for International Superstar Soccer (SNES): the
Konami logo screen, the title background and the menu wallpaper the library
can replace (its `image_slots`). The art names the update by its season.

Sizes and the regions the game draws over come from the library's
`iss_snes.screens.SLOTS` (measured in Mesen 2): on the title the ISS logo,
PRESS START, the two players and the copyright lines are the game's own, so the
art keeps clear of them. The wallpaper is a 256x256 pattern the menus scroll,
so it is built from one motif repeated, which tiles seamlessly and stays well
under the slot's 255-tile budget.
"""
import os

_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rrp_assets')
LOGO = os.path.join(_ASSETS, 'logo.png')
FONT = os.path.join(_ASSETS, 'ChakraPetch-Bold.ttf')

WHITE = (255, 255, 255, 255)
PURPLE = (74, 43, 181, 255)
DEEP = (27, 15, 58, 255)
LIGHT = (232, 228, 248, 255)
GRASS_TOP = (52, 128, 60, 255)
GRASS_BOTTOM = (34, 96, 44, 255)
STRIPE = (60, 140, 68, 255)
LINE = (220, 236, 220, 255)

SIZES = {'konami': (256, 224), 'title': (256, 224), 'menu': (256, 256)}


def _font(size):
    from PIL import ImageFont
    return ImageFont.truetype(FONT, size)


def _text(img, cx, cy, text, size, fill=WHITE, stroke=PURPLE, max_w=None):
    """`text` centred on (cx, cy), shrunk until it fits max_w (the image width
    less a margin by default)."""
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    while size > 8:
        l, t, r, b = draw.textbbox((0, 0), text, font=_font(size), stroke_width=2)
        if r - l <= (max_w or img.width - 8):
            break
        size -= 1
    draw.text((cx - (r - l) // 2 - l, cy - (b - t) // 2 - t), text, font=_font(size), fill=fill,
              stroke_width=2, stroke_fill=stroke)


def _logo(img, cx, cy, size, alpha=255):
    """Paste the app logo, size px square, centred on (cx, cy), faded to alpha."""
    from PIL import Image
    logo = Image.open(LOGO).convert('RGBA').resize((size, size), Image.Resampling.LANCZOS)
    if alpha < 255:
        logo.putalpha(logo.getchannel('A').point(lambda a: a * alpha // 255))
    img.alpha_composite(logo, (cx - size // 2, cy - size // 2))


def _vertical(img, top, bottom, a, b):
    """A vertical gradient from colour a at row `top` to b at row `bottom`."""
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    for y in range(top, bottom):
        t = (y - top) / max(1, bottom - top - 1)
        draw.line((0, y, img.width, y), fill=tuple(round(p + (q - p) * t) for p, q in zip(a, b)))


#: Leagues whose season is a calendar year, by the name the library gives them.
CALENDAR_SPORTS = ('mlb',)


def season_mark(league, season, fallback='SOCCER'):
    """'2026' for a calendar-year league (the Brasileirao, MLS, MLB), '26-27'
    for one that runs August to May (the NHL too), as ESPN names them; the
    update is named by its season, never as one of the publisher's games."""
    try:
        year = int(season)
    except (TypeError, ValueError):
        return fallback
    names = [s.strip().lower() for s in str(league or '').split('+')]
    if all(n in CALENDAR_SPORTS for n in names):
        return str(year)
    try:
        from retro_roster_patcher.sports import espn
        codes = [lg['code'] for lg in espn.ESPN_LEAGUES if lg['name'].lower() in names]
        calendar = getattr(espn, 'CALENDAR_YEAR_LEAGUES', ())
        if codes and all(c.lower().startswith(calendar) for c in codes):
            return str(year)
    except Exception:
        pass
    return f'{year % 100:02d}-{(year + 1) % 100:02d}'


def splash(img, mark):
    """A boot screen: the app's logo and name on a purple gradient, `mark`
    ROSTER UPDATE below."""
    _vertical(img, 0, img.height, DEEP, PURPLE)
    _logo(img, img.width // 2, 92, 104)
    _text(img, img.width // 2, 166, 'RETRO TOOLBOX', 26)
    _text(img, img.width // 2, 192, f'{mark}  ROSTER UPDATE', 12, stroke=DEEP)


def _konami(img, league, season):
    """The logo screen (a line sweeps it in from the top, as the cartridge's
    logo is)."""
    splash(img, season_mark(league, season))


def _title(img, league, season):
    """Behind the ISS logo: a light top half where the game's colourful logo
    and PRESS START sit, a pitch below with the two players in the middle, the
    update's season on the left and the app's logo on the right of them, and
    the copyright lines left clear at the bottom."""
    from PIL import ImageDraw
    _vertical(img, 0, 108, LIGHT, (214, 206, 240, 255))
    _vertical(img, 108, img.height, GRASS_TOP, GRASS_BOTTOM)
    draw = ImageDraw.Draw(img)
    for x in range(0, img.width, 32):  # mown stripes
        draw.rectangle((x, 108, x + 15, img.height), fill=STRIPE)
    draw.line((0, 112, img.width, 112), fill=LINE, width=2)  # touchline
    draw.ellipse((86, 140, 170, 224), outline=LINE, width=2)  # centre circle, under the players
    _text(img, 48, 146, season_mark(league, season), 22)
    _text(img, 48, 168, 'UNOFFICIAL', 9, stroke=DEEP)
    _text(img, 48, 179, 'ROSTER UPDATE', 9, stroke=DEEP)
    _logo(img, 208, 156, 52)


def _menu(img, league, season):
    """A 64x64 motif, repeated four times each way, so the pattern meets itself
    at every edge as the menus scroll: the app's logo, faded, on deep purple
    with a fine diagonal."""
    from PIL import Image, ImageDraw
    motif = Image.new('RGBA', (64, 64), DEEP)
    draw = ImageDraw.Draw(motif)
    for k in range(-64, 64, 16):
        draw.line((k, 64, k + 64, 0), fill=(40, 24, 82, 255), width=3)
    _logo(motif, 32, 32, 40, alpha=150)
    for y in range(0, img.height, 64):
        for x in range(0, img.width, 64):
            img.alpha_composite(motif, (x, y))


_PAINTERS = {'konami': _konami, 'title': _title, 'menu': _menu}


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every ISS slot; returns {slot: path}."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    written = {}
    for name, size in SIZES.items():
        img = Image.new('RGBA', size, DEEP)
        _PAINTERS[name](img, league, season)
        path = os.path.join(out_dir, f'{name}.png')
        img.convert('RGB').save(path)
        written[name] = path
    return written


def slots(package):
    """{name: Slot} of an SNES game's screen slots, from the library's
    `<package>.screens.SLOTS`."""
    import importlib
    return {s.name: s for s in importlib.import_module(f'retro_roster_patcher.games.{package}.screens').SLOTS}


def render_slots(package, painters, league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for each of package's slots that painters
    ({name: painter(img, league, season, slot)}) draws, on deep purple at the
    slot's size; returns {slot: path}. A slot the library adds later keeps the
    cartridge's art until it has a painter."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    written = {}
    for name, slot in slots(package).items():
        if name in painters:
            img = Image.new('RGBA', slot.size, DEEP)
            painters[name](img, league, season, slot)
            written[name] = os.path.join(out_dir, f'{name}.png')
            img.convert('RGB').save(written[name])
    return written


def _n64_title(img, league, season):
    """ISS 2000's whole title (320x240): the app's logo and name, the update's
    season below the blinking PRESS START box (91,163 138x14), which stays clear."""
    _vertical(img, 0, img.height, DEEP, PURPLE)
    _logo(img, img.width // 2, 78, 104)
    _text(img, img.width // 2, 142, 'RETRO TOOLBOX', 28)
    _text(img, img.width // 2, 200, f'{season_mark(league, season)}  ROSTER UPDATE', 14, stroke=DEEP)


def render_n64_images(league, season, out_dir):
    """ISS 2000 (N64): the wallpaper behind every menu, 312x236, and the title,
    320x240. The menus draw panels over most of the wallpaper, so it is the
    scrolling motif's look at full size: the season mark top left, where team
    select and the main menu leave the wallpaper bare."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    img = Image.new('RGBA', (312, 236), DEEP)
    _menu(img, league, season)
    _text(img, 70, 14, season_mark(league, season), 14)
    written = {'menu': os.path.join(out_dir, 'menu.png')}
    img.convert('RGB').save(written['menu'])
    title = Image.new('RGBA', (320, 240), DEEP)
    _n64_title(title, league, season)
    written['title'] = os.path.join(out_dir, 'title.png')
    title.convert('RGB').save(written['title'])
    return written


def _deluxe_title(img, league, season, slot=None):
    """ISS Deluxe's title (256x224): the game draws its lettering (16,41
    168x57), PRESS START (79,122) and the copyright (bottom 18 rows) over it,
    so the app's logo sits top right and the season on the pitch between."""
    from PIL import ImageDraw
    _vertical(img, 0, 112, LIGHT, (214, 206, 240, 255))
    _vertical(img, 112, img.height, GRASS_TOP, GRASS_BOTTOM)
    draw = ImageDraw.Draw(img)
    for x in range(0, img.width, 32):  # mown stripes
        draw.rectangle((x, 112, x + 15, img.height), fill=STRIPE)
    draw.line((0, 114, img.width, 114), fill=LINE, width=2)  # touchline
    _logo(img, 220, 62, 56)
    _text(img, img.width // 2, 158, season_mark(league, season), 24)
    _text(img, img.width // 2, 184, 'UNOFFICIAL ROSTER UPDATE', 10, stroke=DEEP)


def render_deluxe_images(league, season, out_dir):
    """ISS Deluxe (SNES): the Konami screen, the title and the menu wallpaper,
    at the library's slot sizes (`iss_deluxe_snes.screens.SLOTS`). The
    wallpaper is the 64x64 motif repeated: the slot holds 128 tiles."""
    painters = {
        'konami': lambda img, lg, ss, slot: _konami(img, lg, ss),
        'title': _deluxe_title,
        'menu': lambda img, lg, ss, slot: _menu(img, lg, ss),
    }
    return render_slots('iss_deluxe_snes', painters, league, season, out_dir)
