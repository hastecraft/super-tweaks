"""Loads Haste's Super Tweaks into a fresh Lua 5.1 runtime: game API mocks, the real embedded
libraries, then the addon files in TOC order. Call start(lua) to fire ADDON_LOADED and PLAYER_LOGIN.
Used by tools/bench.py; tools/install.py uses toc_files and the bundled lupa."""
from pathlib import Path
import os
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
# The addon folder to load: the project's, or another copy (tools/bench.py can measure an older one).
ADDON = Path(os.environ.get('HST_ADDON_DIR') or PROJECT / 'HastesSuperTweaks')
sys.path.insert(0, str(HERE / 'pydeps'))
from lupa.lua51 import LuaRuntime  # noqa: E402


def toc_files(root=ADDON):
    """Lua files in load order, following XML includes."""
    files = []

    def visit(path):
        assert path.is_file(), f'Missing TOC/XML reference: {path}'
        if path.suffix.lower() == '.xml':
            for node in ET.parse(path).getroot():
                if node.attrib.get('file'):
                    visit(path.parent / node.attrib['file'].replace('\\', '/'))
        elif path.suffix.lower() == '.lua':
            files.append(path)
    for line in (root / 'HastesSuperTweaks.toc').read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            visit(root / line.replace('\\', '/'))
    return files


def new_runtime(prelude=None, root=ADDON):
    """prelude runs after the mocks and before the libraries (saved variables, API overrides)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("io.stdout:setvbuf('no')")  # keep Lua and Python output in order
    lua.execute((HERE / 'events_70205.lua').read_text(encoding='utf-8'))
    lua.execute((HERE / 'wow_mock.lua').read_text(encoding='utf-8'))
    if prelude:
        lua.execute(prelude)
    compile_lua = lua.eval('function(source, name) local fn, err = loadstring(source, name); assert(fn, err); return fn end')
    ns = lua.table()
    for path in toc_files(root):
        chunk = compile_lua(path.read_text(encoding='utf-8-sig'), path.relative_to(root).as_posix())
        if 'Libs' in path.parts:
            chunk()
        else:
            chunk('HastesSuperTweaks', ns)
    return lua


def start(lua):
    """Drive AceAddon's initialize/enable queue the way the client does at login."""
    lua.execute('''
        local frame = LibStub('AceAddon-3.0').frame
        frame.scripts.OnEvent(frame, 'ADDON_LOADED', 'HastesSuperTweaks')
        state.loggedIn = true
        frame.scripts.OnEvent(frame, 'PLAYER_LOGIN')
        assert(#ERRORS == 0, 'errors during load: ' .. table.concat(ERRORS, '\\n'))
    ''')

