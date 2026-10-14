"""Installs Haste's Super Tweaks, replacing its own former name, Haste's Simple Tweaks (HastesSimpleTweaks), whose
settings it copies over.

The release is staged first: the addon's files are copied to a temporary folder, and exactly those staged bytes are
installed and zipped. The installed folder is only replaced once a complete copy of the release sits next to it and
matches the staged files; if the swap fails, the old folder is put back.
Migration outputs and the ZIP are verified before live changes. A write-ahead journal and verified backups let the
complete upgrade roll back, including the install record, saved variables and the retired former folder. The ZIP
(dist/ in this checkout) is written once the install is done.

The install record (a copy of what was installed, which an install checks the game's folder against so it never
overwrites changes made there), the journal and the backups are kept per game folder, outside the checkout, so every
checkout and worktree installing into the same game shares them: on Windows in
%LOCALAPPDATA%/HastesSuperTweaks/install/<game folder>. One install into a game folder runs at a time.

WoW may be running for an ordinary update; the last line says whether /reload is enough or the game needs a restart
(a changed TOC or XML include, or new or changed art). WoW must be closed while Haste's Simple Tweaks' saved variables
are copied over (the game rewrites saved variables when it exits) or its folder is removed. Everything replaced is
backed up to backups/<timestamp> there first. The former folder is retired only after the replacement and migration
succeed.

Usage: python tools/install.py [--dry-run]
  HST_WOW_DIR=<folder>   the game folder to install into (the one holding Interface), if not the default below
"""
from pathlib import Path
from datetime import datetime
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / 'tools' / 'mockgame'))
from harness import ADDON, toc_files  # noqa: E402
from lupa.lua51 import LuaRuntime  # noqa: E402

WOW = Path(os.environ.get('HST_WOW_DIR', r'G:\World of Warcraft\_classic_beta_'))  # the game folder holding Interface
ADDONS = WOW / 'Interface' / 'AddOns'
TARGET = ADDONS / 'HastesSuperTweaks'
REPLACED = ['HastesSimpleTweaks']  # the addon's former folder
SAVED, DB = 'HastesSuperTweaks.lua', 'HastesSuperTweaksDB'
OLD_SAVED, OLD_DB = 'HastesSimpleTweaks.lua', 'HastesSimpleTweaksDB'  # the addon's former name
GAME_EXES = {'wow.exe', 'wowb.exe', 'wowt.exe', 'wowclassic.exe', 'wow-64.exe'}


def state_folder():
    """Where installs into this game folder keep their record, journal and backups, shared by every checkout."""
    base = os.environ.get('LOCALAPPDATA') or os.environ.get('XDG_STATE_HOME') or Path.home() / '.local' / 'state'
    where = os.path.normcase(str(TARGET.resolve()))
    name = re.sub(r'[^A-Za-z0-9]+', '-', WOW.name).strip('-')[:40] or 'game'
    return Path(base) / 'HastesSuperTweaks' / 'install' / f"{name}-{hashlib.sha256(where.encode('utf-8')).hexdigest()[:12]}"


STATE = state_folder()
SNAPSHOT = STATE / 'last-installed'
BACKUPS = STATE / 'backups'
# Where each checkout kept its own record and backups before they were shared.
LEGACY_SNAPSHOT = PROJECT / '.last-installed'
LEGACY_BACKUPS = PROJECT / 'backups'
LOCK = None
DIST = PROJECT / 'dist' / 'HastesSuperTweaks.zip'
TOC = 'HastesSuperTweaks.toc'
DRY = '--dry-run' in sys.argv


class InstallError(Exception):
    pass


def step(message):
    print(('[dry run] ' if DRY else '') + message)


def game_running():
    """Running game executables, or None when process inspection could not establish the state."""
    try:
        result = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True, text=True)
        if result.returncode:
            return None
        rows = list(csv.reader(io.StringIO(result.stdout), strict=True))
        if not rows or any(len(row) != 5 or not row[1].strip().isdigit() for row in rows):
            return None
        return sorted({row[0] for row in rows if row[0].lower() in GAME_EXES})
    except (OSError, csv.Error):
        return None


