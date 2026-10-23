"""Retro Toolbox-branded screens for Ken Griffey Jr. Presents Major League
Baseball (SNES): the stadium behind the title and the front-end menus, and the
licence screen at power-on, the library's `image_slots`. The art names the
update by its season ('2026'), never as one of Nintendo's games.

Sizes and guides come from the library's `kgj_mlb_snes.screens.SLOTS` at run
time. The game draws nearly all of the stadium over: its logo, Griffey, PUSH
START, the menu box, the season result text and the copyright line. So the
stadium stays a stadium (crowd, outfield wall, warning track, grass), in the
app's colours, and the update's mark sits in the one corner left clear, on the
grass at the bottom left. It has 30 colours and 256 tiles: flat bands and
patterns that repeat every 8 or 16 pixels.
"""
from iss_art import DEEP, LIGHT, PURPLE, _logo, _text, _vertical, render_slots, season_mark, splash

PACKAGE = 'kgj_mlb_snes'

GRASS = (46, 120, 56, 255)
STRIPE = (56, 136, 64, 255)
DIRT = (176, 120, 72, 255)
CROWD = ((74, 58, 120, 255), (120, 104, 168, 255))

#: (x, y, w, h) of what each painter draws beyond its background; the guides
#: the game draws over must stay clear of them (checked by the packaging test).
CONTENT = {
    'title': [(2, 178, 92, 26)],
    'boot': [],  # the whole screen is the picture's
}


def _mark(season):
    """'2026': the MLB season, whatever the rosters file calls its league."""
    return season_mark('MLB', season, 'BASEBALL')


def _title(img, league, season, slot):
    """Crowd, outfield wall, warning track and grass, as the cartridge's
    stadium is laid out, with the app's logo and the season on the grass."""
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, img.width, 47), fill=DEEP)
    for row, y in enumerate(range(4, 46, 6)):  # the crowd: heads in rows
        for x in range((row % 2) * 4, img.width, 8):
            draw.ellipse((x, y, x + 4, y + 4), fill=CROWD[row % 2])
    draw.rectangle((0, 48, img.width, 51), fill=LIGHT)  # the wall's padding
    _vertical(img, 52, 168, PURPLE, DEEP)
    draw.rectangle((0, 168, img.width, 175), fill=DIRT)
    draw.rectangle((0, 176, img.width, img.height), fill=GRASS)
    for x in range(0, img.width, 32):  # mown stripes
        draw.rectangle((x, 176, x + 15, img.height), fill=STRIPE)
    x, y, w, h = CONTENT['title'][0]
    _logo(img, x + h // 2, y + h // 2, h)
    rest = w - h - 2
    _text(img, x + h + 2 + rest // 2, y + 8, _mark(season), 16, max_w=rest)
    _text(img, x + h + 2 + rest // 2, y + 20, 'ROSTERS', 9, fill=LIGHT, stroke=DEEP, max_w=rest)


def _boot(img, league, season, slot):
    splash(img, _mark(season))


_PAINTERS = {'title': _title, 'boot': _boot}


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every KGJ slot; returns {slot: path}."""
    return render_slots(PACKAGE, _PAINTERS, league, season, out_dir)
