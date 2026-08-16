"""Assemble ``build/Expansion-Pack/`` — the flat workshop item layout (docs/07).

BZ98R workshop items are **flat**: every file sits at the item root, no
subdirectories for map content (docs/07 §"Pack layout"). For each map the pack
carries the terrain, mission and metadata files plus a per-map thumbnail, and a
single top-level ``preview.png`` is the workshop item thumbnail:

    build/Expansion-Pack/
    ├── <map>.trn  <map>.hg2  <map>.mat  <map>.lgt  <map>.vxt
    ├── <map>.bzn  <map>_S.bzn  <map>_SW.bzn  [<map>_ST.bzn]
    ├── <map>.ini  <map>.des  <map>.odf  <map>.lua
    ├── <map>.png  <map>.bmp
    ├── ... × 10 maps
    └── preview.png

This module copies an already-generated, already-validated set of per-map files
into that flat layout. It does **not** run the generator or the validators — the
caller assembles candidate files (all of which must already have passed Tier 1-3
validation) into a staging directory, and this module flattens them into the
pack. The only file it creates itself is the top-level ``preview.png`` workshop
thumbnail.

The pack is written into ``build/`` per AGENTS.md rule 2 — never into the installed pack or the
installed game.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

# The per-map file suffixes that make up one map's entry in the flat pack
# (docs/07 §"Pack layout"). ``.bzn`` covers the base terrain and the ``_S`` /
# ``_ST`` / ``_SW`` variants, which share the ``.bzn`` extension and differ only
# in basename.
MAP_SUFFIXES = (
    ".trn",
    ".hg2",
    ".mat",
    ".lgt",
    ".vxt",
    ".bzn",
    ".ini",
    ".des",
    ".odf",
    ".lua",
    ".png",
    ".bmp",
    # Per-map generated geometry (bzmap.generate.meshgen — water surfaces,
    # plant fields): the OGRE mesh, its material, and any texture it adds.
    ".mesh",
    ".material",
    ".dds",
)

#: Default workshop item thumbnail size in pixels (docs/07, thumbnail.py).
PREVIEW_SIZE = (512, 512)


class AssembleError(RuntimeError):
    """Raised when the pack cannot be assembled from the given staging dir."""


def _map_files(source_dir):
    """Yield every staged per-map file in ``source_dir``.

    The staging directory holds the generated map files flat (the natural form
    after the per-map writers run). Yields ``(basename, path)`` pairs where
    ``basename`` is the file's name as it should appear in the pack and ``path``
    is the source file. Non-map files (e.g. a candidate ``report.json`` or a
    ``preview.png``) are ignored here.
    """
    for path in sorted(source_dir.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() in MAP_SUFFIXES:
            yield path.name, path


def assemble_pack(source_dir, dest_dir, *, preview=None):
    """Assemble the flat pack into ``dest_dir`` from ``source_dir``.

    ``source_dir`` is a directory of generated per-map files (all already
    validated). Every recognized map file is copied flat into ``dest_dir``
    (created if absent). ``preview`` is an optional ``PIL.Image`` written as the
    workshop item thumbnail ``preview.png`` at the pack root; if omitted, a
    ``preview.png`` already present in ``source_dir`` is copied instead. If
    neither is available an :class:`AssembleError` is raised.

    Returns the pack directory (``dest_dir``).
    """
    source_dir = Path(source_dir)
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)

    copied = 0
    for name, path in _map_files(source_dir):
        shutil.copy2(path, dest_dir / name)
        copied += 1

    if copied == 0:
        raise AssembleError(
            f"no map files found in staging dir: {source_dir}"
        )

    _write_preview(source_dir, dest_dir, preview)
    return dest_dir


def _write_preview(source_dir, dest_dir, preview):
    """Write the pack ``preview.png`` from ``preview`` or the staging dir."""
    dest = dest_dir / "preview.png"
    if preview is not None:
        _resized(preview, PREVIEW_SIZE).save(dest, format="PNG")
        return
    staged = source_dir / "preview.png"
    if staged.is_file():
        shutil.copy2(staged, dest)
        return
    raise AssembleError(
        "no preview supplied: pass a PIL image or stage a preview.png in the "
        f"source dir ({source_dir})"
    )


def _resized(img, size):
    """Return ``img`` resized to ``size`` (no-op when already that size)."""
    if img.size == tuple(size):
        return img
    return img.resize(tuple(size), Image.LANCZOS)