def require_closed(running):
    if running is None:
        raise InstallError('Could not determine whether WoW is running. Saved variables and legacy addons were not changed.')
    if running:
        raise InstallError(f'WoW is running ({", ".join(running)}). Exit the game completely, then run this again.')


def required_files(root=None):
    """The release's files, relative to the addon folder: what the TOC loads, the TOC, the key bindings (which the game
    loads by itself), README and licenses, art."""
    root = root or ADDON
    files = set(toc_files(root)) | {root / name for name in [TOC, 'Bindings.xml', 'README.md', 'LICENSE.txt']}
    files |= {p for p in (root / 'Libs').rglob('*') if p.is_file() and any(t in p.name.lower() for t in ['license', 'copying'])}
    files |= {p for p in (root / 'Art').rglob('*') if p.is_file()}
    # The TOC loads the libraries through XML files, which toc_files follows but does not list.
    files |= {p for p in (root / 'Libs').rglob('*.xml')}
    return sorted(p.relative_to(root) for p in files)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(root):
    """Every file in a folder, by relative path (as a string with forward slashes), with its SHA-256."""
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted(root.rglob('*')) if p.is_file()}


def stage(destination):
    """Copies the release into destination; returns its manifest."""
    for relative in required_files():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ADDON / relative, target)
    staged = manifest(destination)
    for relative in required_files():
        if staged.get(relative.as_posix()) != digest(ADDON / relative):
            raise InstallError(f'{relative} changed while it was being staged; run the installer again.')
    return staged


def restart_reasons(before, after, old_toc, new_toc):
    """Why the game needs a restart rather than /reload to load `after` over `before` (manifests), or []."""
    if before is None:
        return ['the addon is new to this game']
    reasons = []
    if old_toc != new_toc:
        reasons.append('the TOC changed')
    if any(path.endswith('.xml') and before.get(path) != sha for path, sha in after.items()):
        reasons.append('an XML include changed')
    art = [path for path, sha in after.items() if path.startswith('Art/') and before.get(path) != sha]
    if art:
        reasons.append('art was added or changed (' + ', '.join(sorted(art)) + ')')
    return reasons


def rename(source, destination, tries=5):
    """Renames a folder, trying again briefly while something (a virus scanner, the indexer) has a file open."""
    for attempt in range(tries):
        try:
            return source.rename(destination)
        except PermissionError:
            if attempt == tries - 1:
                raise
            time.sleep(0.5)


def replace_folder(source, target, expected):
    """Makes target a verified copy of source (whose manifest is expected) without ever leaving it half-written.
    The copy is made beside target and checked first; target is then swapped for it with two renames. If anything
    fails the old target is put back, and the error is raised. Nothing old is deleted before the new copy is in place:
    a copy that failed its check is moved aside (.failed) rather than deleted, so a locked file can't cost the old one."""
    incoming = target.with_name(target.name + '.incoming')
    outgoing = target.with_name(target.name + '.outgoing')
    failed = target.with_name(target.name + '.failed')
    for leftover in (incoming, failed):
        if leftover.exists():
            shutil.rmtree(leftover)
    if outgoing.exists():
        raise InstallError(f'{outgoing} is left from an earlier install; recover_folder should have handled it.')
    try:
        shutil.copytree(source, incoming)
        if manifest(incoming) != expected:
            raise InstallError(f'the copy at {incoming} does not match the staged release')
    except BaseException:
        shutil.rmtree(incoming, ignore_errors=True)
        raise
    moved = False
    try:
        if target.exists():
            rename(target, outgoing)
            moved = True
        rename(incoming, target)
        if manifest(target) != expected:
            raise InstallError(f'{target} does not match the staged release after the swap')
    except BaseException:
        if moved:
            if target.exists():
                rename(target, failed)
            rename(outgoing, target)
        shutil.rmtree(incoming, ignore_errors=True)
        shutil.rmtree(failed, ignore_errors=True)
        raise
    if moved:
        shutil.rmtree(outgoing, ignore_errors=True)


