#!/usr/bin/env python3
import os
import sys
from pathlib import Path


def _report(progress_file, msg):
    if progress_file:
        with open(progress_file, 'a') as f:
            f.write(msg + '\n')
    print(msg, flush=True)


def main():
    nsz_file = os.environ.get('NSZ_FILE')
    output_dir = os.environ.get('OUTPUT_DIR')
    keys_path = os.environ.get('KEYS_PATH') or None
    progress_file = os.environ.get('PROGRESS_FILE')

    if not nsz_file or not output_dir:
        _report(progress_file, 'ERROR:Missing NSZ_FILE or OUTPUT_DIR environment variables')
        return

    try:
        from nsz import decompress
    except ImportError as e:
        _report(progress_file, f'ERROR:NSZ library import failed: {e}')
        return

    last_pct = [-1]

    def on_progress(done, total):
        if total <= 0:
            return
        pct = min(99, int(done * 100 / total))
        if pct != last_pct[0]:
            last_pct[0] = pct
            _report(progress_file, f'PROGRESS:{pct}')

    try:
        decompress(
            Path(nsz_file),
            Path(output_dir),
            True,   # fixPadding
            None,   # statusReportInfo
            keys_path=keys_path,
            progress_callback=on_progress,
        )
        _report(progress_file, 'DONE')
    except Exception as e:
        _report(progress_file, f'ERROR:{e}')


main()
