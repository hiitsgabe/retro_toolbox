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

    class Ordered:
        def map_rosters(self, data, slot_mapping, *, order_as_given=False):
            return order_as_given

    assert main._map_rosters(P(), None, None, '/x/Cart.sfc') == [(2, 12, 7)]
    assert main._map_rosters(Plain(), None, None, '/x/Cart.sfc') == 'plain'
    # The editor's order is the ROM order: ask for it wherever it's supported.
    assert main._map_rosters(Ordered(), None, None, '/x/Cart.sfc') is True


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


def test_patch_options_follow_the_patcher_capabilities():
    class Visual:
        languages = ('en', 'pt')
        supports_logos = True
        supports_blank_unused = True
        image_slots = ('title', 'menu')
        supports_kits = True

    class Plain:
        pass

    job = {'language': 'pt', 'logos': False, 'blank_unused': True,
           'images': {'title': '/a.png', 'menu': ''}, 'kits': {'3': {'home': {'template': 1}, 'away': None}}}
    team_kits = {3: {'home': KIT, 'away': KIT}, 7: {'home': KIT, 'away': None}}
    assert main._patch_options(job, Visual(), team_kits) == {
        'language': 'pt', 'logos': False, 'blank_unused': True, 'images': {'title': '/a.png'},
        # The job's per-slot kits (string keys from JSON) override the teams' own.
        'kits': {3: {'home': {'template': 1}, 'away': None}, 7: {'home': KIT, 'away': None}}}
    # A patcher without the capabilities never sees the keywords.
    assert main._patch_options(job, Plain(), team_kits) == {}
    # Absent flags are left to the library's defaults, kits included.
    assert main._patch_options({}, Visual()) == {}


KIT = {'shirt': '#ff0000', 'secondary': '#ffffff', 'pattern': 'stripes',
       'shorts': '#0000ff', 'socks': '#ff0000', 'sleeves': None}


def test_list_patchers_payload_reads_the_capabilities_with_defaults():
    class Base:
        def kit_templates(self, rom_path):
            return []

    class Full(Base):
        languages = ('en',)
        supports_logos = True
        supports_blank_unused = True
        image_slots = ('title',)
        supports_kits = True
        supports_nationals = True
        national_slot_base = 1000
        slot_groups = (('english', 0, 20), ('other', 98, 36))

        def kit_templates(self, rom_path):
            return ['t']

    class Old(Base):  # an older library: none of the new attributes
        supports_logos = True

    assert main._capabilities(Full, Base) == {
        'languages': ['en'], 'supports_logos': True, 'supports_blank_unused': True, 'image_slots': ['title'],
        'supports_kits': True, 'kit_templates': True, 'supports_nationals': True, 'national_slot_base': 1000,
        'slot_groups': [{'name': 'english', 'first': 0, 'count': 20}, {'name': 'other', 'first': 98, 'count': 36}],
        'multi_league': True}
    assert main._capabilities(Old, Base) == {
        'languages': [], 'supports_logos': True, 'supports_blank_unused': False, 'image_slots': [],
        'supports_kits': False, 'kit_templates': False, 'supports_nationals': False, 'national_slot_base': None,
        'slot_groups': [], 'multi_league': False}


class FakeRrp:
    """The slice of retro_roster_patcher the roster loading touches."""
    class SlotMapping:
        def __init__(self, slot_index, team_id):
            self.slot_index, self.team_id = slot_index, team_id

    class ApiError(Exception):
        pass

    class TeamRoster:
        def __init__(self, team):
            self.team, self.players, self.extra, self.error = team, [], {}, None

    class LeagueData:
        def __init__(self, league, teams):
            self.league, self.teams = league, teams

    @staticmethod
    def league_data_from_dict(d):
        class Obj:
            def __init__(self, **kw):
                self.__dict__.update(kw)
        return Obj(league=Obj(season=d['league']['season']),
                   teams=[Obj(team=Obj(id=t['team']['id']), extra=t.get('extra', {})) for t in d['teams']])


class Mapped:
    def __init__(self, teams):
        self.teams = teams

    def merge(self, other):
        return Mapped({**self.teams, **other.teams})


class MapByMapping:
    """map_rosters as the library does it: each mapping entry's team into its slot."""
    def map_rosters(self, data, slot_mapping):
        if not slot_mapping:
            raise RuntimeError('requires a slot mapping')
        by_id = {t.team.id: t for t in data.teams}
        return Mapped({m.slot_index: by_id[m.team_id].team.id for m in slot_mapping})