def recover_folder(target, keep):
    """Deals with a swap an interrupted install left behind. A lone old copy (.outgoing) is put back. When both the
    folder and an old copy exist, it isn't known which is complete, so the old copy is moved to `keep` (a backups
    folder) rather than deleted; the check against the install record then decides whether the folder can be
    replaced."""
    outgoing = target.with_name(target.name + '.outgoing')
    for leftover in (target.with_name(target.name + '.incoming'), target.with_name(target.name + '.failed')):
        if leftover.exists() and not DRY:
            shutil.rmtree(leftover)
    if not outgoing.exists():
        return
    if not target.exists():
        print(f'Restoring {target} from {outgoing}, left by an interrupted install.')
        if not DRY:
            rename(outgoing, target)
    else:
        print(f'Moving {outgoing}, left by an interrupted install, to {keep}.')
        if not DRY:
            keep.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(outgoing), str(keep))


def needs_rename(account):
    """True when the account has settings saved under the addon's former name but none under its new one."""
    saved = account / 'SavedVariables'
    return (saved / OLD_SAVED).exists() and not (saved / SAVED).exists()


def write_verified(path, text, check):
    """Writes text to path through a temporary file beside it, moved into place once check(temporary) passes."""
    temporary = path.with_name(path.name + '.tmp')
    try:
        temporary.write_text(text, encoding='utf-8')
        check(temporary)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def serialized(path, name):
    """The table a saved variables file assigns to `name`, as canonical Lua source (keys sorted)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((PROJECT / 'tools' / 'migrate.lua').read_text(encoding='utf-8'))
    lua.execute(path.read_text(encoding='utf-8'))
    if lua.eval(f'type({name})') != 'table':
        raise InstallError(f'{path} does not hold {name}')
    return lua.eval(f"HST_Serialize('{DB}', {name})")


def renamed_text(path):
    """The former name's saved variables file with its one variable renamed, every value left byte for byte."""
    text = path.read_text(encoding='utf-8')
    assignments = [line for line in text.splitlines() if re.match(r'[A-Za-z_]\w*\s*=', line)]
    if len(assignments) != 1 or not assignments[0].startswith(OLD_DB + ' = '):
        raise InstallError(f'{path} has an unexpected layout; nothing was installed.')
    return text.replace(OLD_DB + ' = ', DB + ' = ', 1)


def prepare_migration(account, destination):
    """Builds and verifies the account's carried-over settings in staging, returning their summary and input
    fingerprints. Settings saved under the former name are copied unchanged (checked value for value against the
    original)."""
    saved = account / 'SavedVariables'
    old, new = saved / OLD_SAVED, saved / SAVED
    inputs = {path: digest(path) if path.exists() else None for path in (old, new)}
    source = renamed_text(old)

    def check(path):
        if serialized(path, DB) != serialized(old, OLD_DB):
            raise InstallError(f'the copied settings in {path} differ from {old}')

    write_verified(destination, source, check)
    return f"Haste's Simple Tweaks settings copied from {OLD_SAVED}", inputs


def build_zip(release, expected, destination):
    """Zips the staged release under HastesSuperTweaks/, checks the archive against the staged files, then moves it
    into place."""
    temporary = destination.with_name(destination.name + '.tmp')
    destination.parent.mkdir(exist_ok=True)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as z:
            for relative in sorted(expected):
                z.write(release / relative, 'HastesSuperTweaks/' + relative)
        with zipfile.ZipFile(temporary) as z:
            if z.testzip() is not None:
                raise InstallError('the ZIP failed its integrity check')
            zipped = {name[len('HastesSuperTweaks/'):]: hashlib.sha256(z.read(name)).hexdigest() for name in z.namelist()}
        if zipped != expected:
            raise InstallError('the ZIP does not match the staged release')
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def content_state(path, directory):
    if not path.exists():
        return None
    return manifest(path) if directory else digest(path)


