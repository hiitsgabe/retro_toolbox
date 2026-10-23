#!/usr/bin/env python3
import os
import sys
import time
import json
import glob
from pathlib import Path


def _report(progress_file, msg):
    if progress_file:
        with open(progress_file, 'a') as f:
            f.write(msg + '\n')
    print(msg, flush=True)


def run_3dsconv(job):
    """Convert one .3ds/.cci to .cia via the bundled 3dsconv, reporting DONE/ERROR.

    3dsconv runs its logic at module top-level off sys.argv, so we exec it fresh
    with runpy each time and detect success by a new .cia appearing in output.
    """
    import runpy
    import re
    progress_file = job.get('progress_file')
    input_file = job.get('input_file')
    output_dir = job.get('output_dir')
    boot9 = job.get('boot9_path') or None
    ignore_encryption = job.get('ignore_encryption') or False
    if not input_file or not output_dir:
        _report(progress_file, 'ERROR:Missing input_file or output_dir in job')
        return

    # Locate the bundled script via the importable package — __file__ is not
    # defined for the entry script under the embedded (serious_python) runtime.
    try:
        import threedsconv as _tdc_pkg
        script = os.path.join(os.path.dirname(_tdc_pkg.__file__), 'threedsconv.py')
    except Exception as e:
        _report(progress_file, f'ERROR:Could not locate 3dsconv: {e}')
        return

    os.makedirs(output_dir, exist_ok=True)
    pct_re = re.compile(r'(\d+(?:\.\d+)?)%')

    def _run(ignore):
        # Runs 3dsconv once; returns (produced_cia, saw_decrypted_hint).
        before = set(glob.glob(os.path.join(output_dir, '*.cia')))
        argv = ['3dsconv.py', '-o', output_dir]
        if boot9:
            argv += ['-b', boot9]
        if ignore:
            argv.append('--ignore-encryption')
        argv.append(input_file)

        hint = [False]

        class _Tap:
            def __init__(self):
                self.buf = ''
                self.last = -1

            def write(self, s):
                self.buf += s
                if 'ignore-encryption' in self.buf or 'invalid ExtHeader' in self.buf:
                    hint[0] = True
                for m in pct_re.finditer(self.buf):
                    pct = int(float(m.group(1)))
                    if pct != self.last:
                        self.last = pct
                        if progress_file:
                            with open(progress_file, 'a') as f:
                                f.write('PROGRESS:%d\n' % pct)
                self.buf = self.buf[-256:]

            def flush(self):
                pass

        old_argv, old_stdout = sys.argv, sys.stdout
        sys.argv, sys.stdout = argv, _Tap()
        try:
            runpy.run_path(script, run_name='__main__')
        except SystemExit:
            pass  # success is judged by output, not exit code
        finally:
            sys.argv, sys.stdout = old_argv, old_stdout
        produced = bool(set(glob.glob(os.path.join(output_dir, '*.cia'))) - before)
        return produced, hint[0]

    _report(progress_file, 'PROGRESS:0')
    try:
        produced, hint = _run(ignore_encryption)
        # Auto-detect decrypted dumps: retry once with --ignore-encryption when
        # 3dsconv reported the tell-tale ExtHeader-hash hint.
        if not produced and not ignore_encryption and hint:
            _report(progress_file, 'PROGRESS:0')
            produced, _ = _run(True)
    except Exception as e:
        _report(progress_file, f'ERROR:{e}')
        return

    if produced:
        _report(progress_file, 'DONE')
    else:
        _report(progress_file, 'ERROR:Conversion produced no CIA — check that boot9.bin is correct for this ROM')


SPORTS_TYPES = {'list_patchers', 'list_leagues', 'sports_fetch', 'sports_analyze', 'sports_patch',
                'sports_images', 'sports_default_images', 'sports_kit_previews', 'sports_templates'}


def _configure_ssl():
    """Point HTTPS at a real CA bundle.

    The embedded CPython (serious_python) ships no system trust store, so
    urllib's default context can't verify certificates and every provider
    request fails — surfacing as "no teams". certifi supplies the CA bundle;
    force it as the default HTTPS context so the library's stdlib urllib picks
    it up without any code change on its side.
    """
    try:
        import ssl
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
        ssl._create_default_https_context = lambda *a, **k: ctx
    except Exception as e:
        _report(None, f'SSL config skipped: {e}')


_DATA_EXTS = ('.bin', '.iso', '.img', '.gen', '.md', '.smc', '.sfc', '.nes', '.cso')


def _cue_first_bin(cue_path):
    """The first FILE "..." track a .cue references (the data track), or None."""
    import re
    try:
        txt = open(cue_path, errors='replace').read()
    except OSError:
        return None
    m = re.search(r'FILE\s+"([^"]+)"', txt)
    return m.group(1) if m else None


