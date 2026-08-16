"""``bzmap editor save`` — session directory -> map file set.

Untouched inputs are copied from ``residue/source/`` byte for byte. Only
domains marked in ``dirty.json`` are re-encoded.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.editor.objects import apply_record_to_block
from bzmap.editor.session import (
    find_source_file,
    read_json,
    reconstruct_heightmap,
    session_paths,
    variant_bzn_suffix,
)
from bzmap.formats.bzn import read_bzn, write_bzn
from bzmap.formats.mat import MaterialGrid


def _objects_dirty(dirty):
    objects = dirty.get("objects") or {}
    if objects is True:
        return True
    if isinstance(objects, dict):
        return any(bool(v) for v in objects.values())
    return bool(objects)


def _copy_source(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def save_session(session_dir, out_dir, stem=None):
    """Write the session to ``out_dir``. Returns the response dict."""
    paths = session_paths(session_dir)
    if not paths["manifest"].is_file():
        raise EditorError(
            "no_session",
            f"no manifest.json in {session_dir}",
            hint="open or new a map first",
            path=session_dir,
        )
    manifest = read_json(paths["manifest"])
    dirty = read_json(paths["dirty"]) if paths["dirty"].is_file() else {}
    source_stem = manifest.get("stem")
    out_stem = stem or source_stem
    if not out_stem:
        raise EditorError("no_stem", "manifest has no stem and --stem was not given")

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    source_dir = paths["source"]
    if not source_dir.is_dir():
        raise EditorError("no_residue", f"session has no residue/source: {source_dir}", path=source_dir)

    # Index residue files by lowercased suffix-bearing name relative to stem.
    residue_files = [p for p in source_dir.iterdir() if p.is_file()]
    written = []
    identical = []
    regenerated = []
    warnings = []

    def out_name(src_path):
        """Rename a residue file onto ``out_stem`` keeping variant/suffix."""
        name = src_path.name
        lower = name.lower()
        src_l = source_stem.lower()
        if lower.startswith(src_l):
            return out_stem + name[len(source_stem):]
        return name

    # Pass 1: copy or skip every residue file. We'll overwrite dirty domains.
    dest_by_key = {}
    for src in residue_files:
        dest = out_dir / out_name(src)
        dest_by_key[src.name.lower()] = (src, dest)
        _copy_source(src, dest)
        written.append(dest.name)

    # Terrain
    if dirty.get("terrain"):
        header = read_json(paths["hg2_header"])
        heightmap = reconstruct_heightmap(paths, header)
        dest = out_dir / f"{out_stem}.hg2"
        heightmap.write(dest)
        if dest.name not in written:
            written.append(dest.name)
        regenerated.append(dest.name)
        warnings.append("terrain re-encoded from terrain.r16")
    else:
        dest = out_dir / f"{out_stem}.hg2"
        src = find_source_file(source_dir, source_stem, ".hg2")
        if src is not None and dest.is_file() and dest.read_bytes() == src.read_bytes():
            identical.append(dest.name)

    # Materials
    if dirty.get("materials"):
        mat_x = int(manifest["mat_grid_x"])
        mat_z = int(manifest["mat_grid_z"])
        raw = __import__("numpy").fromfile(paths["materials"], dtype="<u2")
        grid = MaterialGrid(raw.reshape(mat_z, mat_x))
        dest = out_dir / f"{out_stem}.mat"
        grid.write(dest)
        if dest.name not in written:
            written.append(dest.name)
        regenerated.append(dest.name)
    else:
        dest = out_dir / f"{out_stem}.mat"
        src = find_source_file(source_dir, source_stem, ".mat")
        if src is not None and dest.is_file() and dest.read_bytes() == src.read_bytes():
            identical.append(dest.name)

    # Objects
    if _objects_dirty(dirty):
        objects = read_json(paths["objects"])
        dirty_objects = dirty.get("objects") or {}
        for variant, records in objects.items():
            touched = set(dirty_objects.get(variant) or [])
            dest = out_dir / f"{out_stem}{variant_bzn_suffix(variant)}"
            src = find_source_file(source_dir, source_stem, variant_bzn_suffix(variant))
            if src is None:
                warnings.append(f"no residue BZN for variant {variant!r}; skipped")
                continue
            if not touched:
                _copy_source(src, dest)
                continue
            bzn = read_bzn(src)
            by_id = {rec["id"]: rec for rec in records}
            # Source objects were assigned obj-0001 in file order on open.
            prefix = "obj" if variant == "" else f"obj{variant.lower()}"
            for i, obj in enumerate(bzn.objects, start=1):
                obj_id = f"{prefix}-{i:04d}"
                if obj_id in touched and obj_id in by_id:
                    apply_record_to_block(obj, by_id[obj_id])
            # New objects (origin new) are not cloned here in Phase 1 —
            # placement lands in Phase 5. Warn if any new- ids are dirty.
            new_ids = [i for i in touched if i.startswith("new-")]
            if new_ids:
                warnings.append(
                    f"variant {variant!r}: {len(new_ids)} new object(s) not "
                    "written (clone-on-save lands with placement)"
                )
            write_bzn(dest, bzn)
            if dest.name not in written:
                written.append(dest.name)
            regenerated.append(dest.name)
    else:
        for variant in manifest.get("variants") or [""]:
            dest = out_dir / f"{out_stem}{variant_bzn_suffix(variant)}"
            src = find_source_file(source_dir, source_stem, variant_bzn_suffix(variant))
            if src is not None and dest.is_file() and dest.read_bytes() == src.read_bytes():
                identical.append(dest.name)

    # Everything else: already copied. Mark byte-identical vs residue.
    for src in residue_files:
        dest = out_dir / out_name(src)
        if not dest.is_file():
            continue
        if dest.name in regenerated:
            continue
        if dest.read_bytes() == src.read_bytes() and dest.name not in identical:
            identical.append(dest.name)

    # Derived-file note: we never invent a .lgt on an untouched save.
    return {
        "ok": True,
        "files": sorted(set(written)),
        "byte_identical": sorted(set(identical)),
        "regenerated": sorted(set(regenerated)),
        "warnings": warnings,
        "out": str(out_dir.resolve()),
        "stem": out_stem,
    }