def copy_verified_file(source, target, expected):
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.tmp')
    try:
        shutil.copy2(source, temporary)
        if digest(temporary) != expected:
            raise InstallError(f'{temporary} does not match the prepared file')
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()


def closed_game_target(target):
    return target in [ADDONS / name for name in REPLACED] or target.name == SAVED


def validate_target(target, directory):
    """Only the installer's explicit destinations can be restored or removed by a recovery record."""
    target = target.resolve()
    folders = [TARGET, SNAPSHOT, LEGACY_SNAPSHOT] + [ADDONS / name for name in REPLACED]
    if directory and target in [path.resolve() for path in folders]:
        return target
    if not directory and target == DIST.resolve():
        return target
    accounts = (WOW / 'WTF' / 'Account').resolve()
    if not directory and target.name == SAVED and target.parent.name == 'SavedVariables' and target.parent.parent.parent == accounts:
        return target
    raise InstallError(f'Unexpected recovery destination: {target}')


def remove_live(path, directory):
    path = validate_target(path, directory)
    if directory:
        shutil.rmtree(path)
    else:
        path.unlink()


class Upgrade:
    """Small write-ahead record for this installer's known destinations, with full-upgrade rollback."""

    def __init__(self, backup, record=None, path=None):
        self.path = path or BACKUPS / 'pending-install.json'
        self.backup = backup.resolve()
        self.record = record or {'version': 1, 'backup': str(self.backup), 'started': 0, 'complete': False, 'entries': []}
        self.sources = []

    def save(self):
        write_verified(self.path, json.dumps(self.record, indent=2), lambda path: json.loads(path.read_text(encoding='utf-8')))

    def add(self, target, source, directory, relative_backup):
        target = validate_target(target, directory)
        before = content_state(target, directory)
        kept = self.backup / relative_backup
        if before is not None:
            kept.parent.mkdir(parents=True, exist_ok=True)
            if directory:
                shutil.copytree(target, kept)
            else:
                shutil.copy2(target, kept)
            if content_state(kept, directory) != before:
                raise InstallError(f'Backup verification failed for {target}; nothing was installed.')
        self.record['entries'].append({'target': str(target), 'directory': directory, 'backup': relative_backup,
                                       'before': before, 'after': content_state(source, directory) if source else None})
        self.sources.append(source)

    def rollback(self):
        for index in range(self.record['started'] - 1, -1, -1):
            entry = self.record['entries'][index]
            directory = entry['directory']
            target = validate_target(Path(entry['target']), directory)
            kept = (self.backup / entry['backup']).resolve()
            if not kept.is_relative_to(self.backup):
                raise InstallError('Recovery backup path is outside its backup directory.')
            if directory:
                recovery = self.backup / 'interrupted' / str(index)
                suffix = 0
                while recovery.exists():
                    suffix += 1
                    recovery = self.backup / 'interrupted' / f'{index}-{suffix}'
                recover_folder(target, recovery)
            current = content_state(target, directory)
            if current != entry['before']:
                partial_retirement = (directory and entry['after'] is None and isinstance(current, dict)
                                      and isinstance(entry['before'], dict)
                                      and all(entry['before'].get(name) == sha for name, sha in current.items()))
                if current is not None and current != entry['after'] and not partial_retirement:
                    raise InstallError(f'{target} changed outside the installer; it and the backup were preserved for review.')
                if closed_game_target(target):
                    require_closed(game_running())
                if entry['before'] is None:
                    if target.exists():
                        remove_live(target, directory)
                else:
                    if content_state(kept, directory) != entry['before']:
                        raise InstallError(f'The recovery backup for {target} failed verification.')
                    if directory:
                        replace_folder(kept, target, entry['before'])
                    else:
                        copy_verified_file(kept, target, entry['before'])
            self.record['started'] = index
            self.save()
        self.path.unlink()

    def commit(self):
        self.save()
        try:
            for index, (entry, source) in enumerate(zip(self.record['entries'], self.sources)):
                target, directory = Path(entry['target']), entry['directory']
                if closed_game_target(target):
                    require_closed(game_running())
                if content_state(target, directory) != entry['before']:
                    raise InstallError(f'{target} changed while the release was prepared.')
                self.record['started'] = index + 1
                self.save()  # durable before the mutation, including an interruption halfway through it
                if source is None:
                    remove_live(target, directory)
                elif directory:
                    replace_folder(source, target, entry['after'])
                else:
                    copy_verified_file(source, target, entry['after'])
            self.record['complete'] = True
            self.save()
        except Exception as error:
            try:
                self.rollback()
            except Exception as recovery_error:
                raise InstallError(f'Install failed ({error}). Recovery is pending in {self.path}: {recovery_error}') from error
            raise InstallError(f'Install failed ({error}); the previous installation and settings were restored.') from error
        try:
            self.path.unlink()
        except OSError:
            print(f'Installation completed; the next run will clear its completed record at {self.path}.')


