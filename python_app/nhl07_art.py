"""Retro Toolbox-branded screens for NHL 07 (PSP): the boot splash, title,
menu backdrop, logo, menu player, loading screens and the two legal badges
the library can replace (its `image_slots`). The badges stay empty, and the art
names the update by its season, never as one of EA's games.

The full-screen slots are 512x256 textures the PSP stretches over its 480x272
screen, so each is designed on a 480x272 canvas with square pixels and then
resized to 512x256. The menu backdrop sits under every menu and the legal
screen, whose items are dark navy in the middle and white in the top and
bottom bands, so it keeps that layout: a light middle between two deep bands.
The logo, player and badges are drawn over the backdrop, on transparency.
Checked in PPSSPP, Oct 2026.
"""
import os

_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rrp_assets')
LOGO = os.path.join(_ASSETS, 'logo.png')
FONT = os.path.join(_ASSETS, 'ChakraPetch-Bold.ttf')

WHITE = (255, 255, 255, 255)
PURPLE = (74, 43, 181, 255)
DEEP = (27, 15, 58, 255)
LIGHT = (232, 228, 248, 255)
CLEAR = (0, 0, 0, 0)

SCREEN = (480, 272)
#: Slot size the library stores; full-screen slots are designed at SCREEN.
SIZES = {
    'boot': (512, 256), 'title': (512, 256), 'menu': (512, 256), 'loading': (512, 256),
    'logo': (256, 64), 'player': (256, 512), 'league_badge': (128, 128), 'players_badge': (128, 128),
}
_FULL_SCREEN = ('boot', 'title', 'menu', 'loading')


def _font(size):
    from PIL import ImageFont
    return ImageFont.truetype(FONT, size)


def _fit(draw, text, box_w, box_h, start, stroke=2):
    """The largest font (<= start) whose rendering of text fits box_w x box_h."""
    for size in range(start, 7, -1):
        f = _font(size)
        l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
        if r - l <= box_w and b - t <= box_h:
            return f
    return _font(8)


