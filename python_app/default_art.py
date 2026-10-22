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


# The boot screens are drawn in a 384x480 frame with one texel per line and
# per column, so on a 4:3 screen a texel is ASPECT times wider than it is
# tall. Each painter composes its screen in display units (square pixels) and
# squashes the result to texels before placing it; the screen positions below
# were read off a labelled grid shown in DuckStation (Oct 2026).
ASPECT = 1.69


def _design(w, h):
    """A square-pixel canvas for a w x h texel region."""
    from PIL import Image
    return Image.new('RGBA', (round(w * ASPECT), h), (0, 0, 0, 0))


def _squash(canvas, w, h):
    from PIL import Image
    return canvas.resize((w, h), Image.Resampling.LANCZOS)


def _lines(canvas, cx, lines, top, bottom, max_w=None):
    """Draw text lines centred on x=cx, stacked and centred between top and
    bottom; lines = [(text, max font size, max height)]; each line fits in
    max_w (default: the canvas width)."""
    from PIL import ImageDraw
    draw = ImageDraw.Draw(canvas)
    fitted = []
    for text, start, max_h in lines:
        f = _fit(draw, text, (max_w or canvas.width) - 8, max_h, start)
        l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=2)
        fitted.append((text, f, l, t, r - l, b - t))
    gap = 4
    total = sum(h for *_, h in fitted) + gap * (len(fitted) - 1)
    y = top + (bottom - top - total) // 2
    for text, f, l, t, w, h in fitted:
        draw.text((cx - w // 2 - l, y - t), text, font=f, fill=WHITE, stroke_width=2, stroke_fill=PURPLE)
        y += h + gap


def _boot(img, pieces, league, season):
    """Three screens, in display order.

    KONAMI logo: pieces 9 (upper) and 10 (lower) form a 128x256 column shown
    centred on the screen. Licence text: piece 0 and piece 1 form a 256-wide
    area shown at x=17 of a 369-texel screen, so the screen centre is 167
    texels into it; only its rows 0-55 and 64-95 are drawn. JFA emblem: see
    the comments below. Pieces 6-8 are lettering overlays and stay
    transparent.
    """
    from PIL import Image
    logo = Image.open(LOGO).convert('RGBA')

    # KONAMI column: logo over two lines of text, the group centred.
    col = _design(128, 256)
    size = 110
    col.alpha_composite(logo.resize((size, size), Image.Resampling.LANCZOS), ((col.width - size) // 2, 22))
    _lines(col, col.width // 2, [('RETRO', 40, 46), ('TOOLBOX', 40, 46)], 138, 236)
    col = _squash(col, 128, 256)
    img.alpha_composite(col.crop((0, 0, 128, 128)), (pieces[9].x, pieces[9].y))
    img.alpha_composite(col.crop((0, 128, 128, 256)), (pieces[10].x, pieces[10].y))

    # Licence text. The sprites show rows 0-55 of the 256-wide area at lines
    # 176-232 and rows 64-91 at lines 239-266; rows 56-63 are never drawn and
    # rows 92-121 of piece 1 repeat off to the right, so the two zones get
    # their own lines. The area starts 16 texels in from the left of a
    # 369-texel screen, hence the centre at 169.
    cx = round(169 * ASPECT)
    lic = _design(256, 96)
    room = 2 * (lic.width - cx)  # centred text may not pass the right edge
    _lines(lic, cx, [('RETRO TOOLBOX', 24, 24), (league, 28, 28)], 2, 54, max_w=room)
    _lines(lic, cx, [(f'SEASON {season}', 22, 24)], 65, 90, max_w=room)
    lic = _squash(lic, 256, 96)
    img.alpha_composite(lic, (pieces[0].x, pieces[0].y))

    # JFA emblem page. Piece 2's columns 9-122 are shown on lines 83-210
    # centred on the screen: the logo and the app name go there. Piece 3 shows
    # off-centre below it and stays empty; piece 5 is the page's border tiles
    # and must stay transparent or its pixels repeat around the frame. The
    # caption is piece 4's rows 0-57 (columns 0-127) followed by its rows
    # 64-121 (columns 0-32): one 161-texel strip from x=104, centre 184.5.
    emb = _design(128, 128)
    cx = round(65 * ASPECT)
    size = 84
    emb.alpha_composite(logo.resize((size, size), Image.Resampling.LANCZOS), (cx - size // 2, 10))
    _lines(emb, cx, [('RETRO TOOLBOX', 22, 24), (f'SEASON {season}', 16, 18)], 96, 128)
    emb = _squash(emb, 128, 128)
    img.alpha_composite(emb, (pieces[2].x, pieces[2].y))
    # Glyphs crossing the seam at column 128 come out split, so the caption
    # stays within columns 35-126 (91 texels around the centre).
    cap = _design(161, 57)
    _lines(cap, round(80.5 * ASPECT), [(league, 28, 34)], 4, 53, max_w=round(91 * ASPECT))
    cap = _squash(cap, 161, 57)
    img.alpha_composite(cap.crop((0, 0, 128, 57)), (pieces[4].x, pieces[4].y))
    img.alpha_composite(cap.crop((128, 0, 161, 57)), (pieces[4].x, pieces[4].y + 64))


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
