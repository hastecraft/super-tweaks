# Haste's Super Tweaks

Small quality-of-life tweaks for WoW Forever, all in one settings window: an XP tracker, better tooltips and combat text, a compact loot window, automatic junk and clutter selling, quest and NPC shortcuts, auto-decline and more. Classic Era is listed in the TOC too.

Type `/hst` in game to open the settings. The full list of tweaks and how each behaves is in [HastesSuperTweaks/README.md](HastesSuperTweaks/README.md).

## Install

1. Download the ZIP from the latest [release](../../releases).
2. Unzip it into your game's `Interface\AddOns` folder, so that you get `Interface\AddOns\HastesSuperTweaks`.
3. Restart the game.

## Development

The addon is the `HastesSuperTweaks` folder. The scripts in `tools` need Python 3 with `pip install lupa pillow`.

- `python tools/install.py` installs the addon into the game and builds the release ZIP in `dist`. Set `HST_WOW_DIR` to your game folder (the one holding `Interface`). `--dry-run` shows what it would do.
- `python tools/make_art.py` redraws the icons in `HastesSuperTweaks/Art`.
- `python tools/bench.py` counts the work done on the addon's hot paths in a mocked game runtime (`tools/mockgame`), to compare two versions.

## License

The code is licensed under the [Mozilla Public License 2.0](LICENSE). The name and logo are not covered by it: see [TRADEMARKS.md](TRADEMARKS.md). The embedded libraries keep their own licenses, listed in [HastesSuperTweaks/Libs/THIRD-PARTY-LICENSES.txt](HastesSuperTweaks/Libs/THIRD-PARTY-LICENSES.txt).
