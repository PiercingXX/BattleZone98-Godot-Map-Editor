"""``bzmap editor save`` — session directory -> map file set.

Untouched inputs are copied from ``residue/source/`` byte for byte. Only
domains marked in ``dirty.json`` are re-encoded.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.editor.objects import apply_record_to_block, template_text_for
from bzmap.editor.session import (
    find_source_file,
    read_json,
    reconstruct_heightmap,
    session_paths,
    variant_bzn_suffix,
)
from bzmap.formats.bzn import GameObject, read_bzn, write_bzn
from bzmap.formats.mat import MaterialGrid


def _objects_dirty(dirty):
    objects = dirty.get("objects") or {}
    if objects is True:
        return True
    if isinstance(objects, dict):
        return any(bool(v) for v in objects.values())
    return bool(objects)


def _append_runtime_spawns(out_dir, stem, variant, records, warnings):
    """Append host-guarded BuildObject calls to ``<stem>MAP.lua``.

    Unverified classes must not become invented BZN blocks. The BZP map
    script hook is the documented runtime path.
    """
    if not records:
        return
    path = Path(out_dir) / f"{stem}MAP.lua"
    existing = ""
    if path.is_file():
        existing = path.read_text(encoding="utf-8", errors="replace")
    lines = [
        "",
        "-- bzmap editor: runtime spawns (unverified classes; host only)",
        f"-- variant {variant!r}",
        "if IsHosting and IsHosting() then",
    ]
    for rec in records:
        prjid = rec.get("prjid") or "unknown"
        x = float(rec.get("x", 0.0))
        y = float(rec.get("y", 0.0))
        z = float(rec.get("z", 0.0))
        team = int(rec.get("team") or 0)
        lines.append(
            f'  do local h = BuildObject("{prjid}", {team}, SetVector({x:.3f}, {y:.3f}, {z:.3f}))'
        )
        lines.append("    if h and RemovePilot then RemovePilot(h) end")
        lines.append("  end")
    lines.append("end")
    path.write_text(existing + "\r\n".join(lines) + "\r\n", encoding="utf-8")
    warnings.append(
        f"variant {variant!r}: {len(records)} unverified class(es) written "
        f"as runtime spawns in {path.name}"
    )


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
            new_ids = [i for i in touched if i.startswith("new-")]
            runtime = []
            next_seq = max((o.seqno or 0) for o in bzn.objects) + 1 if bzn.objects else 1
            next_addr = max((o.obj_addr or 0) for o in bzn.objects) + 1 if bzn.objects else 1
            for obj_id in new_ids:
                rec = by_id.get(obj_id)
                if rec is None:
                    continue
                if rec.get("placement_mode") == "runtime" or rec.get("template_verified") is False:
                    runtime.append(rec)
                    continue
                text = template_text_for(rec.get("prjid"), source_dir)
                if text is None:
                    runtime.append(rec)
                    warnings.append(
                        f"{rec.get('prjid')}: no verified same-class block; "
                        "emitting as runtime spawn"
                    )
                    continue
                clone = GameObject.from_template(text)
                apply_record_to_block(clone, rec)
                clone.set_identity(
                    seqno=next_seq,
                    addr=next_addr,
                    label=rec.get("label") or f"{rec.get('prjid')}{next_seq}",
                )
                next_seq += 1
                next_addr += 1
                bzn.add_object(clone)
            if runtime:
                _append_runtime_spawns(out_dir, out_stem, variant, runtime, warnings)
            try:
                bzn.set_header("size [1]", len(bzn.objects))
            except KeyError:
                pass
            try:
                bzn.set_header("seq_count [1]", next_seq)
            except KeyError:
                pass
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
