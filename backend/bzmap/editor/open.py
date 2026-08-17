"""``bzmap editor open`` — map file set -> session directory."""

from __future__ import annotations

from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.editor.objects import load_variant_objects
from bzmap.editor.session import (
    VARIANT_SUFFIXES,
    copy_into_residue,
    empty_dirty,
    ensure_session_dir,
    find_source_file,
    height_over_ceiling,
    resolve_map_input,
    variant_bzn_suffix,
    write_hg2_flags,
    read_json,
    write_json,
    write_manifest,
    write_materials_u16,
    write_terrain_r16,
)
from bzmap.formats.hg2 import HEIGHT_SCALE, read_hg2
from bzmap.formats.mat import TILE_M, MaterialGrid
from bzmap.formats.trn import read_trn


def is_binary_bzn(path):
    """True when a .bzn is a 1998-era binary save, not ASCII.

    Do not treat ``missionSave = true`` as binary — that flag is on every
    ASCII corpus file. Only ``binarySave`` itself, NULs, or a non-UTF-8
    decode count.
    """
    path = Path(path)
    raw = path.read_bytes()
    if not raw:
        return False
    if b"\x00" in raw[:256]:
        return True
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return True
    stripped = text.lstrip()
    if not stripped.lower().startswith("version"):
        return True
    # Value is on the line after ``binarySave [1] =``.
    lines = stripped.splitlines()
    for i, line in enumerate(lines[:20]):
        if line.strip().lower() == "binarysave [1] =" and i + 1 < len(lines):
            return lines[i + 1].strip().lower() == "true"
        if line.strip().lower().startswith("binarysave") and "true" in line.lower():
            return True
    return False


def _detect_pack_context(directory, files):
    """Heuristic pack_context from the source location and sidecar files."""
    directory = Path(directory)
    parts = [p.lower() for p in directory.parts]
    has_odf = any(p.suffix.lower() == ".odf" for p in files)
    if "3406347034" in parts or (has_odf and any(
        "packaged_mods" in parts or "workshop" in parts for _ in (0,)
    )):
        workshop_id = None
        for i, part in enumerate(directory.parts):
            if part.lower() in {"3406347034"} or (
                part.isdigit() and len(part) >= 7
                and i > 0
                and directory.parts[i - 1].lower() in {"packaged_mods", "301650"}
            ):
                workshop_id = part
                break
        return {"kind": "bzp", "workshop_id": workshop_id or "3406347034"}
    if has_odf:
        return {"kind": "bzp", "workshop_id": None}
    return {"kind": "base"}


def _world_from_trn(trn_path):
    if trn_path is None:
        return ""
    cfg = read_trn(trn_path)
    sky = (cfg.get("Sky", "SkyTexture") or "").strip().lower()
    # SkyTexture is often ``mars.map`` — use the stem as a world hint.
    if sky:
        stem = Path(sky).stem.lower()
        if stem:
            return stem
    palette = (cfg.get("Color", "Palette") or "").strip().lower()
    if palette:
        return Path(palette).stem.lower()
    return ""


def _parse_meta(files, stem):
    meta = {}
    by_suf = {p.suffix.lower(): p for p in files}
    # last write wins on suffix; fine for a first-pass meta dump
    for p in files:
        suf = p.suffix.lower()
        by_suf[suf] = p
    if ".ini" in by_suf:
        text = by_suf[".ini"].read_text(encoding="utf-8", errors="replace")
        meta["ini"] = {"raw": text}
    if ".des" in by_suf:
        meta["des"] = {"raw": by_suf[".des"].read_text(encoding="utf-8", errors="replace")}
    if ".odf" in by_suf:
        meta["odf"] = {"raw": by_suf[".odf"].read_text(encoding="utf-8", errors="replace")}
    if ".trn" in by_suf:
        cfg = read_trn(by_suf[".trn"])
        meta["trn"] = {
            "NormalView": dict(cfg.section("NormalView").items()) if cfg.section("NormalView") else {},
            "World": dict(cfg.section("World").items()) if cfg.section("World") else {},
            "Sky": dict(cfg.section("Sky").items()) if cfg.section("Sky") else {},
            "Clouds": dict(cfg.section("Clouds").items()) if cfg.section("Clouds") else {},
        }
    return meta


