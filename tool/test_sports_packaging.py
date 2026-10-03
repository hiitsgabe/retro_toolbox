"""`python3 tool/test_sports_packaging.py` — output packaging for sports patches.

The output must mirror the input: a zip comes back as a zip, a loose
.cue/.bin set comes back as the full set, every file renamed to
"<label> - <game base>..." with the .cue pointing at the renamed tracks.
"""
import os
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python_app'))
import main  # noqa: E402

CUE = 'FILE "Game (Track 1).bin" BINARY\n  TRACK 01 MODE2/2352\nFILE "Game (Track 2).bin" BINARY\n  TRACK 02 AUDIO\n'


class FakePatcher:
    def patch(self, rom_path, output_path, rosters, on_progress):
        data = open(rom_path, 'rb').read()
        open(output_path, 'wb').write(data + b'PATCHED')

        class R:
            pass
        r = R()
        r.output_path = str(output_path)
        return r


def _disc(d):
    open(os.path.join(d, 'Game (Track 1).bin'), 'wb').write(b'data' * 10)
    open(os.path.join(d, 'Game (Track 2).bin'), 'wb').write(b'aud')
    open(os.path.join(d, 'Game.cue'), 'w').write(CUE)
    open(os.path.join(d, 'Other.bin'), 'wb').write(b'x')


def run(rom, out_dir, label='Liga A/B 2026'):
    return main._patch_with_packaging(FakePatcher(), rom, out_dir, label, lambda _rom: [], None)


def test_loose_disc():
    src, out = tempfile.mkdtemp(), tempfile.mkdtemp()
    _disc(src)
    res = run(os.path.join(src, 'Game.cue'), out)
    p = 'Liga A-B 2026 - Game'
    assert sorted(os.listdir(out)) == sorted([f'{p} (Track 1).bin', f'{p} (Track 2).bin', f'{p}.cue']), os.listdir(out)
    assert open(os.path.join(out, f'{p} (Track 1).bin'), 'rb').read().endswith(b'PATCHED')
    assert open(os.path.join(out, f'{p} (Track 2).bin'), 'rb').read() == b'aud'
    cue = open(os.path.join(out, f'{p}.cue')).read()
    assert f'FILE "{p} (Track 1).bin"' in cue and f'FILE "{p} (Track 2).bin"' in cue, cue
    assert res.output_path == os.path.join(out, f'{p} (Track 1).bin')


def test_rerun_in_same_folder_ignores_previous_output():
    src = tempfile.mkdtemp()
    _disc(src)
    run(os.path.join(src, 'Game (Track 1).bin'), src)
    run(os.path.join(src, 'Game (Track 1).bin'), src, label='Liga 2027')
    assert 'Liga 2027 - Game (Track 2).bin' in os.listdir(src)
    assert not any('Liga 2027 - Liga' in f for f in os.listdir(src)), os.listdir(src)


def test_zip_in_zip_out():
    src, out = tempfile.mkdtemp(), tempfile.mkdtemp()
    _disc(src)
    z = os.path.join(src, 'Game.zip')
    with zipfile.ZipFile(z, 'w') as zf:
        for n in ('Game (Track 1).bin', 'Game (Track 2).bin', 'Game.cue'):
            zf.write(os.path.join(src, n), n)
    res = run(z, out)
    p = 'Liga A-B 2026 - Game'
    assert os.listdir(out) == [f'{p}.zip'], os.listdir(out)
    assert res.output_path == os.path.join(out, f'{p}.zip')
    with zipfile.ZipFile(res.output_path) as zf:
        assert sorted(zf.namelist()) == sorted([f'{p} (Track 1).bin', f'{p} (Track 2).bin', f'{p}.cue']), zf.namelist()
        assert zf.read(f'{p} (Track 1).bin').endswith(b'PATCHED')
        assert f'FILE "{p} (Track 2).bin"' in zf.read(f'{p}.cue').decode()


def test_single_image():
    src, out = tempfile.mkdtemp(), tempfile.mkdtemp()
    open(os.path.join(src, 'Cart.sfc'), 'wb').write(b'rom')
    res = run(os.path.join(src, 'Cart.sfc'), out, label='Liga 2026')
    assert os.listdir(out) == ['Liga 2026 - Cart.sfc'], os.listdir(out)
    assert res.output_path == os.path.join(out, 'Liga 2026 - Cart.sfc')


def test_roster_counts_read_from_the_actual_rom():
    """A game declaring roster_counts gets them from analyze_rom on the image."""
    class Info:
        extra = {'roster_counts': [(2, 12, 7)]}

    class P:
        def analyze_rom(self, rom):
            assert str(rom).endswith('Cart.sfc')
            return Info()

        def map_rosters(self, data, slot_mapping, *, roster_counts=None):
            return roster_counts

    class Plain:
        def map_rosters(self, data, slot_mapping):
            return 'plain'

    assert main._map_rosters(P(), None, None, '/x/Cart.sfc') == [(2, 12, 7)]
    assert main._map_rosters(Plain(), None, None, '/x/Cart.sfc') == 'plain'


def test_build_patcher_hands_bundled_assets_only_to_patchers_that_take_them():
    class WithAssets:
        def __init__(self, cache_dir, *, provider=None, assets_dir=None):
            self.assets_dir = assets_dir

    class Plain:
        def __init__(self, cache_dir, *, provider=None):
            pass

    p = main._build_patcher(WithAssets, '/c', 'espn')
    assert os.path.isfile(os.path.join(p.assets_dir, 'w202-english.ppf')), p.assets_dir
    main._build_patcher(Plain, '/c', 'espn')  # must not raise


def test_options_reach_patch():
    seen = {}

    class P(FakePatcher):
        def patch(self, rom_path, output_path, rosters, on_progress, **options):
            seen.update(options)
            return super().patch(rom_path, output_path, rosters, on_progress)

    src, out = tempfile.mkdtemp(), tempfile.mkdtemp()
    open(os.path.join(src, 'Cart.sfc'), 'wb').write(b'rom')
    main._patch_with_packaging(P(), os.path.join(src, 'Cart.sfc'), out, 'L', lambda _r: [], None, {'language': 'pt'})
    assert seen == {'language': 'pt'}


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn()
            print('ok', name)
