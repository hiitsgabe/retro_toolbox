"""Retro Toolbox-branded screens for NHL '94 (Genesis): the title and Game
Setup's rink the library can replace (its `image_slots`). The art names the
update by its season ('26-27'), never as one of EA's games.

Sizes and guides come from the library's `nhl94_genesis.screens.SLOTS` at run
time. On the title the game keeps its NHL and NHLPA shields in the top
corners, its NHL HOCKEY 94 letters across the middle and its credits (black)
on the bottom lines, so the art puts the app's logo and the season between
the shields and the app's name between the letters and the credits, on dark
purple, with ice under the credits. Game Setup's options box is dithered, so
the rink shows through it: the SNES wallpaper's dark, calm motif. The
cartridge gives the title 526 tiles and the rink 240, so the art is flat
bands and a repeated motif.
"""
from iss_art import DEEP, PURPLE, _logo, _text, _vertical, render_slots
from nhl94_art import ICE_BOTTOM, ICE_TOP, _mark, _menu, _wordmark

PACKAGE = 'nhl94_genesis'

#: (x, y, w, h) of what each painter draws beyond its background; the guides
#: the game draws over must stay clear of them (checked by the packaging test).
CONTENT = {
    'title': [(60, 8, 136, 98), (8, 162, 240, 20)],
    'menu': [],
}


def _title(img, league, season, slot):
    """Dark purple down to the credits, the app's logo and the season between
    the shields, the app's name between the letters and the credits; ice
    under the credits, which the game draws in black."""
    credits = next(g for g in slot.guides if g.w == img.width)
    _vertical(img, 0, credits.y, DEEP, PURPLE)
    _vertical(img, credits.y, img.height, ICE_TOP, ICE_BOTTOM)
    (lx, ly, lw, lh), (tx, ty, tw, th) = CONTENT['title']
    _logo(img, lx + lw // 2, ly + 30, 52)
    _wordmark(img, (lx + 4, ly + 62, lw - 8, 32), _mark(season))
    _text(img, img.width // 2, ty + th // 2, 'RETRO TOOLBOX', 16, max_w=tw)


_PAINTERS = {'title': _title, 'menu': _menu}


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every NHL '94 (Genesis) slot; returns {slot: path}."""
    return render_slots(PACKAGE, _PAINTERS, league, season, out_dir)