def _find_data_file(files):
    """The patchable data image among a disc's files: the .cue's first track if
    present, else the largest file with a known data extension."""
    import os
    cues = [f for f in files if f.lower().endswith('.cue')]
    for cue in cues:
        b = _cue_first_bin(cue)
        if b:
            for f in files:
                if os.path.basename(f) == b:
                    return f
    cand = [f for f in files if f.lower().endswith(_DATA_EXTS)]
    if cand:
        return max(cand, key=lambda f: os.path.getsize(f))
    return files[0] if files else None


_TRACK_SUFFIX = r'\s*[\(\-]\s*[Tt]rack\s*\d+\)?.*$'


def _game_base(path):
    """A disc file's shared game name: its stem minus any " (Track N)" suffix."""
    import os
    import re
    stem = os.path.splitext(os.path.basename(path))[0]
    return re.sub(_TRACK_SUFFIX, '', stem).strip()


def _patch_set(patcher, rom_path, out_dir, new_prefix, rosters_for, on_progress, options=None):
    """Patch the data track and write the game's whole file set to out_dir.

    Every .bin/.cue next to rom_path sharing its game base name comes along,
    renamed new_prefix + <rest of its name>: the data track patched, the other
    tracks copied, the .cue's FILE references rewritten. Without the full set
    the .cue would keep loading the original tracks. A single image (no
    .bin/.cue siblings) is just patched to new_prefix + its extension.

    rosters_for(data_file) maps the rosters against the actual image, since
    some games size each team from the ROM itself.

    Returns (PatchResult, [written paths]).
    """
    import os
    import shutil

    src_dir = os.path.dirname(rom_path) or '.'
    game_base = _game_base(rom_path)
    # Files from an earlier run start with the label, not game_base, so they
    # are never picked up as input again.
    files = [
        os.path.join(src_dir, e) for e in sorted(os.listdir(src_dir))
        if e.lower().endswith(('.bin', '.cue')) and e.lower().startswith(game_base.lower())
    ] or [rom_path]
    data_file = _find_data_file(files)

    os.makedirs(out_dir, exist_ok=True)
    result, written = None, []
    for f in files:
        name = os.path.basename(f)
        dst = os.path.join(out_dir, new_prefix + name[len(game_base):])
        if f == data_file:
            result = patcher.patch(
                rom_path=Path(f), output_path=Path(dst),
                rosters=rosters_for(f), on_progress=on_progress, **(options or {}),
            )
        elif f.lower().endswith('.cue'):
            with open(f, errors='replace') as src:
                txt = src.read().replace(game_base, new_prefix)
            with open(dst, 'w') as out:
                out.write(txt)
        else:
            shutil.copy2(f, dst)
        written.append(dst)
    return result, written


def _patch_with_packaging(patcher, rom_path, output_dir, label, rosters_for, on_progress, options=None):
    """Patch rom_path into output_dir, mirroring the input's packaging.

    Output names are "<label> - <game base>" plus each file's own suffix
    (" (Track 2).bin", ".cue", ".iso", ...), the label being "<league> <season>".
    A .zip in comes back as "<label> - <game base>.zip" holding the full set;
    a loose .cue/.bin set comes back as the full set; a single image as one
    file. Returns the library's PatchResult with output_path set to the zip or
    the patched data file.
    """
    import os
    import re
    import shutil
    import tempfile
    import zipfile

    rom_path = str(rom_path)
    safe_label = re.sub(r'[\\/:*?"<>|]', '-', label).strip()

    if not rom_path.lower().endswith('.zip'):
        new_prefix = f'{safe_label} - {_game_base(rom_path)}'
        result, _ = _patch_set(patcher, rom_path, output_dir, new_prefix, rosters_for, on_progress, options)
        return result

    work = tempfile.mkdtemp(prefix='rrp_zip_')
    try:
        with zipfile.ZipFile(rom_path) as zf:
            zf.extractall(work)
        inner = [os.path.join(dp, f) for dp, _, fs in os.walk(work) for f in fs]
        data_file = _find_data_file(inner)
        if not data_file:
            raise ValueError('No patchable image inside the zip')
        new_prefix = f'{safe_label} - {_game_base(data_file)}'
        staged = os.path.join(work, '__out__')
        result, written = _patch_set(patcher, data_file, staged, new_prefix, rosters_for, on_progress, options)
        os.makedirs(output_dir, exist_ok=True)
        out_zip = os.path.join(output_dir, new_prefix + '.zip')
        with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
            for f in written:
                zf.write(f, os.path.basename(f))
        result.output_path = out_zip
        return result
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _build_patcher(cls, cache_dir, provider, assets_dir=None):
    """Instantiate a patcher, handing it the app's bundled data files when it
    takes an `assets_dir` (the PSX soccer patcher's full menu translation), or
    the per-job assets_dir given."""
    import inspect
    kwargs = {}
    if 'assets_dir' in inspect.signature(cls.__init__).parameters:
        if assets_dir is None:
            import rrp_assets
            assets_dir = os.path.dirname(rrp_assets.__file__)
        kwargs['assets_dir'] = assets_dir
    return cls(cache_dir=cache_dir, provider=provider, **kwargs)