def recover_upgrade(backups):
    path = backups / 'pending-install.json'
    if not path.exists():
        return
    record = json.loads(path.read_text(encoding='utf-8'))
    backup = Path(record['backup']).resolve()
    if record.get('version') != 1 or not backup.is_relative_to(backups.resolve()) or backup == backups.resolve():
        raise InstallError(f'Invalid recovery record at {path}; review it before installing.')
    if DRY:
        raise InstallError(f'An earlier install needs recovery from {path}. Run without --dry-run to recover it.')
    if record['complete']:
        path.unlink()
    else:
        print(f'Recovering the previous installation from {backup}.')
        Upgrade(backup, record, path).rollback()


def legacy_snapshots():
    """The install records checkouts kept before the shared one: this checkout's, then the main checkout's."""
    found = [LEGACY_SNAPSHOT]
    try:
        common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=PROJECT,
                                capture_output=True, text=True)
        if common.returncode == 0 and common.stdout.strip():
            main = Path(common.stdout.strip()).parent / '.last-installed'
            if main.resolve() != LEGACY_SNAPSHOT.resolve():
                found.append(main)
    except OSError:
        pass
    return found


def unrecorded(snapshot):
    """The first file in the installed folder that differs from the install record `snapshot`, or None."""
    for path in TARGET.rglob('*'):
        if path.is_file():
            recorded = snapshot / path.relative_to(TARGET)
            if not (recorded.is_file() and recorded.read_bytes() == path.read_bytes()):
                return path
    return None


def lock_state():
    """Holds the game folder's install lock until the process ends; raises when another install holds it."""
    STATE.mkdir(parents=True, exist_ok=True)
    handle = open(STATE / 'lock', 'a+b')
    try:
        if os.name == 'nt':
            import msvcrt
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        raise InstallError(f'Another install into {WOW} is running; run this again when it has finished.')
    return handle


