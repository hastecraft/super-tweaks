# Contributing to Haste's Super Tweaks

Thanks for helping. Fixes and new tweaks are both welcome. If you use an AI agent, it follows [AGENTS.md](AGENTS.md), which holds the same rules.

## Before you start

For a bug or a small fix, open a pull request straight away. For a new tweak or a bigger change, open an issue or a discussion first, so we can agree on the idea before you build it. Tweaks should add something the game doesn't already do.

By contributing, you agree that your work is licensed under the [MPL-2.0](LICENSE), like the rest of the code. The name and logo aren't part of that license: see [TRADEMARKS.md](TRADEMARKS.md).

## Setup

1. Fork the repository and clone your fork.
2. Install Python 3 and the tools' packages:

   ```bash
   python -m pip install -r tools/requirements.txt
   ```

3. Point the installer at your game folder, the one holding `Interface`. On Windows, in PowerShell:

   ```powershell
   $env:HST_WOW_DIR = "C:\Program Files (x86)\World of Warcraft\_classic_"
   ```

4. Run `python tools/install.py`. It copies the addon into your game's `Interface\AddOns\HastesSuperTweaks` and backs up what it replaces. Run it after every change, then `/reload` in game. New files in the TOC and new art need a full game restart.

## Making a change

- Work on a branch, and keep each pull request to one change.
- Match the code around you: its naming, comment style and structure.
- Test in game. CI can't run the game, so say in the pull request which client you tested on (WoW Forever or Classic Era) and what you did.
- Mind the cost. The addon promises minimal performance impact. Prefer events over OnUpdate, register frequent events only while needed, make no garbage per event, and make sure a turned-off tweak costs nothing. [AGENTS.md](AGENTS.md#cost-as-little-as-possible) has the details.
- Some APIs return hidden values in restricted situations. Check them with `ns.IsSecret(x)` before testing, comparing or indexing them.
- Don't add unit tests; changes are checked in game.

## Commit messages and pull request titles

Commits and pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
type(scope): summary in the imperative
```

| Type | For |
| --- | --- |
| `feat` | a new tweak, setting or visible feature |
| `fix` | a fix for a problem players could run into |
| `perf` | less CPU, memory or garbage, with no visible change |
| `refactor` | code changes with no change in behavior |
| `docs` | README, CONTRIBUTING and other docs |
| `ci`, `build` | GitHub workflows, packaging, `tools/` |
| `chore` | anything else, including releases (`chore(release): 1.2.0`) |
| `revert` | undoing an earlier commit |

The scope is optional: the tweak or area it touches, in kebab case, such as `sell-clutter`, `tooltips` or `settings`. If players lose something or have to redo it (a removed tweak or command, settings that reset), add `!` after the type or scope (`feat!: remove Flash Taskbar on Whisper`) or a `BREAKING CHANGE:` footer.

Pull requests are squash-merged, so the pull request's title becomes the commit on `master`, and CI checks that it follows the format. The type hints at the version step too: `fix` is a patch, `feat` a minor version and `!` a major one.

## Patch notes and versions

Don't edit the patch notes entries in `PatchNotes.lua`, the TOC's `## Version` or `CHANGELOG.md`. Instead, write one line for players under "For the patch notes" in your pull request, in game terms, naming the tweak as the settings window does. The maintainer writes the patch notes and picks the version when releasing. CI fails pull requests that change these.

## Measuring performance

```bash
python tools/bench.py
```

This loads the addon into a mocked game and counts the work done per operation on its hot paths: game API calls, widget calls, frames and regions created, event handlers run, and memory allocated. It covers every tweak's frequent events, a login, and each tweak alone, and checks that turned-off tweaks cost nothing. The counts are the same on every run, so compare before and after your change. CI runs the bench on every pull request and on its base branch, and posts the difference in the Performance check's summary. Only a major regression fails the check: any more work with every tweak off, new garbage per run on a tweak's own hot paths, or a count there up by more than 10%. Scenarios with every tweak on are reported only, since a new tweak always adds work there. The maintainer can accept a regression that's worth it with the `perf-accepted` label. If you add something that runs often, add a scenario for it to `tools/bench.py`.

The bench counts work; it doesn't time the real game. For a real-world check, compare FPS in a busy spot with the tweak on and off.

## Pull request checks

Every pull request runs:

| Check | What it does |
| --- | --- |
| PR title | The title follows [Conventional Commits](#commit-messages-and-pull-request-titles). |
| Lint | [luacheck](https://github.com/lunarmodules/luacheck) with `.luacheckrc`: accidental globals, unused variables, syntax errors. |
| Checks | `tools/check.py`: the TOC's files exist, and the patch notes and version are untouched (the maintainer's `patch-notes-fix` label allows correcting shipped patch notes). |
| Performance | The bench comparison described above. |
| Package | Builds the addon ZIP. Download it from the run's artifacts to try the pull request in game. |

## Reporting bugs and security problems

Use the issue forms for bugs, ideas and performance problems. Report security problems privately: see [SECURITY.md](SECURITY.md).
