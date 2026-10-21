"""Retro Toolbox-branded screen images for the games whose art the library can
replace (today WE2002's title, main menu and boot screens).

Each image is painted on the slot's own canvas, piece by piece, so the game's
sprites (which draw rectangles of the canvas at their own screen positions)
each show one coherent element: the Retro Toolbox logo where the game drew its
ball, the app name where it drew the game's logo, the league and season where
it drew the year. Pixels no piece covers stay transparent. Text is white with
a purple stroke, legible on the black boot screen, the white licence screen,
the title's sky and the menu's dark field alike.

Geometry comes from the library's `SLOTS`, so this file never duplicates it.
"""
import os

_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rrp_assets')
LOGO = os.path.join(_ASSETS, 'logo.png')
FONT = os.path.join(_ASSETS, 'ChakraPetch-Bold.ttf')

WHITE = (255, 255, 255, 255)
PURPLE = (74, 43, 181, 255)


def _font(size):
    from PIL import ImageFont
    return ImageFont.truetype(FONT, size)


def _fit(draw, text, box_w, box_h, start=40, stroke=2):
    """The largest font size (<= start) whose rendering of text fits box_w x box_h."""
    for size in range(start, 7, -1):
        f = _font(size)
        l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
        if r - l <= box_w and b - t <= box_h:
            return f
    return _font(8)


def _text(img, piece, text, start=40, dy=0, max_h=None, stroke=2, fill=WHITE):
    """Centre text inside the piece (x, y, w, h), shifted by dy; returns its height."""
    from PIL import ImageDraw
    x, y, w, h = piece
    draw = ImageDraw.Draw(img)
    f = _fit(draw, text, w - 6, max_h or h, start, stroke)
    l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
    tw, th = r - l, b - t
    draw.text((x + (w - tw) // 2 - l, y + dy - t), text, font=f, fill=fill,
              stroke_width=stroke, stroke_fill=PURPLE)
    return th


def _logo(img, piece, size):
    """Paste the logo, size px square, centred in the piece."""
    from PIL import Image
    x, y, w, h = piece
    logo = Image.open(LOGO).convert('RGBA').resize((size, size), Image.Resampling.LANCZOS)
    img.alpha_composite(logo, (x + (w - size) // 2, y + (h - size) // 2))


def _rect(piece):
    return (piece.x, piece.y, piece.w, piece.h)


def _title(img, pieces, league, season):
    ball, logo_area, credits = (_rect(p) for p in pieces[:3])
    _logo(img, ball, 104)
    h = _text(img, logo_area, 'RETRO', start=34, dy=16)
    h += 2 + _text(img, logo_area, 'TOOLBOX', start=34, dy=18 + h)
    _text(img, logo_area, league, start=16, dy=30 + h, max_h=22)
    _text(img, credits, f'SEASON {season}', start=16, dy=50, max_h=24)


def _menu(img, pieces, league, season):
    ball = _rect(pieces[0])
    banner, year = _rect(pieces[2]), _rect(pieces[3])
    _logo(img, ball, 96)  # the ball sits at the screen edge; keep the logo inside it
    _text(img, banner, 'RETRO TOOLBOX', start=22, dy=4, max_h=24)
    _text(img, banner, league, start=14, dy=28, max_h=18)
    _text(img, year, str(season), start=22, dy=1)


def _boot(img, pieces, league, season):
    """Three screens: the licence text (pieces 0-1, one 256x128 area), the JFA
    emblem screen (2-5) and the KONAMI logo (9: upper half, 10: lower half of
    a centred 128x256 column; 6-8 are lettering overlays, left transparent)."""
    x, y, w, h = _rect(pieces[0])
    licence = (x, y, w + pieces[1].w, h)
    _text(img, licence, 'RETRO TOOLBOX', start=20, dy=14, max_h=24)
    th = _text(img, licence, league, start=22, dy=50, max_h=28)
    _text(img, licence, f'SEASON {season}', start=16, dy=58 + th, max_h=22)
    # JFA screen: the emblem sprite is the top-left 96x112 of piece 3, its
    # caption the 120x48 at (8,136) of the page, drawn under it.
    emblem = pieces[3]
    _logo(img, (emblem.x, emblem.y, 96, 112), 88)
    caption = pieces[4]
    _text(img, (caption.x + 8, caption.y + 8, 120, 48), 'RETRO TOOLBOX', start=16, dy=14, max_h=20)
    upper, lower = _rect(pieces[9]), _rect(pieces[10])
    _logo(img, upper, 112)
    th = _text(img, lower, 'RETRO', start=34, dy=8)
    _text(img, lower, 'TOOLBOX', start=34, dy=10 + th)


_PAINTERS = {'title': _title, 'menu': _menu, 'boot': _boot}


def render_default_images(game_id, league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every slot of game_id; returns {slot: path}."""
    from PIL import Image
    if game_id != 'we2002':
        raise ValueError(f'No branded screen images for {game_id}')
    from retro_roster_patcher.games.we2002.screen_art import SLOTS
    os.makedirs(out_dir, exist_ok=True)
    league = (league or 'Retro Toolbox').upper()
    written = {}
    for name, slot in SLOTS.items():
        img = Image.new('RGBA', (slot.width, slot.height), (0, 0, 0, 0))
        _PAINTERS[name](img, slot.pieces, league, season)
        path = os.path.join(out_dir, f'{name}.png')
        img.save(path)
        written[name] = path
    return written


if __name__ == '__main__':
    import sys
    import tempfile
    out = render_default_images('we2002', 'Brasileirão Série A', 2026, sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp())
    from PIL import Image
    for name, path in out.items():
        im = Image.open(path)
        assert im.mode == 'RGBA' and im.getbbox(), name
        print(name, im.size, path)
