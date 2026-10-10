"""Compares two runs of `python tools/bench.py --json` (a pull request's base and head) and prints a GitHub-flavored
markdown report: a verdict, a table of the scenarios whose numbers changed, and the scenarios added or removed.

Usage: python tools/bench_compare.py BASE.json HEAD.json
Exits 1 when a scenario both runs have got more expensive:
  - any count went up: API calls, widget calls, frames or regions created, or handlers (calls from the game into the
    addon). Counts are exact and the same on every run, so any increase is real.
  - allocated bytes went up by more than the noise allowance, max(16 B + 4096 B / runs, 1% of the base), per run.
    A run of the bench is exactly repeatable (the same numbers every time, on Windows and Linux alike), but Lua 5.1
    places table keys that are tables or functions by their address, so when such a table grows (a rehash) depends
    on where earlier objects landed, which changes whenever the addon's code allocates differently anywhere before.
    Measured from 24 different memory layouts, the same code varied by up to about 2 KB in total for a scenario (a
    cold single run: a login, a first nameplate number) and by under 80 B per run for scenarios averaged over 30 or
    more runs; counts never varied. The allowance is at least twice the largest variation seen, and still catches a
    new table made per run (an empty one is 56 B) in the scenarios measured 300 times, and 60 B or more per run in
    those measured 100 times.
Standard library only."""
import json
import sys

COUNTS = (('api', 'API'), ('widget', 'Widget'), ('frames', 'Frames'), ('regions', 'Regions'), ('handlers', 'Handlers'))
EPSILON = 0.0005  # counts are rounded to 3 decimals per run


def allowance(base, runs):
    return max(16 + 4096 / max(1, runs or 1), 0.01 * abs(base))


def number(value):
    text = f'{value:,.3f}'.rstrip('0').rstrip('.')
    return '0' if text in ('-0', '') else text


def signed(delta):
    return ('+' if delta > 0 else '') + number(delta)


def compare(base, head):
    """Per scenario both runs have: {metric: (base, head, verdict)} for the metrics that changed, where verdict is
    'worse' or 'better'."""
    changes = {}
    for name in base.keys() & head.keys():
        old, new, changed = base[name], head[name], {}
        for key, _ in COUNTS:
            if key in old and key in new and abs(new[key] - old[key]) > EPSILON:
                changed[key] = (old[key], new[key], 'worse' if new[key] > old[key] else 'better')
        if 'bytes' in old and 'bytes' in new:
            delta = new['bytes'] - old['bytes']
            if abs(delta) > allowance(old['bytes'], new.get('runs', old.get('runs'))):
                changed['bytes'] = (old['bytes'], new['bytes'], 'worse' if delta > 0 else 'better')
        if changed:
            changes[name] = changed
    return changes


def cell(entry, key, changed):
    if key in changed:
        old, new, verdict = changed[key]
        text = f'{number(old)} -> {number(new)} ({signed(new - old)})'
        return f'**{text}**' if verdict == 'worse' else text
    return number(entry[key]) if key in entry else ''


def report(base, head):
    changes = compare(base, head)
    worse = sorted(name for name, changed in changes.items() if any(v == 'worse' for *_, v in changed.values()))
    better = sorted(name for name in changes if name not in worse)
    added = [name for name in head if name not in base]
    removed = [name for name in base if name not in head]
    common = len(base.keys() & head.keys())
    lines = ['## Benchmark: base vs head', '']
    if worse:
        lines.append(f'**Regression: {len(worse)} scenario{"s" if len(worse) != 1 else ""} got more expensive.** '
                     + (f'{len(better)} got cheaper. ' if better else '') + f'{common} scenarios compared.')
    elif better:
        lines.append(f'**No regressions.** {len(better)} scenario{"s" if len(better) != 1 else ""} got cheaper; '
                     f'{common} scenarios compared.')
    elif not added and not removed:
        lines.append(f'**No changes.** All {common} scenarios measured the same (allocation within noise).')
    else:
        lines.append(f'**No regressions.** The {common} scenarios both runs have measured the same.')
    if changes:
        lines += ['', 'Per run of each scenario; **bold** is more expensive. Allocation within max(16 B + 4096 B / runs, '
                  '1%) of the base is noise and not shown as a change.', '',
                  '| Scenario | ' + ' | '.join(title for _, title in COUNTS) + ' | Bytes |',
                  '|---|' + '---:|' * (len(COUNTS) + 1)]
        for name in worse + better:
            entry, changed = head[name], changes[name]
            cells = [cell(entry, key, changed) for key, _ in COUNTS] + [cell(entry, 'bytes', changed)]
            lines.append('| ' + name.replace('|', '\\|') + ' | ' + ' | '.join(cells) + ' |')
    for title, names in (('New scenarios', added), ('Removed scenarios', removed)):
        if names:
            lines += ['', f'{title} ({len(names)}):', '']
            lines += ['- ' + name for name in names]
    return '\n'.join(lines), bool(worse)


def main(argv):
    if len(argv) != 3:
        print(__doc__.split('\n\n')[0], file=sys.stderr)
        print('Usage: python tools/bench_compare.py BASE.json HEAD.json', file=sys.stderr)
        return 2
    with open(argv[1], encoding='utf-8') as f:
        base = json.load(f)
    with open(argv[2], encoding='utf-8') as f:
        head = json.load(f)
    text, failed = report(base, head)
    print(text)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
