"""Session directory layout and buffer helpers (map-editor docs/02 §1).

The editor sees row-major, height-only ``terrain.r16`` and row-major
``materials.u16``. Zone interleave, HG2 flag bits, and verbatim source files
live under ``residue/`` and are never the editor's problem.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np

from bzmap.editor import CONTRACT_VERSION
from bzmap.editor.errors import EditorError
from bzmap.formats.hg2 import ZONE_SIZE, HeightMap
from bzmap.formats.mat import MaterialGrid

HEIGHT_MASK = 0x1FFF
FLAG_SHIFT = 13
VARIANT_SUFFIXES = ("", "_S", "_ST", "_SW")

# Files that belong to a basename group, besides variant BZNs.
_MAP_SUFFIXES = (
    ".trn", ".hg2", ".mat", ".lgt", ".ini", ".des", ".odf", ".vxt",
    ".lua", ".png", ".bmp",
)


def session_paths(session_dir):
    """Return the standard file paths inside a session directory."""
    root = Path(session_dir)
    residue = root / "residue"
    return {
        "root": root,
        "manifest": root / "manifest.json",
        "terrain": root / "terrain.r16",
        "materials": root / "materials.u16",
        "objects": root / "objects.json",
        "features": root / "features.json",
        "meta": root / "meta.json",
        "dirty": root / "dirty.json",
        "report": root / "report.json",
        "masks": root / "masks",
        "residue": residue,
        "source": residue / "source",
        "hg2_header": residue / "hg2_header.json",
        "hg2_flags": residue / "hg2_flags.u8",
    }


def ensure_session_dir(session_dir):
    """Create the session skeleton. Raises if the path cannot be used."""
    paths = session_paths(session_dir)
    paths["root"].mkdir(parents=True, exist_ok=True)
    paths["masks"].mkdir(parents=True, exist_ok=True)
    paths["residue"].mkdir(parents=True, exist_ok=True)
    paths["source"].mkdir(parents=True, exist_ok=True)
    return paths


def write_json(path, payload):
    Path(path).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def empty_dirty(variants=None):
    variants = list(variants) if variants is not None else [""]
    return {
        "terrain": False,
        "materials": False,
        "objects": {v: [] for v in variants},
        "features": False,
        "meta": [],
    }


def write_terrain_r16(path, heightmap):
    """Write height-only row-major uint16 (flag bits stripped)."""
    heights = np.asarray(heightmap.data, dtype=np.uint16) & HEIGHT_MASK
    Path(path).write_bytes(np.ascontiguousarray(heights, dtype="<u2").tobytes())


def write_hg2_flags(path, heightmap):
    """Write per-cell flag bits (0..7) as row-major uint8."""
    flags = (np.asarray(heightmap.data, dtype=np.uint16) >> FLAG_SHIFT).astype(np.uint8)
    Path(path).write_bytes(np.ascontiguousarray(flags).tobytes())


def write_materials_u16(path, grid):
    data = np.ascontiguousarray(grid.data, dtype="<u2")
    Path(path).write_bytes(data.tobytes())


def read_terrain_r16(path, grid_z, grid_x):
    raw = np.fromfile(path, dtype="<u2")
    expected = grid_z * grid_x
    if raw.size != expected:
        raise EditorError(
            "terrain_size_mismatch",
            f"terrain.r16 has {raw.size} samples, expected {expected} "
            f"({grid_z}x{grid_x})",
            path=path,
        )
    return raw.reshape(grid_z, grid_x)


def read_hg2_flags(path, grid_z, grid_x):
    raw = np.fromfile(path, dtype=np.uint8)
    expected = grid_z * grid_x
    if raw.size != expected:
        raise EditorError(
            "flags_size_mismatch",
            f"hg2_flags.u8 has {raw.size} samples, expected {expected}",
            path=path,
        )
    return raw.reshape(grid_z, grid_x)


def read_materials_u16(path, grid_z, grid_x):
    raw = np.fromfile(path, dtype="<u2")
    expected = grid_z * grid_x
    if raw.size != expected:
        raise EditorError(
            "materials_size_mismatch",
            f"materials.u16 has {raw.size} samples, expected {expected}",
            path=path,
        )
    return MaterialGrid(raw.reshape(grid_z, grid_x))


def reconstruct_heightmap(paths, header):
    """Build a :class:`HeightMap` from session terrain + residue flags/header."""
    grid_x = int(header["zonesX"]) * ZONE_SIZE
    grid_z = int(header["zonesZ"]) * ZONE_SIZE
    heights = read_terrain_r16(paths["terrain"], grid_z, grid_x)
    if paths["hg2_flags"].is_file():
        flags = read_hg2_flags(paths["hg2_flags"], grid_z, grid_x)
    else:
        flags = np.zeros((grid_z, grid_x), dtype=np.uint8)
    words = (flags.astype(np.uint16) << FLAG_SHIFT) | (heights & HEIGHT_MASK)
    return HeightMap(
        header["zonesX"],
        header["zonesZ"],
        words,
        version=int(header.get("version", 1)),
        depth=int(header.get("depth", 8)),
        unknownA=int(header.get("unknownA", 10)),
        unknownB=int(header.get("unknownB", 0)),
    )


def copy_into_residue(source_files, source_dir):
    """Copy every source file into ``residue/source/`` under its own name."""
    source_dir = Path(source_dir)
    source_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    for src in source_files:
        src = Path(src)
        dest = source_dir / src.name
        try:
            if dest.resolve() == src.resolve():
                copied.append(dest)
                continue
        except OSError:
            pass
        shutil.copy2(src, dest)
        copied.append(dest)
    return copied


def find_source_file(source_dir, stem, suffix):
    """Case-insensitive ``<stem><suffix>`` inside residue/source."""
    target = (stem + suffix).lower()
    for p in Path(source_dir).iterdir():
        if p.is_file() and p.name.lower() == target:
            return p
    return None


def variant_bzn_suffix(variant):
    return f"{variant}.bzn" if variant else ".bzn"


def collect_map_files(root, stem):
    """Return every file in ``root`` that belongs to the ``stem`` basename group.

    Matching is case-insensitive. Variant BZNs (``_S`` / ``_ST`` / ``_SW``)
    and ``<stem>MAP.lua`` are included.
    """
    root = Path(root)
    stem_l = stem.lower()
    found = []
    for p in root.iterdir():
        if not p.is_file():
            continue
        name = p.name
        lower = name.lower()
        name_stem = Path(name).stem
        # Strip one trailing variant suffix for comparison.
        base = name_stem
        for suffix in ("_SW", "_ST", "_MS", "_S"):
            if base.upper().endswith(suffix):
                base = base[: -len(suffix)]
                break
        if base.lower() == stem_l:
            found.append(p)
            continue
        if lower == f"{stem_l}map.lua":
            found.append(p)
            continue
        if lower.startswith(stem_l + ".") or lower.startswith(stem_l + "_"):
            found.append(p)
    return sorted(found, key=lambda p: p.name.lower())


def resolve_map_input(path):
    """Accept a file or directory and return ``(directory, stem, files)``.

    ``stem`` is the terrain basename without a variant suffix.
    """
    path = Path(path).expanduser()
    if not path.exists():
        raise EditorError("not_found", f"no such file or directory: {path}", path=path)

    if path.is_dir():
        directory = path
        # Prefer a .trn, then .hg2, then any .bzn.
        candidates = []
        for p in path.iterdir():
            if not p.is_file():
                continue
            suf = p.suffix.lower()
            if suf in {".trn", ".hg2", ".bzn", ".mat"}:
                candidates.append(p)
        if not candidates:
            raise EditorError(
                "no_map_files",
                f"no map files in {path}",
                hint="point at a .trn / .bzn / .hg2 or the directory that holds them",
                path=path,
            )
        # Pick the shortest stem (so uexmap10.bzn wins over uexmap10_S.bzn).
        chosen = min(candidates, key=lambda p: len(p.stem))
        stem = _strip_variant(chosen.stem)
    else:
        directory = path.parent
        stem = _strip_variant(path.stem)

    files = collect_map_files(directory, stem)
    if not files:
        raise EditorError("no_map_files", f"no files for stem {stem!r} in {directory}", path=directory)
    return directory, stem, files


def _strip_variant(stem):
    upper = stem.upper()
    for suffix in ("_SW", "_ST", "_MS", "_S"):
        if upper.endswith(suffix):
            return stem[: -len(suffix)]
    return stem


def write_manifest(path, **fields):
    payload = {"contract_version": CONTRACT_VERSION}
    payload.update(fields)
    write_json(path, payload)
    return payload


def height_over_ceiling(heightmap):
    """True when any cell's 13-bit height exceeds the editor authoring ceiling."""
    heights = np.asarray(heightmap.data, dtype=np.uint16) & HEIGHT_MASK
    return bool(np.any(heights > 4095))
