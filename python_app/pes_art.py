"""Retro Toolbox-branded screens for PES 2013 (PS2): the title, menu, loading
and match textures the library can replace.

Each slot is one full-screen texture, and the PS2 stretches the square texture
over the whole 4:3 frame, so on screen a texel is 4/3 wider than it is tall
(assumption from the texture sizes and the game's full-frame draws, Oct 2026;
if a slot ever shows at its own aspect, drop the squash for it). Each painter
therefore draws with square pixels on a 4:3 design canvas, which is then
resized to the slot's square and stretched back by the display. Backgrounds
are opaque deep purple: these textures are whole screens, nothing shows
through them. Text is white with the app's purple stroke, as in default_art.
"""
import os

_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rrp_assets')
LOGO = os.path.join(_ASSETS, 'logo.png')
FONT = os.path.join(_ASSETS, 'ChakraPetch-Bold.ttf')

WHITE = (255, 255, 255, 255)
PURPLE = (74, 43, 181, 255)
DEEP = (27, 15, 58, 255)

#: Texture side per slot: the library pastes a PNG centred without upscaling,
#: so each must be rendered at exactly this size.
SIZES = {'title': 512, 'menu': 512, 'loading': 256, 'match': 512}


def _fit(draw, text, box_w, box_h, start, stroke=2):
    """The largest font size (<= start) whose rendering of text fits box_w x box_h."""
    from PIL import ImageFont
    for size in range(start, 7, -1):
        f = ImageFont.truetype(FONT, size)
        l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
        if r - l <= box_w and b - t <= box_h:
            return f
    return ImageFont.truetype(FONT, 8)


def _lines(img, cx, lines, top, bottom, box_w=None):
    """Draw text lines centred on x=cx, stacked and centred between top and
    bottom; lines = [(text, max font size, max height)]."""
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
        draw.text((cx - w // 2 - l, y - t), text, font=f, fill=WHITE, stroke_width=2, stroke_fill=PURPLE)
        y += h + gap


def _logo(img, cx, cy, size, alpha=255):
    """Paste the logo, size px square, centred on (cx, cy), faded to alpha."""
    from PIL import Image
    logo = Image.open(LOGO).convert('RGBA').resize((size, size), Image.Resampling.LANCZOS)
    if alpha < 255:
        logo.putalpha(logo.getchannel('A').point(lambda a: a * alpha // 255))
    img.alpha_composite(logo, (cx - size // 2, cy - size // 2))


def _title(img, league, season):  # 512x384 design
    _logo(img, 256, 112, 168)
    _lines(img, 256, [('RETRO TOOLBOX', 46, 48), (league, 30, 32), (f'SEASON {season}', 24, 26)], 206, 374)


def _menu(img, league, season):  # 512x384 design, subtle: the menu draws over it
    _logo(img, 44, 40, 56)
    _lines(img, 44 + 32 + 150, [('RETRO TOOLBOX', 22, 24), (league, 16, 18)], 16, 64, box_w=300)
    _logo(img, 400, 300, 260, alpha=28)


def _loading(img, league, season):  # 256x192 design
    _logo(img, 128, 74, 100)
    _lines(img, 128, [(league, 20, 22), (f'SEASON {season}', 14, 16)], 130, 188)


def _match(img, league, season):  # 512x384 design: a dark field, the logo barely there
    _logo(img, 256, 192, 300, alpha=36)


_PAINTERS = {'title': _title, 'menu': _menu, 'loading': _loading, 'match': _match}


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every PES slot; returns {slot: path}."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    league = (league or 'Retro Toolbox').upper()
    written = {}
    for name, size in SIZES.items():
        img = Image.new('RGBA', (size, size * 3 // 4), DEEP)
        _PAINTERS[name](img, league, season)
        path = os.path.join(out_dir, f'{name}.png')
        img.resize((size, size), Image.Resampling.LANCZOS).save(path)
        written[name] = path
    return written


if __name__ == '__main__':
    import sys
    import tempfile
    out = render_default_images('Brasileirão Série A', 2026, sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp())
    from PIL import Image
    for name, path in out.items():
        im = Image.open(path)
        assert im.size == (SIZES[name], SIZES[name]), (name, im.size)
        assert im.getchannel('A').getextrema() == (255, 255), f'{name} is not opaque'
        print(name, im.size, path)
