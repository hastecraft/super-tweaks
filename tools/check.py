"""Consistency checks CI runs on every pull request, push and release tag:

- every file the TOC loads exists (following XML includes);
- the patch notes load, each entry has a version (x.y.z) and a date (YYYY-MM-DD), newest first, no repeats;
- the TOC's ## Version is the newest patch notes entry's version (a prerelease such as 1.2.0-beta.1 matches 1.2.0);
- CHANGELOG.md is up to date with the patch notes;
- with --tag vX: the tag is the TOC's version;
- with --base REF: the pull request leaves the patch notes' entries and the TOC's version alone (so CHANGELOG.md too),
  unless it is a release pull request (--release). Releases write those; see .claude/skills/release. (PatchNotes.lua's code
  and comments may change.)

Usage: python tools/check.py [--tag vX.Y.Z] [--base REF [--release]]
"""
from pathlib import Path
import os
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / 'tools'))
sys.path.insert(0, str(PROJECT / 'tools' / 'mockgame'))
import changelog  # noqa: E402
from harness import toc_files  # noqa: E402

ADDON = PROJECT / 'HastesSuperTweaks'
TOC = ADDON / 'HastesSuperTweaks.toc'
NOTES = 'HastesSuperTweaks/PatchNotes.lua'
VERSION = re.compile(r'^(\d+)\.(\d+)\.(\d+)$')
errors = []


def error(message, file=None):
    errors.append(message)
    print(f'::error{" file=" + file if file else ""}::{message}' if 'GITHUB_ACTIONS' in os.environ
          else f'error: {message}')


def arg(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def toc_version(text):
    match = re.search(r'^## Version:\s*(\S+)\s*$', text, re.M)
    return match.group(1) if match else None


def main():
    try:
        toc_files(ADDON)
    except AssertionError as missing:
        error(str(missing), 'HastesSuperTweaks/HastesSuperTweaks.toc')

    notes = changelog.load_notes()
    seen = set()
    for i, entry in enumerate(notes):
        version, date = entry.get('version', ''), entry.get('date', '')
        if not VERSION.match(version):
            error(f'Patch notes entry {i + 1}: version "{version}" isn\'t x.y.z', NOTES)
        if not re.match(r'^\d{4}-\d{2}-\d{2}$', date):
            error(f'Patch notes {version}: date "{date}" isn\'t YYYY-MM-DD', NOTES)
        if version in seen:
            error(f'Patch notes list {version} twice', NOTES)
        seen.add(version)
    numbers = [tuple(map(int, VERSION.match(e['version']).groups())) for e in notes if VERSION.match(e['version'])]
    if numbers != sorted(numbers, reverse=True):
        error('Patch notes must be newest first', NOTES)

    version = toc_version(TOC.read_text(encoding='utf-8-sig'))
    newest = notes[0]['version'] if notes else None
    if not version:
        error('The TOC has no ## Version', 'HastesSuperTweaks/HastesSuperTweaks.toc')
    elif version.split('-')[0] != newest:
        error(f'The TOC\'s version {version} isn\'t the newest patch notes entry ({newest})',
              'HastesSuperTweaks/HastesSuperTweaks.toc')

    if not changelog.is_current(notes):
        error('CHANGELOG.md is out of date with PatchNotes.lua: run python tools/changelog.py', 'CHANGELOG.md')

    tag = arg('--tag')
    if tag and tag != f'v{version}':
        error(f'Tag {tag} doesn\'t match the TOC\'s version {version}: the tag must be v{version}')

    base = arg('--base')
    if base and '--release' not in sys.argv:
        def at_base(path):
            return subprocess.run(['git', 'show', f'{base}:{path}'], cwd=PROJECT, capture_output=True, text=True,
                                  encoding='utf-8', check=True).stdout
        changed = subprocess.run(['git', 'diff', '--name-only', f'{base}...HEAD'], cwd=PROJECT, capture_output=True,
                                 text=True, check=True).stdout.split()
        later = 'describe the change for players in the pull request instead (see CONTRIBUTING.md)'
        if NOTES in changed and changelog.load_notes(at_base(NOTES).lstrip('\ufeff')) != notes:
            error(f'Patch notes entries are written at release time; {later}', NOTES)
        if toc_version(at_base('HastesSuperTweaks/HastesSuperTweaks.toc')) != version:
            error('The TOC\'s ## Version is set at release time; leave it as it is (see CONTRIBUTING.md)',
                  'HastesSuperTweaks/HastesSuperTweaks.toc')

    if errors:
        sys.exit(f'{len(errors)} problem(s) found')
    print(f'All checks passed (version {version}).')


if __name__ == '__main__':
    main()