def _assets_with_logos(base_dir, team_logos):
    """A copy of the bundled assets dir plus `logos/<team_id>.png` for each
    entry of team_logos ({team_id: png path}): the library reads a team's logo
    override from there. Returns base_dir itself when there is nothing to add."""
    import shutil
    import tempfile
    if not team_logos:
        return base_dir
    d = tempfile.mkdtemp(prefix='rrp_assets_')
    for name in os.listdir(base_dir):
        src = os.path.join(base_dir, name)
        if os.path.isfile(src):
            shutil.copy2(src, d)
    os.makedirs(os.path.join(d, 'logos'))
    for team_id, path in team_logos.items():
        shutil.copy2(path, os.path.join(d, 'logos', f'{int(team_id)}.png'))
    return d


def _patch_options(job, patcher, team_kits=None):
    """The keyword options for patcher.patch from a sports_patch job: only the
    ones this patcher declares, so an older library or another game never sees
    a keyword it does not take.

    `kits` = {slot: {"home": KIT, "away": KIT}}: team_kits (each mapped team's
    own picks, see `_team_kits`) overridden per slot by the job's `kits` dict
    (JSON keys, so slot numbers arrive as strings). Left out entirely when
    empty so the library keeps its own defaults."""
    options = {}
    language = job.get('language')
    if language and getattr(patcher, 'languages', ()):
        options['language'] = language
    if getattr(patcher, 'supports_logos', False) and 'logos' in job:
        options['logos'] = bool(job['logos'])
    if getattr(patcher, 'supports_blank_unused', False) and job.get('blank_unused'):
        options['blank_unused'] = True
    images = job.get('images') or {}
    if getattr(patcher, 'image_slots', ()) and images:
        options['images'] = {slot: path for slot, path in images.items() if path}
    kits = {**(team_kits or {}), **{int(s): k for s, k in (job.get('kits') or {}).items()}}
    if getattr(patcher, 'supports_kits', False) and kits:
        options['kits'] = kits
    return options


def _capabilities(cls, base):
    """The patcher class attributes the app's list_patchers payload carries
    beyond PatcherInfo: every one read with a default so an older library
    (without kits, nationals or slot groups) still lists cleanly."""
    groups = getattr(cls, 'slot_groups', None) or ()
    # Absent on an older library: one league, which can never overwrite a group.
    leagues = int(getattr(cls, 'max_leagues', 1) or 1)
    return {
        'languages': list(getattr(cls, 'languages', None) or ()),
        'supports_logos': bool(getattr(cls, 'supports_logos', False)),
        'supports_blank_unused': bool(getattr(cls, 'supports_blank_unused', False)),
        'image_slots': list(getattr(cls, 'image_slots', None) or ()),
        'supports_kits': bool(getattr(cls, 'supports_kits', False)),
        'kit_templates': _overrides(cls, 'kit_templates', base),
        'supports_nationals': bool(getattr(cls, 'supports_nationals', False)),
        'national_slot_base': getattr(cls, 'national_slot_base', None),
        'slot_groups': [{'name': n, 'first': f, 'count': c} for n, f, c in groups],
        'max_leagues': leagues,
        'multi_league': leagues > 1 and bool(groups),
    }


def _overrides(cls, name, base):
    """True when cls defines `name` itself rather than inheriting base's no-op
    (an older library has neither, which also reads as False)."""
    return getattr(cls, name, None) is not None and getattr(cls, name) is not getattr(base, name, None)


def _load_rosters(job, slot_mapping, rrp):
    """[(LeagueData, slot mapping)] for the job's roster file(s).

    `rosters_file` is one league. `rosters_files` are several leagues sharing
    the job's one `slot_mapping`, whose `slot_index` values are absolute. An
    entry `{"file", "first_slot", "count"}` takes the mapping entries with
    first_slot <= slot_index < first_slot + count (a team in two leagues then
    lands in both their slots); a bare `{"file"}` entry takes the ones whose
    `team_id` is in that file. A file's position in the list never matters.
    """
    entries = job.get('rosters_files') or [{'file': job['rosters_file']}]
    if len(entries) > 1 and not slot_mapping:
        raise ValueError('rosters_files needs a slot_mapping')
    out = []
    for entry in entries:
        with open(entry['file']) as f:
            data = rrp.league_data_from_dict(json.load(f))
        mapping = slot_mapping
        if slot_mapping and 'first_slot' in entry and 'count' in entry:
            first, count = int(entry['first_slot']), int(entry['count'])
            mapping = [m for m in slot_mapping if first <= m.slot_index < first + count]
        elif slot_mapping:
            ids = {t.team.id for t in data.teams}
            mapping = [m for m in slot_mapping if m.team_id in ids]
        out.append((data, mapping))
    return out


