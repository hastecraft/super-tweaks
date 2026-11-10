"""Runs what CI runs on a pull request, locally and in one go:

- luacheck, when it is installed (https://github.com/lunarmodules/luacheck); CI runs it either way;
- tools/check.py against the base branch (as a release, on a release/* branch);
- the bench for this checkout and for the base branch, and their comparison (tools/bench_compare.py).

The base is where this branch left REF (origin/master unless --base names another). Nothing is written to the checkout.

Usage: python tools/verify.py [--base REF]
"""
from pathlib import Path
import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

PROJECT = Path(__file__).resolve().parent.parent
TOOLS = PROJECT / 'tools'


def git(*args, binary=False):
    result = subprocess.run(['git', *args], cwd=PROJECT, capture_output=True, check=True)
    return result.stdout if binary else result.stdout.decode('utf-8').strip()


def tool(name, *args, env=None, out=None):
    """Runs one of the tools; its output goes to `out` (a file) or the console. Returns its exit code."""
    command = [sys.executable, str(TOOLS / name), *args]
    if out is None:
        return subprocess.run(command, cwd=PROJECT, env=env).returncode
    with open(out, 'wb') as file:
        return subprocess.run(command, cwd=PROJECT, env=env, stdout=file).returncode


def main():
    ref = sys.argv[sys.argv.index('--base') + 1] if '--base' in sys.argv else 'origin/master'
    base = git('merge-base', ref, 'HEAD')
    branch = git('rev-parse', '--abbrev-ref', 'HEAD')
    failed = []

    print(f'== luacheck (base {ref} at {base[:7]})', flush=True)
    luacheck = shutil.which('luacheck')
    if not luacheck:
        print('luacheck is not installed, so it was skipped; CI runs it.')
    elif subprocess.run([luacheck, '.', '--formatter', 'plain'], cwd=PROJECT).returncode != 0:
        failed.append('luacheck')

    print('== tools/check.py', flush=True)
    flags = ['--release'] if branch.startswith('release/') else []
    if tool('check.py', '--base', base, *flags) != 0:
        failed.append('check.py')

    print('== bench (this checkout, then the base)', flush=True)
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        if tool('bench.py', '--json', out=temp / 'head.json') != 0:
            failed.append('bench.py')
        with tarfile.open(fileobj=io.BytesIO(git('archive', base, 'HastesSuperTweaks', binary=True))) as archive:
            archive.extractall(temp / 'base', filter='data')
        # Both sides run this checkout's bench, mocks and scenarios, as CI does; only the addon differs.
        if tool('bench.py', '--json', env={**os.environ, 'HST_ROOT': str(temp / 'base')}, out=temp / 'base.json') != 0:
            print('Some scenarios failed on the base; they are compared as new.')
        if tool('bench_compare.py', str(temp / 'base.json'), str(temp / 'head.json'), out=temp / 'report.md') != 0:
            failed.append('the bench comparison (a major regression)')
        sys.stdout.flush()
        sys.stdout.buffer.write((temp / 'report.md').read_bytes())
        sys.stdout.buffer.flush()

    if failed:
        sys.exit('\nFailed: ' + ', '.join(failed))
    print('\nAll passed.')


if __name__ == '__main__':
    main()