def _lines(img, cx, lines, top, bottom, box_w=None, fill=WHITE, stroke=PURPLE):
    """Draw text lines centred on x=cx between top and bottom; lines = [(text, max size, max h)]."""
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    fitted = []
    for text, start, max_h in lines:
        f = _fit(draw, text, (box_w or img.width) - 16, max_h, start)
        l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=2)
        fitted.append((text, f, l, t, r - l, b - t))
    gap = 6
    total = sum(h for *_, h in fitted) + gap * (len(fitted) - 1)
    y = top + (bottom - top - total) // 2
    for text, f, l, t, w, h in fitted:
        draw.text((cx - w // 2 - l, y - t), text, font=f, fill=fill, stroke_width=2, stroke_fill=stroke)
        y += h + gap


def _logo(img, cx, cy, size, alpha=255):
    """Paste the app logo, size px square, centred on (cx, cy), faded to alpha."""
    from PIL import Image
    logo = Image.open(LOGO).convert('RGBA').resize((size, size), Image.Resampling.LANCZOS)
    if alpha < 255:
        logo.putalpha(logo.getchannel('A').point(lambda a: a * alpha // 255))
    img.alpha_composite(logo, (cx - size // 2, cy - size // 2))


def season_mark(season):
    """'25-26' for the 2025 season: the update is named by its season, never as
    one of EA's own games (EA sells 'NHL 26')."""
    try:
        return f'{int(season) % 100:02d}-{(int(season) + 1) % 100:02d}'
    except (TypeError, ValueError):
        return 'HOCKEY'


UPDATE_LINE = 'UNOFFICIAL ROSTER UPDATE'


ICE_TOP = (206, 222, 242, 255)
ICE_BOTTOM = (238, 244, 251, 255)
RINK_BLUE = (70, 110, 200, 70)
RINK_RED = (200, 40, 60, 60)


def _ice(img):
    """A light ice surface with faint rink markings, like the game's own screens:
    the game writes navy text over the bottom of the title, so it stays light."""
    from PIL import Image, ImageDraw
    w, h = img.size
    for y in range(h):
        t = y / max(1, h - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(ICE_TOP, ICE_BOTTOM))
        ImageDraw.Draw(img).line((0, y, w, y), fill=row)
    marks = Image.new('RGBA', img.size, CLEAR)
    draw = ImageDraw.Draw(marks)
    cx, cy = w * 3 // 4, h // 2
    draw.line((cx, 0, cx, h), fill=RINK_RED, width=6)
    draw.ellipse((cx - 70, cy - 70, cx + 70, cy + 70), outline=RINK_BLUE, width=4)
    draw.ellipse((cx - 6, cy - 6, cx + 6, cy + 6), fill=RINK_BLUE)
    for x in (w // 4, w * 3 // 4 + 110):
        draw.line((x, 0, x, h), fill=RINK_BLUE, width=8)
    img.alpha_composite(marks)


def _band(img, top, bottom):
    """A deep purple band across the screen, its lower edge slanted."""
    from PIL import ImageDraw
    w = img.size[0]
    ImageDraw.Draw(img).polygon([(0, top), (w, top), (w, bottom - 14), (0, bottom)], fill=DEEP)


def _wordmark(img, x, y, text, size):
    """The game name in deep purple with a white outline, left-aligned at (x, y)."""
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    draw.text((x, y), text, font=_font(size), fill=DEEP, stroke_width=4, stroke_fill=WHITE)


def _boot(img, season):  # 480x272; the game draws its loading bar at (163, 195), 128x64
    _ice(img)
    _band(img, 0, 56)
    _lines(img, 240, [('RETRO TOOLBOX', 26, 30)], 8, 44)
    _logo(img, 128, 124, 112)
    _wordmark(img, 196, 86, season_mark(season), 64)


def _title(img, season):  # 480x272; the game writes its own lines below y 200
    _ice(img)
    _band(img, 0, 50)
    _lines(img, 240, [('RETRO TOOLBOX', 24, 28)], 6, 40)
    _logo(img, 112, 120, 118)
    _wordmark(img, 182, 70, season_mark(season), 70)
    _lines(img, 300, [(UPDATE_LINE, 22, 24)], 160, 192, box_w=260, fill=PURPLE, stroke=WHITE)


def _menu(img, season):  # 480x272: deep bands where the game writes white, light between
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 44, 479, 231), fill=LIGHT)
    _logo(img, 120, 160, 150, alpha=26)


def _loading(img, season):  # 480x272; the game draws its loading bar at (306, 206)
    _logo(img, 150, 120, 150)
    _lines(img, 150, [(season_mark(season), 30, 32), (UPDATE_LINE, 16, 18)], 196, 266, box_w=290)


def _logo_slot(img, season):  # 256x64 on transparency, shown about 237x52 over the backdrop
    _logo(img, 30, 32, 56)
    _lines(img, 30 + 30 + 96, [(season_mark(season), 40, 54)], 4, 60, box_w=200)


def _player(img, season):  # 256x512 on transparency; rows 0-271 show beside the menu
    _logo(img, 150, 136, 200, alpha=210)


def _league_badge(img, season):  # 128x128, left empty: the NHL Shield is the league's mark, not ours
    pass


def _players_badge(img, season):  # 128x128, left empty
    pass


_PAINTERS = {
    'boot': _boot, 'title': _title, 'menu': _menu, 'loading': _loading, 'logo': _logo_slot,
    'player': _player, 'league_badge': _league_badge, 'players_badge': _players_badge,
}


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every NHL 07 slot; returns {slot: path}."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    written = {}
    for name, size in SIZES.items():
        if name in _FULL_SCREEN:
            img = Image.new('RGBA', SCREEN, DEEP)  # each painter covers it or keeps it
            _PAINTERS[name](img, season)
            img = img.resize(size, Image.Resampling.LANCZOS)
        else:
            img = Image.new('RGBA', size, CLEAR)
            _PAINTERS[name](img, season)
        path = os.path.join(out_dir, f'{name}.png')
        img.save(path)
        written[name] = path
    return written


if __name__ == '__main__':
    import sys
    import tempfile
    out = render_default_images('NHL', 2025, sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp())
    from PIL import Image
    for name, path in out.items():
        im = Image.open(path)
        assert im.size == SIZES[name], (name, im.size)
        if name in _FULL_SCREEN:
            assert im.getchannel('A').getextrema() == (255, 255), f'{name} is not opaque'
        print(name, im.size, path)
