"""`python3 tool/test_3dsconv_keys.py` — 3dsconv key loading from aes_keys.txt.

A Citra/Azahar aes_keys.txt can stand in for boot9.bin: its slot0x2CKeyX line
is read and trusted only if it matches the known key hash. No real key lives
here; the positive case runs only when AES_KEYS_TXT points at your own file.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'python_app')
SCRIPT = os.path.join(ROOT, 'threedsconv', 'threedsconv.py')


def run(keys_path):
    with tempfile.TemporaryDirectory() as d:
        # empty cwd/HOME so the script's boot9 fallbacks can't find anything
        env = dict(os.environ, PYTHONPATH=ROOT, HOME=d, BOOT9_PATH='')
        out = subprocess.run([sys.executable, SCRIPT, '-v', '-o', d, '-b', keys_path, os.path.join(d, 'none.3ds')],
                             cwd=d, env=env, capture_output=True, text=True, timeout=60)
        return out.stdout + out.stderr


with tempfile.TemporaryDirectory() as d:
    bad = os.path.join(d, 'aes_keys.txt')
    with open(bad, 'w') as f:
        f.write('slot0x25KeyX=00000000000000000000000000000000\r\nslot0x2CKeyX=' + '11' * 16 + '\r\n')
    out = run(bad)
    assert 'slot0x2CKeyX found, Corrupt file (invalid key)' in out and 'Correct key found' not in out, out

real = os.environ.get('AES_KEYS_TXT')
if real:
    out = run(real)
    assert 'Correct key found' in out, out
    print('ok (with AES_KEYS_TXT)')
else:
    print('ok (positive case skipped: set AES_KEYS_TXT to your own aes_keys.txt)')