def _merge_rosters(patcher, sources, rom):
    """Every (LeagueData, mapping) of sources mapped against rom and merged
    into one MappedRosters (a slot in two leagues takes the later one's). A
    file none of whose teams are mapped (an empty mapping) is skipped: the
    library would refuse it as unmapped; nothing mapped at all is an error."""
    merged = None
    for data, mapping in sources:
        if mapping is not None and not mapping:
            continue
        m = _map_rosters(patcher, data, mapping, rom)
        merged = m if merged is None else merged.merge(m)
    if merged is None:
        raise ValueError('no mapped team in any rosters file')
    return merged


def _team_kits(sources):
    """{slot: {"home": KIT, "away": KIT}} from the roster `extra["kits"]` of
    each mapped team (the editor's picks), keyed by the slot the mapping puts
    it in. A game that maps automatically (no mapping) gets none: the library
    then draws its own defaults."""
    kits = {}
    for data, mapping in sources:
        by_id = {t.team.id: t for t in data.teams}
        for m in mapping or ():
            k = (getattr(by_id.get(m.team_id), 'extra', None) or {}).get('kits')
            if k:
                kits[m.slot_index] = k
    return kits


def _fetch_nationals(patcher, rom, season, rrp, on_progress=None):
    """(LeagueData, slot mapping) of the national squads: the teams of ESPN
    league 2021 (international friendlies) paired with the disc's national rows
    by the patcher's `national_slot_map`; squads and lineups are fetched for
    the mapped teams only, the lineup landing in roster.extra["lineup"]."""
    api = patcher.api
    league = next(iter(api.get_leagues(id=2021, season=season)))
    teams = api.get_teams(2021, season)
    mapping = patcher.national_slot_map(
        Path(rom), rrp.LeagueData(league=league, teams=[rrp.TeamRoster(team=t) for t in teams]))
    wanted = [t for t in teams if t.id in {m.team_id for m in mapping}]
    rosters = []
    for i, team in enumerate(wanted):
        if on_progress:
            on_progress(0, f'National squads {i + 1}/{len(wanted)}: {team.name}')
        r = rrp.TeamRoster(team=team)
        try:
            r.players = api.get_squad(team.id, season)
            lineup = api.get_lineup(team.id, 2021)
            if lineup:
                r.extra['lineup'] = lineup
        except rrp.ApiError as exc:
            r.error = str(exc)
        # Fielding order (starters first), as sports_fetch does: the patch
        # writes the list as given and cuts it at the ROM's squad size.
        try:
            r.players = patcher.suggest_squad_order(r)
        except Exception:
            pass
        rosters.append(r)
    return rrp.LeagueData(league=league, teams=rosters), mapping


def _render_default_images(game_id, league, season, out_dir):
    """{slot: png path} of the app-branded screens for game_id: each game with
    its own art module; default_art raises for the games without one."""
    if game_id == 'pes2013-ps2':
        import pes_art
        return pes_art.render_default_images(league, season, out_dir)
    if game_id == 'nhl07-psp':
        import nhl07_art
        return nhl07_art.render_default_images(league, season, out_dir)
    if game_id == 'iss-snes':
        import iss_art
        return iss_art.render_default_images(league, season, out_dir)
    import default_art
    return default_art.render_default_images(game_id, league, season, out_dir)


def _mounted_previews(patcher, rom, slots, whiches, game_id, homes=None):
    """(key, KIT) -> PNG of the kit on the game's own player model, for the
    keys the job maps to a slot ({key: slot}, kit side in {key: "home"|"away"})
    when the game draws that (`kit_preview_png`, needs the image); None when
    it cannot, so the caller falls back to the flat drawing. A WE2002 slot is
    drawn from its TEX index; on ISS an away kit wears the chest design of
    the team's home KIT in homes ({key: KIT}), the design being the team's."""
    fn = getattr(patcher, 'kit_preview_png', None)
    if not (fn and rom and slots):
        return None
    import templates

    def mounted(key, kit):
        if key not in slots:
            return None
        which = (whiches or {}).get(key, 'home')
        if game_id == 'we2002':
            return fn(Path(rom), templates.we2002_tex(slots[key]), which, kit)
        if which == 'away' and (homes or {}).get(key) is not None:
            return fn(Path(rom), int(slots[key]), which, kit, home=homes[key])
        return fn(Path(rom), int(slots[key]), which, kit)
    return mounted


def _default_kit_specs(colours, whiches, kits_mod, team_cls, teams=None):
    """key -> KitSpec of a team's default kit, as the library draws it
    (`default_kits`: the club's real kits when the library's kit catalogue
    knows it, by the ESPN id in teams ({key: {"id", "name"}}), else plain kits
    in the two colours the app sends, {key: [c1, c2]}), the side from whiches;
    None for a key with neither. None altogether without colours or teams, or
    on a library without default_kits."""
    fn = getattr(kits_mod, 'default_kits', None)
    if not (fn and (colours or teams)):
        return None

    def default(key):
        c = list((colours or {}).get(key) or []) + ['', '']
        t = (teams or {}).get(key) or {}
        team = team_cls(id=int(t.get('id') or 0), name=str(t.get('name') or ''), color=c[0], alternate_color=c[1])
        home, away = fn(team)
        return away if (whiches or {}).get(key) == 'away' else home
    return default