def _roster_file(d, name, season, teams):
    import json
    path = os.path.join(d, name)
    with open(path, 'w') as f:
        json.dump({'league': {'season': season}, 'teams': teams}, f)
    return path


def test_multi_file_rosters_are_sliced_by_team_and_merged():
    d = tempfile.mkdtemp()
    a = _roster_file(d, 'a.json', 2026, [{'team': {'id': 1}, 'extra': {'kits': {'home': KIT, 'away': None}}}, {'team': {'id': 2}}])
    b = _roster_file(d, 'b.json', 2025, [{'team': {'id': 3}, 'extra': {'kits': {'home': KIT, 'away': KIT}}}])
    mapping = [FakeRrp.SlotMapping(0, 1), FakeRrp.SlotMapping(1, 2), FakeRrp.SlotMapping(20, 3)]
    sources = main._load_rosters({'rosters_files': [{'file': a, 'first_slot': 0}, {'file': b}]}, mapping, FakeRrp)
    # Each file gets only the mapping entries naming its own teams.
    assert [[m.slot_index for m in m_] for _, m_ in sources] == [[0, 1], [20]]
    assert sources[0][0].league.season == 2026
    assert main._merge_rosters(MapByMapping(), sources, '/x.iso').teams == {0: 1, 1: 2, 20: 3}
    # The editor's kit picks land on the slot their team maps to.
    assert main._team_kits(sources) == {0: {'home': KIT, 'away': None}, 20: {'home': KIT, 'away': KIT}}
    # A single file is the old job, untouched: one source, whole mapping.
    single = main._load_rosters({'rosters_file': a}, mapping[:2], FakeRrp)
    assert len(single) == 1 and len(single[0][1]) == 2
    assert main._load_rosters({'rosters_file': a}, None, FakeRrp)[0][1] is None
    assert main._team_kits(main._load_rosters({'rosters_file': a}, None, FakeRrp)) == {}
    try:
        main._load_rosters({'rosters_files': [{'file': a}, {'file': b}]}, None, FakeRrp)
        assert False, 'several files need a mapping'
    except ValueError:
        pass


def test_rosters_files_slot_ranges_and_unmapped_files():
    SM = FakeRrp.SlotMapping
    d = tempfile.mkdtemp()
    a = _roster_file(d, 'a.json', 2026, [{'team': {'id': 1}}, {'team': {'id': 2}, 'extra': {'kits': {'home': KIT, 'away': None}}}])
    b = _roster_file(d, 'b.json', 2026, [{'team': {'id': 2}}, {'team': {'id': 3}}])
    mapping = [SM(0, 1), SM(1, 2), SM(20, 2), SM(21, 3)]
    job = {'rosters_files': [{'file': a, 'first_slot': 0, 'count': 20}, {'file': b, 'first_slot': 20, 'count': 20}]}
    sources = main._load_rosters(job, mapping, FakeRrp)
    # Ranged entries take their slot range: team 2 is in both leagues and lands in both.
    assert [[m.slot_index for m in m_] for _, m_ in sources] == [[0, 1], [20, 21]]
    assert main._merge_rosters(MapByMapping(), sources, '/x').teams == {0: 1, 1: 2, 20: 2, 21: 3}
    # Its kit picks follow it only where that file carries them.
    assert main._team_kits(sources) == {1: {'home': KIT, 'away': None}}
    # A file none of whose teams are mapped is skipped, not a failed patch.
    c = _roster_file(d, 'c.json', 2026, [{'team': {'id': 9}}])
    sources = main._load_rosters({'rosters_files': [{'file': a}, {'file': c}]}, mapping[:2], FakeRrp)
    assert sources[1][1] == []
    assert main._merge_rosters(MapByMapping(), sources, '/x').teams == {0: 1, 1: 2}
    try:
        main._merge_rosters(MapByMapping(), [sources[1]], '/x')
        assert False, 'nothing mapped must be reported'
    except ValueError as e:
        assert 'no mapped team' in str(e)


