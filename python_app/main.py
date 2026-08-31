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


def run_job(job):
    """Decompress one NSZ described by a job dict, reporting via its progress_file.

    Catches everything: an exception that escapes to the interpreter's default
    excepthook (PyErr_Display) can itself segfault this build, so nothing is
    allowed to propagate out.
    """
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
        print('self-test OK')
    finally:
        run_job = original


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