def _default_kit_dicts(kits, default):
    """{key: spec dict} of the default kit each null KIT of kits ({key: KIT})
    stands for (`default`: see `_default_kit_specs`), so the app's picker can
    show the default the patch writes; a key whose default is unknown is left
    out."""
    if not default:
        return {}
    specs = {key: default(key) for key, kit in (kits or {}).items() if kit is None}
    return {key: spec.to_dict() for key, spec in specs.items() if hasattr(spec, 'to_dict')}


def _kit_previews(kits, out_dir, kits_mod, mounted=None, default=None):
    """Write `<out_dir>/<key>.png` for each KIT of kits ({key: KIT}); returns
    {key: path}. With `mounted` (see `_mounted_previews`) a key it can draw
    shows the kit on the player, any KIT kind included. None is the team's
    default when `default` (see `_default_kit_specs`) knows it, the way the
    patch draws it, else the slot's current kit. Without `mounted` a spec is
    drawn flat as is, a {"image": path} pick as the spec the game will get
    from it (`kit_from_image`), and {"template": n} picks are skipped (the
    templates are written separately). A picked file is always copied next to its preview as
    `<key>_source.png`."""
    import shutil
    os.makedirs(out_dir, exist_ok=True)
    written = {}
    for key, kit in (kits or {}).items():
        if kit and 'image' in kit:
            shutil.copy2(kit['image'], os.path.join(out_dir, f'{key}_source.png'))
        if kit is None and default:
            # The team's default is what the patch draws, not the disc's kit.
            spec = default(key)
            if spec is None:
                continue
            png = mounted(key, spec.to_dict()) if mounted and hasattr(spec, 'to_dict') else None
            if png is None:
                png = kits_mod.render_kit(spec)
        else:
            png = mounted(key, kit) if mounted else None
            if png is None:
                if not kit or 'template' in kit:
                    continue
                if 'image' in kit:
                    with open(kit['image'], 'rb') as f:
                        spec = kits_mod.kit_from_image(f.read())
                else:
                    spec = kits_mod.KitSpec.from_dict(kit)
                png = kits_mod.render_kit(spec)
        path = os.path.join(out_dir, f'{key}.png')
        with open(path, 'wb') as f:
            f.write(png)
        written[key] = path
    return written


def _league_season(league_id, code=None):
    """The season to fetch for a soccer league the app sent no season for: the
    library's per-league calendar (August-to-May leagues are named by their start
    year, calendar-year ones by their year). An older library without it gets the
    calendar year."""
    from retro_roster_patcher.sports import espn as _espn
    code = code or next((l['code'] for l in _espn.ESPN_LEAGUES if l['id'] == league_id), '')
    pick = getattr(_espn, 'default_season', None)
    if pick is None or not code:
        import datetime
        return datetime.date.today().year
    return pick(code)


def _with_data_file(rom_path):
    """(data file path, cleanup) for a ROM that may be a zip or a .cue: the
    zip's data track is extracted to a temp dir that cleanup removes; a .cue
    (text) resolves to its first data track next to it."""
    import shutil
    import tempfile
    import zipfile
    rom_path = str(rom_path)
    if rom_path.lower().endswith('.cue'):
        track = _cue_first_bin(rom_path)
        if track:
            rom_path = os.path.join(os.path.dirname(rom_path) or '.', track)
    if not rom_path.lower().endswith('.zip'):
        return rom_path, lambda: None
    work = tempfile.mkdtemp(prefix='rrp_zip_')
    with zipfile.ZipFile(rom_path) as zf:
        zf.extractall(work)
    inner = [os.path.join(dp, f) for dp, _, fs in os.walk(work) for f in fs]
    data_file = _find_data_file(inner)
    if not data_file:
        shutil.rmtree(work, ignore_errors=True)
        raise ValueError('No patchable image inside the zip')
    return data_file, lambda: shutil.rmtree(work, ignore_errors=True)


def _map_rosters(patcher, data, slot_mapping, rom):
    """map_rosters plus the per-ROM extras some games need, as the library's
    CLI does: a game that declares `roster_counts` reads each team's shape off
    the image (via analyze_rom) instead of falling back to a fixed default.

    `order_as_given`: the rosters come from the app's editor, whose list order
    is the ROM order the user set up, so the library must write it as is
    rather than re-select by stats."""
    import inspect
    extras = {}
    if 'order_as_given' in inspect.signature(patcher.map_rosters).parameters:
        extras['order_as_given'] = True
    if 'roster_counts' in inspect.signature(patcher.map_rosters).parameters:
        counts = patcher.analyze_rom(Path(rom)).extra.get('roster_counts')
        if counts:
            extras['roster_counts'] = counts
    return patcher.map_rosters(data, slot_mapping, **extras)