def test_fetch_nationals_orders_each_squad():
    class Obj:
        def __init__(self, **kw):
            self.__dict__.update(kw)

    class Api:
        def get_leagues(self, id, season):
            return iter([Obj(id=id, season=season)])

        def get_teams(self, league_id, season):
            return [Obj(id=1, name='A'), Obj(id=2, name='B'), Obj(id=3, name='C')]

        def get_squad(self, team_id, season):
            if team_id == 3:
                raise FakeRrp.ApiError('down')
            return ['sub', 'starter']

        def get_lineup(self, team_id, league_id):
            return {'xi': ['starter']}

    class P:
        api = Api()

        def national_slot_map(self, rom, data):
            assert len(data.teams) == 3
            return [FakeRrp.SlotMapping(1000, 1), FakeRrp.SlotMapping(1001, 3)]

        def suggest_squad_order(self, roster):
            return list(reversed(roster.players))

    data, mapping = main._fetch_nationals(P(), '/x.bin', 2026, FakeRrp)
    # Only the mapped teams are fetched, each in fielding order (starters first).
    assert [t.team.id for t in data.teams] == [1, 3] and [m.slot_index for m in mapping] == [1000, 1001]
    assert data.teams[0].players == ['starter', 'sub'] and data.teams[0].extra == {'lineup': {'xi': ['starter']}}
    assert data.teams[1].error == 'down' and data.teams[1].players == []


def test_kit_previews_default_from_the_team_colours():
    class Kits:
        @staticmethod
        def default_kits(team):
            return ('home', team.color, team.alternate_color), ('away', team.alternate_color)

        @staticmethod
        def render_kit(spec):
            return b'FLAT:' + repr(spec).encode()

    class Team:
        def __init__(self, **kw):
            self.__dict__.update(kw)

    colours = {'1_home': ['#ff0000', '#ffffff'], '1_away': ['#ff0000', '#ffffff'], '2_home': ['', '#000000'], '3_home': ['#00ff00']}
    default = main._default_kit_specs(colours, {'1_away': 'away'}, Kits, Team)
    out = tempfile.mkdtemp()
    written = main._kit_previews({'1_home': None, '1_away': None, '2_home': None, '3_home': None, '4_home': None}, out, Kits, None, default)
    # The default follows the colours and the side; no first colour or no colours, no preview.
    assert sorted(written) == ['1_away', '1_home', '3_home']
    assert open(written['1_home'], 'rb').read() == b"FLAT:('home', '#ff0000', '#ffffff')"
    assert open(written['1_away'], 'rb').read() == b"FLAT:('away', '#ffffff')"
    assert open(written['3_home'], 'rb').read() == b"FLAT:('home', '#00ff00', '')"
    assert main._default_kit_specs({}, {}, Kits, Team) is None
    assert main._default_kit_specs(colours, {}, object(), Team) is None  # an older library


def test_kit_previews_job_writes_a_png_per_kit():
    class Kits:
        class KitSpec:
            @staticmethod
            def from_dict(d):
                return ('spec', d['pattern'])

        @staticmethod
        def kit_from_image(png):
            return ('image', png)

        @staticmethod
        def render_kit(spec):
            return b'PNG:' + repr(spec).encode()

    src, out = tempfile.mkdtemp(), os.path.join(tempfile.mkdtemp(), 'previews')
    pick = os.path.join(src, 'pick.png')
    open(pick, 'wb').write(b'picked')
    written = main._kit_previews(
        {'7_home': KIT, '7_away': {'image': pick}, '8_home': {'template': 2}, '8_away': None}, out, Kits)
    assert written == {'7_home': os.path.join(out, '7_home.png'), '7_away': os.path.join(out, '7_away.png')}
    assert open(written['7_home'], 'rb').read() == b"PNG:('spec', 'stripes')"
    # A picked image is previewed as the spec the game will get, and kept beside it.
    assert open(written['7_away'], 'rb').read() == b"PNG:('image', b'picked')"
    assert open(os.path.join(out, '7_away_source.png'), 'rb').read() == b'picked'
    assert sorted(os.listdir(out)) == ['7_away.png', '7_away_source.png', '7_home.png']


