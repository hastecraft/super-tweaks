"""Writes CHANGELOG.md from the in-game patch notes (HastesSuperTweaks/PatchNotes.lua), the one place release notes are
written. The release workflow also uses it for a single version's notes on GitHub, CurseForge and Wago.

Usage: python tools/changelog.py               rewrites CHANGELOG.md
       python tools/changelog.py --check       fails if CHANGELOG.md is out of date
       python tools/changelog.py --version X   prints version X's notes (markdown) to stdout
"""
from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / 'tools' / 'mockgame'))
from harness import LuaRuntime  # noqa: E402  (lupa, from tools/mockgame/pydeps or pip)

ADDON = PROJECT / 'HastesSuperTweaks'
CHANGELOG = PROJECT / 'CHANGELOG.md'
KINDS = [('new', 'New'), ('changed', 'Changed'), ('fixed', 'Fixed')]
HEADER = ("# Changelog\n\nGenerated from `HastesSuperTweaks/PatchNotes.lua` by `tools/changelog.py`; don't edit it by hand. "
          "The same notes show in game: click the version beside the settings window's title.\n")


def load_notes(source=None):
    """The patch notes as Python lists and dicts, newest first: PatchNotes.lua's, or those in source (its text)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    run = lua.eval('function(source) local fn, err = loadstring(source, "PatchNotes.lua"); assert(fn, err); '
                   'local ns = { HST = {} }; fn("HastesSuperTweaks", ns); return ns.HST.patchNotes end')
    notes = run(source if source is not None else (ADDON / 'PatchNotes.lua').read_text(encoding='utf-8-sig'))
    assert notes is not None, 'PatchNotes.lua defines no HST.patchNotes'

    def plain(value):
        if lua.eval('type')(value) != 'table':
            return value
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [plain(value[k]) for k in sorted(keys)]
        return {k: plain(v) for k, v in value.items()}
    return [plain(notes[i]) for i in range(1, len(notes) + 1)]


def text_of(change):
    return change if isinstance(change, str) else change[1] if 1 in change else change.get('text', '')


def line(change):
    return f'- {text_of(change)}'


def highlight(change, level):
    """A highlight as a heading (its title) over its text."""
    if isinstance(change, str) or not change.get('title'):
        return f"{'#' * level} {text_of(change)}\n"
    return f"{'#' * level} {change['title']}\n\n{text_of(change)}\n"


def section(entry, level=2):
    out = [f"{'#' * level} {entry['version']} ({entry['date']})", '']
    if entry.get('summary'):
        out += [entry['summary'], '']
    if entry.get('highlights'):
        out += [highlight(h, level + 1) for h in entry['highlights']]
    for key, name in KINDS:
        if entry.get(key):
            out += [f"{'#' * (level + 1)} {name}", ''] + [line(c) for c in entry[key]] + ['']
    return '\n'.join(out)


def changelog(notes):
    return HEADER + '\n' + '\n'.join(section(entry) for entry in notes)


def is_current(notes):
    current = CHANGELOG.read_text(encoding='utf-8') if CHANGELOG.exists() else ''
    return current.replace('\r\n', '\n') == changelog(notes)


def main():
    notes = load_notes()
    if '--version' in sys.argv:
        version = sys.argv[sys.argv.index('--version') + 1]
        entry = next((e for e in notes if e['version'] == version), None)
        if not entry:
            sys.exit(f'No patch notes for version {version}')
        sys.stdout.write(section(entry, level=2).split('\n', 2)[2])  # the release page has its own title
    elif '--check' in sys.argv:
        if not is_current(notes):
            sys.exit('CHANGELOG.md is out of date with PatchNotes.lua: run python tools/changelog.py')
    else:
        CHANGELOG.write_text(changelog(notes), encoding='utf-8', newline='\n')
        print(f'Wrote {CHANGELOG.relative_to(PROJECT)}')


if __name__ == '__main__':
    main()