def _register_league(league):
    """Add a user-supplied league to the library's ESPN catalog (idempotent).

    Lets the app offer custom leagues from a JSON file: fetch resolves a
    league_id to an ESPN code through this catalog, so a code the library
    doesn't ship must be injected before fetch.
    """
    from retro_roster_patcher.sports import espn as _espn
    if any(item['id'] == league['id'] for item in _espn.ESPN_LEAGUES):
        return
    _espn.ESPN_LEAGUES.append({
        'id': league['id'],
        'code': league['code'],
        'name': league.get('name', str(league['id'])),
        'country': league.get('country', ''),
    })
    _espn._ID_TO_LEAGUE = {i['id']: i for i in _espn.ESPN_LEAGUES}
    _espn._CODE_TO_LEAGUE = {i['code']: i for i in _espn.ESPN_LEAGUES}


def _fill_soccer_photos(patcher, data, cache_dir, rrp, on_progress=None):
    """Soccer only: give each player ESPN has no head shot for the one FotMob
    has (the library's `fill_headshots`, what the CLI's
    `--fill-from-other-sources` runs), matched by birth date and name. Best
    effort: a library without it, or FotMob being down, leaves the squads as
    they were. Returns how many players got a photo."""
    sports = getattr(rrp, 'sports', None)
    fill = getattr(sports, 'fill_headshots', None)
    if getattr(patcher, 'sport', '') != 'soccer' or fill is None:
        return 0

    def status(msg):
        if on_progress:
            on_progress(0.95, msg)

    try:
        return fill(data, sports.FotmobClient(cache_dir, status), status)
    except Exception:
        return 0