def test_kit_previews_mount_on_the_player_when_the_game_draws_it():
    class Kits:
        class KitSpec:
            @staticmethod
            def from_dict(d):
                return ('spec', d['pattern'])

        @staticmethod
        def kit_from_image(png):
            return ('image', png)

        @staticmethod
        def render_kit(spec):
            return b'FLAT:' + repr(spec).encode()

    calls = []

    class We:
        def kit_preview_png(self, rom, tex, which, kit):
            calls.append((str(rom), tex, which, kit))
            return b'MOUNTED:' + repr(kit).encode()

    class Plain:
        pass

    src, out = tempfile.mkdtemp(), tempfile.mkdtemp()
    pick = os.path.join(src, 'pick.png')
    open(pick, 'wb').write(b'picked')
    kits = {'7_home': KIT, '7_away': {'image': pick}, '8_home': {'template': 2}, '8_away': None, '9_home': KIT}
    slots, which = {'7_home': 7, '7_away': 7, '8_home': 8, '8_away': 8}, {'7_away': 'away', '8_away': 'away'}
    # No ROM, or a game without the method: nothing is mounted.
    assert main._mounted_previews(We(), None, slots, which) is None
    assert main._mounted_previews(Plain(), '/d/we.bin', slots, which) is None
    mounted = main._mounted_previews(We(), '/d/we.bin', slots, which)
    written = main._kit_previews(kits, out, Kits, mounted)
    # Every keyed kit kind is mounted, None and templates included; the unkeyed one is drawn flat.
    assert sorted(written) == ['7_away', '7_home', '8_away', '8_home', '9_home']
    assert calls == [('/d/we.bin', 70, 'home', KIT), ('/d/we.bin', 70, 'away', {'image': pick}),
                     ('/d/we.bin', 71, 'home', {'template': 2}), ('/d/we.bin', 71, 'away', None)]
    assert open(written['8_away'], 'rb').read() == b'MOUNTED:None'
    assert open(written['9_home'], 'rb').read() == b"FLAT:('spec', 'stripes')"
    assert open(os.path.join(out, '7_away_source.png'), 'rb').read() == b'picked'


def test_default_images_dispatch_by_game():
    import types
    calls = []
    pes = types.ModuleType('pes_art')
    pes.render_default_images = lambda league, season, out: calls.append(('pes', league, season, out)) or {'title': 't'}
    we = types.ModuleType('default_art')
    we.render_default_images = lambda game, league, season, out: calls.append((game, league)) or {'boot': 'b'}
    saved = {k: sys.modules.get(k) for k in ('pes_art', 'default_art')}
    sys.modules.update({'pes_art': pes, 'default_art': we})
    try:
        assert main._render_default_images('pes2013-ps2', 'Liga', 2026, '/o') == {'title': 't'}
        assert main._render_default_images('we2002', 'Liga', 2026, '/o') == {'boot': 'b'}
        assert main._render_default_images('nhl94', 'Liga', 2026, '/o') == {'boot': 'b'}  # default_art decides
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v
    assert calls == [('pes', 'Liga', 2026, '/o'), ('we2002', 'Liga'), ('nhl94', 'Liga')]


def test_assets_with_logos_copies_the_bundle_and_adds_the_overrides():
    base, logos = tempfile.mkdtemp(), tempfile.mkdtemp()
    open(os.path.join(base, 'w202-english.ppf'), 'wb').write(b'ppf')
    open(os.path.join(logos, 'x.png'), 'wb').write(b'png')
    assert main._assets_with_logos(base, {}) == base
    d = main._assets_with_logos(base, {'359': os.path.join(logos, 'x.png')})
    assert d != base
    assert open(os.path.join(d, 'w202-english.ppf'), 'rb').read() == b'ppf'
    assert open(os.path.join(d, 'logos', '359.png'), 'rb').read() == b'png'


def test_with_data_file_extracts_a_zip_and_cleans_up():
    src = tempfile.mkdtemp()
    _disc(src)
    z = os.path.join(src, 'Game.zip')
    with zipfile.ZipFile(z, 'w') as zf:
        for n in ('Game (Track 1).bin', 'Game (Track 2).bin', 'Game.cue'):
            zf.write(os.path.join(src, n), n)
    path, cleanup = main._with_data_file(z)
    assert path.endswith('Game (Track 1).bin') and os.path.isfile(path)
    cleanup()
    assert not os.path.exists(path)
    # A picked .cue is text: the image is its first data track.
    plain, cleanup = main._with_data_file(os.path.join(src, 'Game.cue'))
    assert plain == os.path.join(src, 'Game (Track 1).bin')
    cleanup()
    bare, _ = main._with_data_file(os.path.join(src, 'Game (Track 1).bin'))
    assert bare == os.path.join(src, 'Game (Track 1).bin')


