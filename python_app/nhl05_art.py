"""Retro Toolbox-branded screens for NHL 2005 (PS2): the boot splash, title,
legal backdrop and menu arena the library can replace (its `image_slots`).
The art names the update by its season, never as one of EA's games.

Every slot is a 512x512 picture the PS2 stretches over its 640x448 screen,
so each is designed on a 640x448 canvas with square pixels and then resized.
The disc's own boot and title are light (the game draws its loading dots and
PRESS START over them), its legal and menu backdrops dark (white notice and
menu text), so the app's keep those tones. The painters share NHL 07's ice,
bands and lettering.

The boot screen is the one slot stored plain and RefPack-compressed, in
14,012 bytes: a gradient or resampling halo does not fit even at 32
colours, so its backdrop is flat and it is resized with a box filter
(13.5 KB at 256 colours against the retail disc, Oct 2026).
"""
import os

from nhl07_art import DEEP, LIGHT, PURPLE, UPDATE_LINE, WHITE, _band, _ice, _lines, _logo, _wordmark, season_mark

SCREEN = (640, 448)
SIZE = (512, 512)
SLOTS = ('boot', 'title', 'legal', 'menu')


def _boot(img, season):  # the game draws its loading dots at (248, 262) 144x24
    _band(img, 0, 64)
    _lines(img, 320, [('RETRO TOOLBOX', 30, 34)], 10, 54)
    _logo(img, 200, 165, 140)
    _wordmark(img, 290, 110, season_mark(season), 96)
    _lines(img, 320, [(UPDATE_LINE, 26, 28)], 300, 340, box_w=440, fill=PURPLE, stroke=WHITE)


def _title(img, season):  # the game writes PRESS START and the copyright at (150, 300) 340x60
    _band(img, 0, 64)
    _lines(img, 320, [('RETRO TOOLBOX', 30, 34)], 10, 54)
    _logo(img, 170, 170, 150)
    _wordmark(img, 270, 112, season_mark(season), 100)
    _lines(img, 320, [(UPDATE_LINE, 26, 28)], 250, 290, box_w=440, fill=PURPLE, stroke=WHITE)


def _legal(img, season):  # the notice covers (60, 60) 400x330: the right strip and the bottom are ours
    _logo(img, 550, 225, 150, alpha=90)
    _lines(img, 320, [(f'RETRO TOOLBOX  {season_mark(season)}  {UPDATE_LINE}', 20, 22)], 400, 440, box_w=600)


def _menu(img, season):  # the logo sits at (70, 50) 240x140, the items at (70, 200) 330x200, the photo from x 380
    _band(img, 0, 40)
    _lines(img, 190, [('RETRO TOOLBOX', 20, 22)], 2, 34, box_w=340)
    _lines(img, 200, [(f'{season_mark(season)}  {UPDATE_LINE}', 22, 24)], 404, 444, box_w=340)


#: Each slot's backdrop (what the game's text and dots sit on) and the marks
#: drawn over it, kept clear of every box the game draws (checked by the test).
def _flat(img):
    img.paste(LIGHT, (0, 0, img.width, img.height))


BACKDROPS = {'boot': _flat, 'title': _ice, 'legal': lambda img: None, 'menu': lambda img: None}
MARKS = {'boot': _boot, 'title': _title, 'legal': _legal, 'menu': _menu}


def paint(name, season, marks=True):
    """The slot's picture at SIZE: its backdrop and, unless marks is False, the logo and lettering."""
    from PIL import Image
    img = Image.new('RGBA', SCREEN, DEEP)
    BACKDROPS[name](img)
    if marks:
        MARKS[name](img, season)
    # ponytail: the boot's box filter keeps it inside its compressed slot; a sharper one does not fit
    return img.resize(SIZE, Image.Resampling.BOX if name == 'boot' else Image.Resampling.LANCZOS)


def render_default_images(league, season, out_dir):
    """Write `<out_dir>/<slot>.png` for every NHL 2005 slot; returns {slot: path}."""
    os.makedirs(out_dir, exist_ok=True)
    written = {}
    for name in SLOTS:
        path = os.path.join(out_dir, f'{name}.png')
        paint(name, season).save(path)
        written[name] = path
    return written


if __name__ == '__main__':
    import sys
    import tempfile
    out = render_default_images('NHL', 2025, sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp())
    from PIL import Image
    for name, path in out.items():
        im = Image.open(path)
        assert im.size == SIZE and im.getchannel('A').getextrema() == (255, 255), (name, im.size)
        print(name, im.size, path)