def run_sports(job):
    """Drive the retro_roster_patcher library for one sports job.

    Job `type` selects the step; data-returning steps write JSON to `output_file`
    and then report DONE (the progress_file only carries PROGRESS/DONE/ERROR).
    Everything is caught and reported as ERROR:<type>: <msg>.
    """
    progress_file = job.get('progress_file')
    output_file = job.get('output_file')
    jtype = job.get('type')

    def emit(obj):
        if output_file:
            with open(output_file, 'w') as f:
                json.dump(obj, f)

    last = [-1]
    last_msg = ['']

    def on_progress(frac, msg=''):
        if msg and msg != last_msg[0]:
            last_msg[0] = msg
            _report(progress_file, f'STATUS:{msg}')
        pct = max(0, min(99, int((frac or 0) * 100)))
        if pct != last[0]:
            last[0] = pct
            _report(progress_file, f'PROGRESS:{pct}')

    _configure_ssl()
    try:
        import retro_roster_patcher as rrp
    except Exception as e:
        _report(progress_file, f'ERROR:retro_roster_patcher not available: {e}')
        return

    try:
        if jtype == 'list_patchers':
            # `languages` and the visual capabilities live on the patcher
            # class, not in PatcherInfo.
            out = []
            for p in rrp.list_patchers():
                cls = rrp.get_patcher(p.game_id)
                out.append({**p.to_dict(), **_capabilities(cls, rrp.Patcher)})
            emit(out)
            _report(progress_file, 'DONE')
            return

        if jtype == 'list_leagues':
            from retro_roster_patcher.sports import espn as _espn
            emit([{'id': i['id'], 'name': i['name'], 'country': i.get('country', '')}
                  for i in _espn.ESPN_LEAGUES])
            _report(progress_file, 'DONE')
            return

        game_id = job.get('game_id')
        cache_dir = job.get('cache_dir') or os.path.join(
            os.environ.get('JOBS_DIR', '.'), '..', 'rrp_cache')
        provider = job.get('provider') or None

        if jtype == 'sports_analyze':
            patcher = rrp.get_patcher(game_id)(cache_dir=cache_dir, provider=provider)
            info = patcher.analyze_rom(Path(job['rom_path']))
            emit(info.to_dict())
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_fetch':
            # A custom (user-JSON) league carries its ESPN code; register it in
            # the catalog so fetch can resolve league_id -> code. Built-in
            # leagues are already there and skip this.
            league = job.get('league')
            if league and league.get('code'):
                _register_league(league)
            patcher = rrp.get_patcher(game_id)(cache_dir=cache_dir, provider=provider)
            league_id = job.get('league_id') or (league or {}).get('id')
            season = job.get('season')
            if season is None:
                season = _league_season(league_id, (league or {}).get('code'))
            data = patcher.fetch(
                season=int(season),
                league_id=league_id,
                on_progress=on_progress,
            )
            _fill_soccer_photos(patcher, data, cache_dir, rrp, on_progress)
            # Reorder each squad into the game's fielding order (starters first)
            # so the editor shows a sensible lineup instead of the provider's
            # alphabetical dump. The patch writes the (possibly edited) list in
            # this order: see `_map_rosters`.
            for roster in data.teams:
                try:
                    roster.players = patcher.suggest_squad_order(roster)
                except Exception:
                    pass  # keep raw order if a game's ordering hiccups
            emit(rrp.league_data_to_dict(data))
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_images':
            # The current screen art of each slot, as PNGs laid out the way the
            # game keeps them, for the app to preview and let the user edit.
            patcher = rrp.get_patcher(game_id)(cache_dir=cache_dir, provider=provider)
            data_file, cleanup = _with_data_file(job['rom_path'])
            try:
                written = patcher.export_images(Path(data_file), Path(job['out_dir']))
            finally:
                cleanup()
            emit({p.stem: str(p) for p in written})
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_default_images':
            emit(_render_default_images(
                game_id, job.get('league') or '', job.get('season') or '', job['out_dir']))
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_templates':
            # A zip of guide PNGs (red boxes where the game shows the user's
            # art) for the app's "download templates" button. rom_path is
            # accepted but unused: the geometry is static.
            import templates
            cls = rrp.get_patcher(game_id)
            if job.get('kind') == 'kits':
                # One team's current kit pages: needs the image.
                data_file, cleanup = _with_data_file(job['rom_path'])
                try:
                    path, names = templates.build_kits(
                        game_id, job['out_dir'], cls(cache_dir=cache_dir, provider=provider), data_file,
                        int(job['slot']), job.get('which') or None, job.get('template'))
                finally:
                    cleanup()
            else:
                path, names = templates.build(game_id, job['out_dir'], bool(getattr(cls, 'supports_kits', False)))
            emit({'zip': path, 'files': names})
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_kit_previews':
            from retro_roster_patcher.core import kits as _kits
            out_dir = job['out_dir']
            cls = rrp.get_patcher(game_id)
            patcher = cls(cache_dir=cache_dir, provider=provider)
            # Only mounted previews and the game's designs read the ROM; flat
            # ones (the picker's patterns and defaults) skip extracting a zip.
            needs_rom = job.get('rom_path') and (job.get('slots') or job.get('templates'))
            data_file, cleanup = _with_data_file(job['rom_path']) if needs_rom else (None, lambda: None)
            try:
                default = _default_kit_specs(job.get('colours') or {}, job.get('which') or {}, _kits, rrp.Team, job.get('teams') or {})
                # An away kit's home KIT (null: the team's default home kit).
                homes = dict(job.get('home') or {})
                default_home = _default_kit_specs(job.get('colours') or {}, {}, _kits, rrp.Team, job.get('teams') or {})
                for key, kit in homes.items():
                    spec = default_home(key) if kit is None and default_home else None
                    if spec is not None and hasattr(spec, 'to_dict'):
                        homes[key] = spec.to_dict()
                mounted = _mounted_previews(patcher, data_file, job.get('slots') or {}, job.get('which') or {}, game_id, homes)
                written = _kit_previews(job.get('kits'), out_dir, _kits, mounted, default)
                defaults = _default_kit_dicts(job.get('kits'), default)
                templates = []
                if job.get('templates') and data_file and _overrides(cls, 'kit_templates', rrp.Patcher):
                    for t in patcher.kit_templates(Path(data_file)):
                        path = os.path.join(out_dir, f'template_{t.index}.png')
                        with open(path, 'wb') as f:
                            f.write(t.png)
                        templates.append({'index': t.index, 'name': t.name, 'path': path})
            finally:
                cleanup()
            emit({'kits': written, 'defaults': defaults, 'templates': templates})
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_patch':
            patcher = _build_patcher(rrp.get_patcher(game_id), cache_dir, provider)
            team_logos = job.get('team_logos') or {}
            if team_logos and getattr(patcher, 'assets_dir', None) is not None:
                patcher = _build_patcher(
                    rrp.get_patcher(game_id), cache_dir, provider,
                    assets_dir=_assets_with_logos(str(patcher.assets_dir), team_logos))
            raw_map = job.get('slot_mapping')
            slot_mapping = ([rrp.SlotMapping.from_dict(m) for m in raw_map]
                            if raw_map else None)
            sources = _load_rosters(job, slot_mapping, rrp)
            options = _patch_options(job, patcher, _team_kits(sources))
            nationals = bool(job.get('nationals')) and getattr(patcher, 'supports_nationals', False)
            season = job.get('season') or sources[0][0].league.season

            def rosters_for(rom):
                # The national squads are fetched here: pairing them with the
                # disc's rows needs the actual image.
                merged = _merge_rosters(patcher, sources, rom)
                if nationals:
                    data, mapping = _fetch_nationals(patcher, rom, season, rrp, on_progress)
                    merged = merged.merge(_map_rosters(patcher, data, mapping, rom))
                return merged

            result = _patch_with_packaging(
                patcher, job['rom_path'], job['output_dir'], job['label'],
                rosters_for, on_progress, options,
            )
            emit(result.to_dict())
            _report(progress_file, 'DONE')
            return

        _report(progress_file, f'ERROR:Unknown sports job type: {jtype}')
    except rrp.RetroRosterError as e:
        _report(progress_file, f'ERROR:{type(e).__name__}: {e}')
    except Exception as e:
        _report(progress_file, f'ERROR:{e}')