def test_templates_zip_from_stand_in_slots():
    import io
    import templates
    from PIL import Image

    class Obj:
        def __init__(self, **kw):
            self.__dict__.update(kw)

    pieces = [Obj(x=0, y=0, w=64, h=64, clear=False), Obj(x=64, y=0, w=64, h=64, clear=True),
              Obj(x=0, y=64, w=128, h=64, clear=False)]
    plain = Obj(width=128, height=128, pieces=pieces)
    guided = Obj(width=128, height=128, pieces=pieces, guides=(Obj(x=8, y=8, w=100, h=20, label='ball'),))
    # Pieces the game clears are not guides; the library's own guides win when present.
    assert templates.we2002_guides(plain) == [(0, 0, 64, 64, 'piece 0'), (0, 64, 128, 64, 'piece 2')]
    assert templates.we2002_guides(guided) == [(8, 8, 100, 20, 'ball')]

    files = templates.we2002_screens({'title': plain, 'menu': guided}) + [templates.kit_photo_guide()] + templates.pes_screens()
    names = [n for n, _, _ in files]
    assert names == ['title.png', 'menu.png', 'kit-photo-guide.png', 'title.png', 'menu.png', 'loading.png', 'match.png']
    im = Image.open(io.BytesIO(files[0][1]))
    assert im.size == (128, 128)
    assert im.getpixel((0, 0)) == templates.RED and im.getpixel((63, 63)) == templates.RED  # box edges
    assert im.getpixel((100, 32)) == templates.GREY  # the cleared piece stays grey
    assert Image.open(io.BytesIO(files[2][1])).size == (96, 128)
    assert Image.open(io.BytesIO(files[5][1])).size == (256, 256)
    # The screens zip carries the photo guide for a kits game, never a kit page (that needs the disc).
    assert [n for n, _, _ in templates.files_for('pes2013-ps2', True)] == ['title.png', 'menu.png', 'loading.png', 'match.png', 'kit-photo-guide.png']
    assert [n for n, _, _ in templates.files_for('pes2013-ps2', False)] == ['title.png', 'menu.png', 'loading.png', 'match.png']

    out = tempfile.mkdtemp()
    path, listed = templates.write_zip(out, 'we2002-templates', files[:3])
    assert path == os.path.join(out, 'we2002-templates.zip')
    assert listed == ['title.png', 'menu.png', 'kit-photo-guide.png', 'README.txt']
    with zipfile.ZipFile(path) as zf:
        assert sorted(zf.namelist()) == sorted(listed)
        readme = zf.read('README.txt').decode()
    for name in listed[:-1]:
        assert name in readme
    assert '128x128' in readme and '96x128' in readme and 'red lines are guides' in readme
    try:
        templates.files_for('nhl94-snes', False)
        assert False, 'a game without templates must say so'
    except ValueError:
        pass