def open_map(path, session_dir):
    """Open a map file set into ``session_dir``. Returns the response dict."""
    directory, stem, files = resolve_map_input(path)
    warnings = []

    binary_bzns = [p for p in files if p.suffix.lower() == ".bzn" and is_binary_bzn(p)]
    if binary_bzns:
        raise EditorError(
            "binary_bzn_unsupported",
            f"{binary_bzns[0].name} is a binary BZN; a binary reader is not "
            "in bzmap yet",
            hint="re-save from the game with the asciisave launch argument, "
                 "or wait for the binary reader",
            path=binary_bzns[0],
        )

    paths = ensure_session_dir(session_dir)
    copy_into_residue(files, paths["source"])

    hg2_path = find_source_file(paths["source"], stem, ".hg2")
    if hg2_path is None:
        raise EditorError(
            "missing_hg2",
            f"no .hg2 for stem {stem!r} next to {path}",
            path=directory,
        )
    heightmap = read_hg2(hg2_path)
    write_terrain_r16(paths["terrain"], heightmap)
    write_hg2_flags(paths["hg2_flags"], heightmap)
    write_json(paths["hg2_header"], {
        "version": heightmap.version,
        "depth": heightmap.depth,
        "zonesX": heightmap.zonesX,
        "zonesZ": heightmap.zonesZ,
        "unknownA": heightmap.unknownA,
        "unknownB": heightmap.unknownB,
    })

    mat_path = find_source_file(paths["source"], stem, ".mat")
    if mat_path is not None:
        grid = MaterialGrid.read(mat_path)
        write_materials_u16(paths["materials"], grid)
        mat_grid_x, mat_grid_z = grid.grid_x, grid.grid_z
    else:
        warnings.append("no .mat in the basename group")
        mat_grid_x = heightmap.grid_x // 4
        mat_grid_z = heightmap.grid_z // 4
        empty = MaterialGrid.__new__(MaterialGrid)
        import numpy as np
        empty.data = np.zeros((mat_grid_z, mat_grid_x), dtype="uint16")
        write_materials_u16(paths["materials"], empty)

    objects = {v: [] for v in VARIANT_SUFFIXES}
    present_variants = []
    for variant in VARIANT_SUFFIXES:
        bzn_path = find_source_file(paths["source"], stem, variant_bzn_suffix(variant))
        if bzn_path is None:
            continue
        prefix = "obj" if variant == "" else f"obj{variant.lower()}"
        records, _blocks, _bzn = load_variant_objects(bzn_path, id_prefix=prefix)
        objects[variant] = records
        present_variants.append(variant)

    if not present_variants:
        warnings.append("no .bzn in the basename group")
        present_variants = [""]

    trn_path = find_source_file(paths["source"], stem, ".trn")
    world = _world_from_trn(trn_path)
    pack_context = _detect_pack_context(directory, files)

    over = height_over_ceiling(heightmap)
    if over:
        warnings.append(
            "source heightmap has cells above the editor authoring ceiling "
            "(raw 4095); inherited values are preserved"
        )

    features = {"water": [], "plants": []}
    sidecar = Path(directory) / "features.json"
    if sidecar.is_file():
        loaded = read_json(sidecar)
        if isinstance(loaded, dict):
            if "water" in loaded or "plants" in loaded:
                features = loaded
    meta = _parse_meta(files, stem)
    dirty = empty_dirty(present_variants)

    write_json(paths["objects"], objects)
    write_json(paths["features"], features)
    write_json(paths["meta"], meta)
    write_json(paths["dirty"], dirty)

    manifest = write_manifest(
        paths["manifest"],
        stem=stem,
        source_path=str(directory.resolve()),
        converted_from_binary=False,
        world=world,
        width_m=int(heightmap.width_m),
        depth_m=int(heightmap.depth_m),
        grid_x=int(heightmap.grid_x),
        grid_z=int(heightmap.grid_z),
        cell_m=5.0,
        height_scale=HEIGHT_SCALE,
        height_max_raw=4095,
        height_over_ceiling=over,
        mat_grid_x=int(mat_grid_x),
        mat_grid_z=int(mat_grid_z),
        mat_cell_m=TILE_M,
        variants=present_variants,
        has_lightmap=find_source_file(paths["source"], stem, ".lgt") is not None,
        pack_context=pack_context,
    )

    return {
        "ok": True,
        "session": str(paths["root"].resolve()),
        "manifest": manifest,
        "warnings": warnings,
    }
