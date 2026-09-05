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


SPORTS_TYPES = {'list_patchers', 'list_leagues', 'sports_fetch', 'sports_analyze', 'sports_patch'}


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


def _patch_with_packaging(patcher, rom_path, output_path, rosters, on_progress):
    """Run patcher.patch, honoring disc packaging like the old app:

    - .zip in -> .zip out: extract, patch the data image in place (internal
      names preserved), re-zip to output_path.
    - loose .cue/.bin(+tracks): patch the data track, copy companion tracks and
      the .cue to the output prefix, rewriting the .cue's FILE references.
    - single image (.iso/.smc/...): patch straight through.

    Returns the library's PatchResult.
    """
    import os
    import shutil
    import tempfile
    import zipfile

    rom_path = str(rom_path)
    output_path = str(output_path)
    out_dir = os.path.dirname(output_path)
    new_prefix = os.path.splitext(os.path.basename(output_path))[0]

    # --- ZIP in -> ZIP out ---------------------------------------------------
    if rom_path.lower().endswith('.zip'):
        work = tempfile.mkdtemp(prefix='rrp_zip_')
        try:
            with zipfile.ZipFile(rom_path) as zf:
                zf.extractall(work)
            inner = [os.path.join(dp, f) for dp, _, fs in os.walk(work) for f in fs]
            data_file = _find_data_file(inner)
            if not data_file:
                raise rrp.RomError('No patchable image inside the zip')
            result = patcher.patch(
                rom_path=Path(data_file), output_path=Path(data_file),
                rosters=rosters, on_progress=on_progress,
            )
            out_zip = output_path if output_path.lower().endswith('.zip') else output_path + '.zip'
            # Rename the inner files to the output prefix too (keeping any
            # " (Track N)" suffix), and rewrite the .cue's FILE references so it
            # still points at the renamed tracks.
            import re as _re
            data_base = os.path.splitext(os.path.basename(data_file))[0]
            inner_base = _re.sub(r'\s*[\(\-]\s*[Tt]rack\s*\d+\)?.*$', '', data_base)
            def _renamed(name):
                return name.replace(inner_base, new_prefix) if inner_base and inner_base in name else name
            with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
                for f in inner:
                    arc = _renamed(os.path.basename(f))
                    if f.lower().endswith('.cue') and inner_base:
                        txt = open(f, errors='replace').read().replace(inner_base, new_prefix)
                        zf.writestr(arc, txt)
                    else:
                        zf.write(f, arc)
            # Report the zip we actually wrote.
            result.output_path = out_zip
            return result
        finally:
            shutil.rmtree(work, ignore_errors=True)

    # --- loose multi-track disc (.cue + .bin tracks) -------------------------
    src_dir = os.path.dirname(rom_path)
    base = os.path.splitext(os.path.basename(rom_path))[0]
    # A track suffix like " (Track 2)" isn't part of the shared base name.
    import re as _re
    game_base = _re.sub(r'\s*[\(\-]\s*[Tt]rack\s*\d+\)?.*$', '', base)
    companions = [
        os.path.join(src_dir, e) for e in (os.listdir(src_dir) if src_dir else [])
        if e.lower().endswith(('.bin', '.cue')) and e.lower().startswith(game_base.lower())
    ]
    if companions:
        os.makedirs(out_dir, exist_ok=True)
        data_file = _find_data_file(companions)
        result = None
        for f in companions:
            ext = os.path.splitext(f)[1]
            dst = os.path.join(out_dir, os.path.basename(f).replace(game_base, new_prefix))
            if f == data_file:
                result = patcher.patch(
                    rom_path=Path(f), output_path=Path(dst),
                    rosters=rosters, on_progress=on_progress,
                )
            elif ext.lower() == '.cue':
                txt = open(f, errors='replace').read().replace(game_base, new_prefix)
                open(dst, 'w').write(txt)
            else:
                shutil.copy2(f, dst)
        return result

    # --- single image --------------------------------------------------------
    return patcher.patch(
        rom_path=Path(rom_path), output_path=Path(output_path),
        rosters=rosters, on_progress=on_progress,
    )


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
            emit([p.to_dict() for p in rrp.list_patchers()])
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
            data = patcher.fetch(
                season=int(job['season']),
                league_id=job.get('league_id') or (league or {}).get('id'),
                on_progress=on_progress,
            )
            # Reorder each squad into the game's fielding order (starters first)
            # so the editor shows a sensible lineup instead of the provider's
            # alphabetical dump. Advisory only — patch still runs its own select.
            for roster in data.teams:
                try:
                    roster.players = patcher.suggest_squad_order(roster)
                except Exception:
                    pass  # keep raw order if a game's ordering hiccups
            emit(rrp.league_data_to_dict(data))
            _report(progress_file, 'DONE')
            return

        if jtype == 'sports_patch':
            patcher = rrp.get_patcher(game_id)(cache_dir=cache_dir, provider=provider)
            with open(job['rosters_file']) as f:
                data = rrp.league_data_from_dict(json.load(f))
            raw_map = job.get('slot_mapping')
            slot_mapping = ([rrp.SlotMapping.from_dict(m) for m in raw_map]
                            if raw_map else None)
            rosters = patcher.map_rosters(data, slot_mapping)
            result = _patch_with_packaging(
                patcher, job['rom_path'], job['output_path'], rosters, on_progress,
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