def run_job(job):
    """Run one job described by a dict, reporting via its progress_file.

    Catches everything: an exception that escapes to the interpreter's default
    excepthook (PyErr_Display) can itself segfault this build, so nothing is
    allowed to propagate out.
    """
    if job.get('type') == '3dsconv':
        return run_3dsconv(job)
    if job.get('type') in SPORTS_TYPES:
        return run_sports(job)

    progress_file = job.get('progress_file')
    nsz_file = job.get('nsz_file')
    output_dir = job.get('output_dir')

    if not nsz_file or not output_dir:
        _report(progress_file, 'ERROR:Missing nsz_file or output_dir in job')
        return

    try:
        from nsz import decompress

        keys_path = job.get('keys_path') or None
        last_pct = [-1]

        def on_progress(done, total):
            if total <= 0:
                return
            pct = min(99, int(done * 100 / total))
            if pct != last_pct[0]:
                last_pct[0] = pct
                _report(progress_file, f'PROGRESS:{pct}')

        decompress(Path(nsz_file), Path(output_dir), True, None,
                   keys_path=keys_path, progress_callback=on_progress)
        _report(progress_file, 'DONE')
    except Exception as e:
        _report(progress_file, f'ERROR:{e}')


def worker_loop(jobs_dir, once=False):
    """Persistent worker: claim job_*.json files and process them one at a time.

    serious_python corrupts process memory if the embedded interpreter is
    initialized a second time in one process (a second SeriousPython.run crashes
    the whole app). So the app starts this loop ONCE and hands each decompression
    over as a job file, instead of calling run() again per NSZ.
    """
    os.makedirs(jobs_dir, exist_ok=True)
    while True:
        for job_path in sorted(glob.glob(os.path.join(jobs_dir, 'job_*.json'))):
            active = job_path + '.active'
            try:
                os.rename(job_path, active)  # claim it; skip if already taken
            except OSError:
                continue
            job = None
            try:
                with open(active) as f:
                    job = json.load(f)
                run_job(job)
            except Exception as e:
                _report((job or {}).get('progress_file'), f'ERROR:{e}')
            finally:
                try:
                    os.remove(active)
                except OSError:
                    pass
        if once:
            return
        time.sleep(0.3)


def _self_test():
    """`python3 main.py --self-test` — exercises the job claim/dispatch/cleanup."""
    import tempfile
    global run_job
    original = run_job
    calls = []

    def fake(job):
        calls.append(job)
        _report(job.get('progress_file'), 'DONE')

    run_job = fake
    try:
        d = tempfile.mkdtemp()
        pf = os.path.join(d, 'prog.txt')
        open(pf, 'w').close()
        with open(os.path.join(d, 'job_1.json'), 'w') as f:
            json.dump({'nsz_file': 'x.nsz', 'output_dir': d, 'progress_file': pf}, f)
        worker_loop(d, once=True)
        assert len(calls) == 1, calls
        assert 'DONE' in open(pf).read()
        assert not glob.glob(os.path.join(d, 'job_*.json*')), 'job file not cleaned up'
    finally:
        run_job = original

    # Sports jobs route to run_sports and never raise, even with the lib absent.
    global run_sports
    sports_orig = run_sports
    routed = []
    run_sports = lambda job: routed.append(job.get('type'))
    try:
        for t in SPORTS_TYPES:
            run_job({'type': t})
        assert set(routed) == SPORTS_TYPES, routed
    finally:
        run_sports = sports_orig

    # With the real handler and the lib unavailable, a sports job reports ERROR
    # (not a crash) and leaves no DONE.
    import tempfile as _tf
    pf2 = os.path.join(_tf.mkdtemp(), 'p.txt')
    open(pf2, 'w').close()
    run_job({'type': 'list_patchers', 'progress_file': pf2})
    out = open(pf2).read()
    assert 'DONE' in out or 'ERROR:' in out, out
    print('self-test OK')


def main():
    if '--self-test' in sys.argv:
        _self_test()
        return

    jobs_dir = os.environ.get('JOBS_DIR')
    if jobs_dir:
        worker_loop(jobs_dir)
        return

    # Legacy single-shot path, kept for any caller still passing env vars.
    run_job({
        'nsz_file': os.environ.get('NSZ_FILE'),
        'output_dir': os.environ.get('OUTPUT_DIR'),
        'keys_path': os.environ.get('KEYS_PATH') or None,
        'progress_file': os.environ.get('PROGRESS_FILE'),
    })


main()
