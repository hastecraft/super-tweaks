# Agent notes

## Never write unit tests

Never write unit tests, test suites or test runners unless the user explicitly asks for them. Changes are checked live in game: install them (below) and let the user try them. `tools/mockgame` holds the mocked game runtime that `tools/bench.py` measures with; it is not a test suite, so don't add tests to it.

## Install after every change

WoW loads the addon from its `Interface\AddOns\HastesSuperTweaks` folder (the game folder is `HST_WOW_DIR`, or the default in `tools/install.py`), not from this project. After any change to the addon (code, TOC, art), run:

```
python tools/install.py
```

without asking first, so the change can be tested live. It stages a copy of the addon and installs exactly that; if it fails, report the failure instead of working around it. It can run while WoW is open.

When it finishes, tell the user whether `/reload` is enough or whether a full game restart is needed (new art files and new TOC entries need a restart).

## Patch notes and version: audit on every commit, push and release

Players read the patch notes in the settings window: the version pip beside the window's title opens them, and a blinking dot on it means that account hasn't opened the newest notes yet. The notes are `HastesSuperTweaks/PatchNotes.lua`, newest entry first. The version is `## Version` in `HastesSuperTweaks/HastesSuperTweaks.toc`, which the pip shows. The newest entry's version must always equal the TOC version; a new newest version is what lights the dot.

Before every commit, push or release, without being asked:

1. **Collect what changed for players.** For a commit, the changes being committed; for a push, every commit not on the upstream yet (`git log @{u}..`); for a release, every commit since the previous release's version.
2. **Make sure the notes capture the main changes.** That means new tweaks, new settings and features, changed behavior or defaults, and fixes for problems players could run into. Leave out what players never notice: refactors, invisible performance work, tooling, docs, AGENTS.md, `tools/`. Write one short line per change, under `new`, `changed` or `fixed`, in player terms, and name tweaks as the settings window does. Put the one to four biggest changes of a release under `highlights` as a title and a short text. When a line or highlight is about one tweak, give it `module` (and `setting` when it's about one setting) so players can click through to it; PatchNotes.lua shows the format. If a line already covers the change, extend it rather than adding a duplicate, and fix any line that later work made untrue. Leave shipped entries alone except to correct mistakes.
3. **Set the version from what was added.** The newest entry stays open until it ships: when a commit that carries it is pushed or released, or, with no upstream (`git rev-parse @{u}` fails), when it's committed. If it's still open, add to it. Otherwise start a new entry at the top. Either way, the version is the previous shipped version raised by the biggest step the changes call for:
   - **patch** (1.0.0 to 1.0.1): only fixes and small adjustments;
   - **minor** (1.0.1 to 1.1.0): a new tweak, setting or visible feature;
   - **major** (1.4.2 to 2.0.0): something players lose or have to redo, such as a removed tweak or command, or settings that reset or don't carry over.

   Set the entry's `date` to today (YYYY-MM-DD) and `## Version` in the TOC to the same version, then install as usual. If nothing in a commit is noticeable to players, it gets no entry and no new version.
4. **Say what you did.** Tell the user the version and the lines you added or changed, so they can adjust them before the commit, push or release goes out.