def test_kit_template_zip_holds_the_current_pages_when_the_library_has_them():
    import io
    import templates
    from PIL import Image

    calls = []

    class WithPages:
        def kit_page_png(self, rom, slot, which='home', *, template=None):
            calls.append((str(rom), slot, which, template))
            if which == 'away':
                raise RuntimeError('no away page')  # one failing page never sinks the zip
            return templates.render(128, 256, [(0, 0, 128, 140, 'shirt')])

    class WithPreviews(WithPages):
        def kit_preview_png(self, rom, tex, which, kit=None):
            calls.append(('preview', tex, which, kit))
            return templates.render(96, 128, [])

    class Older:
        pass

    import types
    lib_calls = []
    fake_lib = types.SimpleNamespace(
        KitSpec=lambda **kw: ('spec', kw['pattern']),
        read_tex_files=lambda rom: lib_calls.append(('read', rom)) or {70: b'tex70', 3: b'tex3'},
        apply_spec=lambda tex, which, spec: lib_calls.append(('apply', tex, which, spec)) or b'painted',
        page_png=lambda tex, which, guides: lib_calls.append(('page', tex, which, guides)) or templates.render(128, 256, []),
        template_preview=lambda tex, which: lib_calls.append(('mounted', tex, which)) or templates.render(96, 128, []))
    real_lib = templates._we2002_lib
    templates._we2002_lib = lambda: None  # the library of today: no texture functions
    try:
        # A mapped slot below 32 reads its Master League copy; higher slots are national rows.
        assert templates.we2002_tex(7) == 70 and templates.we2002_tex(40) == 40
        out = tempfile.mkdtemp()
        path, names = templates.build_kits('we2002', out, WithPages(), '/d/we.bin', 7)
        assert path == os.path.join(out, 'we2002-kit-template-slot7.zip')
        assert names == ['home.png', 'kit-photo-guide.png', 'README.txt']
        assert calls == [('/d/we.bin', 70, 'home', None), ('/d/we.bin', 70, 'away', None)]  # ML slot 7 wears TEX 70
        with zipfile.ZipFile(path) as zf:
            assert Image.open(io.BytesIO(zf.read('home.png'))).size == (128, 256)
            readme = zf.read('README.txt').decode()
        assert readme.startswith('Paint over home.png / away.png keeping the exact size (128x256 pixels)')
        assert 'read as a kit photo' in readme and 'home.png\nThe current home kit texture page of slot 7' in readme
        assert 'home-preview.png shows how home.png looks on the player' in readme
        # A template page instead of the slot's own, one side only.
        calls.clear()
        _, names = templates.build_kits('we2002', out, WithPages(), '/d/we.bin', 7, which='home', template=3)
        assert calls == [('/d/we.bin', 70, 'home', 3)] and names[0] == 'home.png'
        # An older library (no kit_page_png): the guide and README still ship.
        _, names = templates.build_kits('we2002', out, Older(), '/d/we.bin', 0, which='away')
        assert names == ['kit-photo-guide.png', 'README.txt']

        # With everything exposed: mounted previews and the painted example pair.
        templates._we2002_lib = lambda: fake_lib
        calls.clear()
        _, names = templates.build_kits('we2002', out, WithPreviews(), '/d/we.bin', 7)
        assert names == ['home.png', 'home-preview.png', 'away-preview.png', 'example-page.png',
                         'example-preview.png', 'kit-photo-guide.png', 'README.txt'], names
        assert ('preview', 70, 'home', None) in calls and ('preview', 70, 'away', None) in calls
        assert lib_calls == [('read', '/d/we.bin'), ('apply', b'tex70', 'home', ('spec', 'stripes')),
                             ('page', b'painted', 'home', False), ('mounted', b'painted', 'home')], lib_calls
        # A template's example paints that design's TEX, for the side asked.
        lib_calls.clear()
        _, names = templates.build_kits('we2002', out, WithPreviews(), '/d/we.bin', 7, which='away', template=3)
        assert lib_calls[1] == ('apply', b'tex3', 'away', ('spec', 'stripes'))
        assert names == ['away-preview.png', 'example-page.png', 'example-preview.png', 'kit-photo-guide.png', 'README.txt']
    finally:
        templates._we2002_lib = real_lib
    # Without the library the PES pages are skipped the same way.
    assert templates.pes_kit_files('/d/pes.iso', 0, ['home']) == []
    # With it, a page ships only once the library knows the regions to box.
    reads = []

    class Reader:
        def __init__(self, rom):
            reads.append(rom)

        def load(self):
            return True

    def pes_lib(regions):
        return types.SimpleNamespace(
            kit_textures=types.SimpleNamespace(REGIONS=regions, read_kit_png=lambda r, s, w: templates.render(512, 256, [])),
            kits=types.SimpleNamespace(HOME=1, AWAY=3), RomReader=Reader)
    real_pes = templates._pes_lib
    try:
        templates._pes_lib = lambda: pes_lib({})
        assert templates.pes_kit_files('/d/pes.iso', 0, ['home']) == [] and reads == []
        templates._pes_lib = lambda: pes_lib({'shirt': (0, 0, 64, 64)})
        files = templates.pes_kit_files('/d/pes.iso', 0, ['home', 'away'])
        assert [n for n, _, _ in files] == ['home.png', 'away.png'] and reads == ['/d/pes.iso']
        assert Image.open(io.BytesIO(files[0][1])).getpixel((0, 0)) == templates.RED
    finally:
        templates._pes_lib = real_pes
    # outline() boxes a page with the library's regions and leaves it alone without.
    page = templates.render(32, 32, [])
    assert templates.outline(page, {}) is page
    boxed = Image.open(io.BytesIO(templates.outline(page, {'shirt': (4, 4, 20, 20)})))
    assert boxed.getpixel((4, 4)) == templates.RED and boxed.getpixel((1, 1)) == templates.GREY


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn()
            print('ok', name)