def install():
    if not ADDONS.is_dir():
        raise InstallError(f'No AddOns folder at {ADDONS}. Set HST_WOW_DIR to your game folder (the one holding '
                           'Interface).')
    global LOCK
    LOCK = lock_state()  # held until the process ends
    for backups in (LEGACY_BACKUPS, BACKUPS):
        recover_upgrade(backups)
    # WoW only has to be closed while there is saved data to migrate or an old addon to remove.
    accounts = [a for a in (WOW / 'WTF' / 'Account').glob('*') if (a / 'SavedVariables').is_dir()]
    pending = [a for a in accounts if needs_rename(a)]
    running = game_running()
    legacy = [ADDONS / name for name in REPLACED if (ADDONS / name).exists()]
    if pending or legacy:
        require_closed(running)
    zip_error = None
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    recover_folder(TARGET, BACKUPS / f'{stamp}-interrupted' / 'AddOns' / TARGET.name)
    recover_folder(SNAPSHOT, BACKUPS / f'{stamp}-interrupted' / SNAPSHOT.name)

    with tempfile.TemporaryDirectory(prefix='hst-release-') as temporary:
        release = Path(temporary) / 'HastesSuperTweaks'
        step('Staging the release')
        try:
            expected = stage(release)
        except InstallError as error:
            sys.exit(f'{error} Nothing was installed.')
        step(f'Staged {len(expected)} files')

        # Prepare every fallible output before changing any live destination, including in a dry run.
        prepared_zip = Path(temporary) / 'HastesSuperTweaks.zip'
        build_zip(release, expected, prepared_zip)
        migrations, inputs = [], {}
        for index, account in enumerate(pending):
            prepared = Path(temporary) / f'migrated-{index}.lua'
            summary, fingerprints = prepare_migration(account, prepared)
            inputs.update(fingerprints)
            migrations.append((account, prepared))
            step(f'Carrying over settings for account {account.name}: {summary}')

        if TARGET.exists():
            # The shared record, or one a checkout kept before there was one (an older installer may still use them).
            snapshots = [path for path in [SNAPSHOT] + legacy_snapshots() if path.is_dir()]
            if not snapshots:
                sys.exit(f'{TARGET} exists but there is no record of installing it; review it first.')
            changed = [unrecorded(snapshot) for snapshot in snapshots]
            if all(changed):
                sys.exit(f'{changed[0]} changed since the last install; review it first. Nothing was installed.')
        before = manifest(TARGET) if TARGET.exists() else None
        old_toc = (TARGET / TOC).read_bytes() if (TARGET / TOC).is_file() else None
        reasons = restart_reasons(before, expected, old_toc, (release / TOC).read_bytes())

        backup, n = BACKUPS / stamp, 1
        while backup.exists():
            n += 1
            backup = BACKUPS / f'{stamp}-{n}'
        step(f'Backing up to {backup}')
        step(f'Installing {len(expected)} files to {TARGET}')
        if not DRY:
            backup.mkdir(parents=True, exist_ok=True)
            upgrade = Upgrade(backup)
            upgrade.add(TARGET, release, True, 'AddOns/HastesSuperTweaks')
            upgrade.add(SNAPSHOT, release, True, '.last-installed')
            for account, prepared in migrations:
                saved = account / 'SavedVariables'
                upgrade.add(saved / SAVED, prepared, False, f'WTF/{account.name}/{SAVED}')
                for pattern in [OLD_SAVED + '*', SAVED + '.bak']:
                    for path in saved.glob(pattern):
                        kept = backup / 'WTF' / account.name / path.name
                        kept.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(path, kept)
            for target in legacy:
                upgrade.add(target, None, True, 'AddOns/' + target.name)
            for path, fingerprint in inputs.items():
                if content_state(path, False) != fingerprint:
                    raise InstallError(f'{path} changed while migration was prepared; nothing was installed.')
            if pending or legacy:
                require_closed(game_running())
            upgrade.commit()
            # The ZIP is a build output, not part of the install: failing to write it leaves the install done.
            try:
                copy_verified_file(prepared_zip, DIST, digest(prepared_zip))
            except (OSError, InstallError) as error:
                zip_error = error

    if running == []:
        advice = 'Start WoW; /hst opens the settings.'
    elif reasons:
        advice = 'Restart WoW to load this update (' + '; '.join(reasons) + '); /reload is not enough.'
    else:
        advice = '/reload in game to apply.'
    print(f'Dry run complete; nothing changed. Installing would need: {advice}' if DRY else f'Done. {advice}')
    if zip_error:
        sys.exit(f'The addon was installed, but the release ZIP at {DIST} could not be written: {zip_error}')


def main():
    try:
        install()
    except (OSError, InstallError) as error:
        sys.exit(str(error))


if __name__ == '__main__':
    main()
