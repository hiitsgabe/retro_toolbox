"""Retro Toolbox-branded screens for NHL '94 (SNES): the EA SPORTS boot screen,
the title and the menu wallpaper the library can replace (its `image_slots`).
The art names the update by its season ('26-27'), never as one of EA's games.

Sizes and guides come from the library's `nhl94_snes.screens.SLOTS` at run
time. The title is the whole screen now: its top band shows first, the
credits and the NHL and NHLPA shields stay at the bottom, so the art keeps its
lines above them, and dark boards down both sides keep column 0 plain (it
shows alone before the reveal). The
wallpaper sits under every menu, whose text has no box behind it: a dark, calm
motif, and the two logo boxes plain. The cartridge has few tiles (255 on the
boot screen, 318 on the title, 355 on the wallpaper), so the art is flat
bands and a repeated motif.
"""
from iss_art import DEEP, LIGHT, PURPLE, WHITE, _logo, _text, _vertical, render_slots, season_mark, splash

PACKAGE = 'nhl94_snes'

ICE_TOP = (206, 222, 242, 255)
ICE_BOTTOM = (238, 244, 251, 255)
RINK_RED = (200, 40, 60, 255)
BOARDS = 4  # px of dark boards down each side of the title

#: (x, y, w, h) of what each painter draws beyond its background; the guides
#: the game draws over must stay clear of them (checked by the packaging test).
CONTENT = {
    'boot': [],  # the whole screen is the picture's
    'title': [(8, 4, 244, 72), (8, 84, 240, 72)],
    'menu': [],
}


def _mark(season):
    """'26-27': the NHL season, whatever the rosters file calls its league."""
    return season_mark('NHL', season, 'HOCKEY')


def _wordmark(img, box, text):
    """text in deep purple with a white outline, as large as box (x, y, w, h) holds, centred in it."""
    from PIL import ImageDraw
    from iss_art import _font
    x, y, w, h = box
    draw = ImageDraw.Draw(img)
    for size in range(h, 8, -1):
        l, t, r, b = draw.textbbox((0, 0), text, font=_font(size), stroke_width=3)
        if r - l <= w and b - t <= h:
            break
    draw.text((x + (w - (r - l)) // 2 - l, y + (h - (b - t)) // 2 - t), text, font=_font(size), fill=DEEP,
              stroke_width=3, stroke_fill=WHITE)


def _boot(img, league, season, slot):
    splash(img, _mark(season))


def _title(img, league, season, slot):
    """Ice in the band the game shows first, with the app's logo and the
    season; the app's name on purple under it; deep purple from the credits
    down, where the game's white lines and shields sit."""
    from PIL import ImageDraw
    band = next(g.h for g in slot.guides if g.x == 0 and g.y == 0 and g.w == img.width)
    low = min(g.y for g in slot.guides if g.y > 0)
    _vertical(img, 0, band, ICE_TOP, ICE_BOTTOM)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, band - 4, img.width, band - 1), fill=RINK_RED)  # the red line under the ice
    _vertical(img, band, low, PURPLE, DEEP)
    (lx, ly, lw, lh), (tx, ty, tw, th) = CONTENT['title']
    _logo(img, lx + lh // 2 + 4, ly + lh // 2, lh - 8)
    _wordmark(img, (lx + lh + 8, ly + 6, lw - lh - 12, lh - 12), _mark(season))
    _text(img, img.width // 2, ty + 22, 'RETRO TOOLBOX', 24, max_w=tw)
    _text(img, img.width // 2, ty + 50, 'UNOFFICIAL ROSTER UPDATE', 11, fill=LIGHT, stroke=DEEP, max_w=tw)
    # Column 0 shows alone for 4 s before the reveal, over the game's navy:
    # dark boards down both sides keep it plain there and frame the rink after.
    draw.rectangle((0, 0, BOARDS - 1, img.height), fill=DEEP)
    draw.rectangle((img.width - BOARDS, 0, img.width, img.height), fill=DEEP)


def _menu(img, league, season, slot):
    """A 64x64 motif repeated (few tiles): the app's logo, faint, on deep
    purple with a fine diagonal; the logo boxes (the square guides at the top)
    plain light, for the game's logos and portraits to sit on."""
    from PIL import Image, ImageDraw
    motif = Image.new('RGBA', (64, 64), DEEP)
    draw = ImageDraw.Draw(motif)
    for k in range(-64, 64, 16):
        draw.line((k, 64, k + 64, 0), fill=(36, 21, 74, 255), width=3)
    _logo(motif, 32, 32, 36, alpha=70)
    for y in range(0, img.height, 64):
        for x in range(0, img.width, 64):
            img.alpha_composite(motif, (x, y))
    draw = ImageDraw.Draw(img)
    for g in slot.guides:
        if g.w == g.h and g.y < 16:
            draw.rectangle((g.x, g.y, g.x + g.w - 1, g.y + g.h - 1), fill=LIGHT)


_PAINTERS = {'boot': _boot, 'title': _title, 'menu': _menu}


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every NHL '94 slot; returns {slot: path}."""
    return render_slots(PACKAGE, _PAINTERS, league, season, out_dir)
