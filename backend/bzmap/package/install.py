"""Copy a generated map into a separate test mod dir for local testing.

docs/07 §"Local testing install" is the contract:

- **Never test by copying into the installed corpus pack's directory.** Install to a separate
  location so the installed pack stays pristine and Steam does not overwrite or revalidate
  the work:

      <game root>/mods/<test-id>/

  ``RequireFix``'s GOG path already searches ``mods/``, so a map installed
  there is loadable without touching the installed pack or the workshop directory.
- ``modEnabled.dat`` controls which mod is active. It must be **snapshotted
  before** it is changed and **restored afterwards**.

This module takes the *game root* (the directory that contains ``mods/`` and
``modEnabled.dat``) as an explicit parameter. It never writes anywhere outside
that root's ``mods/<test-id>/`` subdirectory and the ``modEnabled.dat`` file —
in particular it never writes into the installed pack's workshop directory. Tests pass a
``tmp_path`` game root so no real game install is ever touched.
"""

from __future__ import annotations

import shutil
from pathlib import Path

# The mod-enabled marker file in the game root whose contents select the
# active mod (docs/07). It sits beside ``mods/``.
MOD_ENABLED_NAME = "modEnabled.dat"


class InstallError(RuntimeError):
    """Raised when an install cannot be completed safely."""


def mod_dir(game_root, test_id):
    """Return the test mod directory ``<game_root>/mods/<test_id>``.

    Does not create it; callers that want it to exist use
    :func:`install_map`.
    """
    return Path(game_root) / "mods" / test_id


def install_map(game_root, test_id, files):
    """Copy ``files`` into ``<game_root>/mods/<test_id>/`` and return the dir.

    ``game_root`` is the game directory that contains ``mods/`` (the operator
    points it at the real install; tests use a scratch dir). ``files`` is an
    iterable of paths or an iterable of ``(source, dest_name)`` pairs; a plain
    path is copied under its own basename.

    The destination directory is created (parents included). Only the files
    named in ``files`` are written — nothing under the installed pack's workshop directory is
    touched. If a destination file already exists it is overwritten, which is
    the desired behaviour for re-installing the same ``test_id``.
    """
    dest_dir = mod_dir(game_root, test_id)
    dest_dir.mkdir(parents=True, exist_ok=True)

    for item in files:
        if isinstance(item, (tuple, list)):
            source, name = item
        else:
            source, name = item, Path(item).name
        source = Path(source)
        if not source.is_file():
            raise InstallError(f"source file not found: {source}")
        shutil.copy2(source, dest_dir / name)

    return dest_dir


def snapshot_mod_enabled(game_root):
    """Return the raw ``modEnabled.dat`` bytes, or ``None`` if it is absent.

    The snapshot is used to restore the previous active-mod selection after a
    test launch, per docs/07. ``None`` means the file did not exist, so
    :func:`restore_mod_enabled` will remove it rather than recreate it.
    """
    path = Path(game_root) / MOD_ENABLED_NAME
    if not path.exists():
        return None
    return path.read_bytes()


def restore_mod_enabled(game_root, snapshot):
    """Restore a :func:`snapshot_mod_enabled` snapshot.

    If ``snapshot`` is ``None`` the file is removed (it did not exist when
    snapshotted); otherwise its previous bytes are written back verbatim.
    """
    path = Path(game_root) / MOD_ENABLED_NAME
    if snapshot is None:
        path.unlink(missing_ok=True)
        return
    path.write_bytes(snapshot)


def set_mod_enabled(game_root, test_id):
    """Write ``modEnabled.dat`` selecting ``test_id`` as the active mod.

    Returns the previous snapshot (see :func:`snapshot_mod_enabled`) so the
    caller can restore it afterwards. Callers should snapshot *before* calling
    this (or use the return value) and restore in a ``finally``.
    """
    previous = snapshot_mod_enabled(game_root)
    (Path(game_root) / MOD_ENABLED_NAME).write_text(test_id, encoding="ascii")
    return previous