"""``bzmap editor new`` — create a fresh map session."""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from bzmap.editor.discover import discover, first_game_root
from bzmap.editor.errors import EditorError
from bzmap.editor.open import open_map
from bzmap.editor.session import ensure_session_dir
from bzmap.editor.worlds import STOCK_WORLDS, worlds_from_game
from bzmap.formats.bzn import BznFile, GameObject
from bzmap.formats.des import write_des
from bzmap.formats.hg2 import GRID_M, HEIGHT_SCALE, ZONE_M, ZONE_SIZE, HeightMap, sample_m
from bzmap.formats.ini import write_ini
from bzmap.formats.mat import auto_paint
from bzmap.formats.odf import write_odf
from bzmap.formats.templates import TemplateLoader
from bzmap.formats.trn import write_complete_trn
from bzmap.formats.vxt import write_standard_vxt

KNOWN_TERRAIN_COLLISIONS = {
    # Stock / BZP names that must never be reused (engine-global).
}

_DEFAULT_PAINT_RULES = [
    {"mat_id": 0, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.0, "max_s": 0.05},
    {"mat_id": 1, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.05, "max_s": 0.25},
    {"mat_id": 2, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.25, "max_s": 10.0},
]


def _known_terrain_names(game_root):
    names = set()
    trn_dir = Path(game_root) / "Edit" / "trn"
    if trn_dir.is_dir():
        for p in trn_dir.iterdir():
            if p.is_file() and p.suffix.lower() == ".trn":
                names.add(p.stem.lower())
    # Workshop / packaged layers: any loose .trn
    discovery = discover()
    for item in discovery["installs"]:
        if item.get("kind") != "workshop_item":
            continue
        root = Path(item["path"])
        try:
            for p in root.iterdir():
                if p.is_file() and p.suffix.lower() == ".trn":
                    names.add(p.stem.lower())
        except OSError:
            continue
    return names


def _find_template_bzn(game_root):
    """Return a stock .bzn that can clone player + pspwn_1, or None."""
    discovery = discover()
    candidates = []
    for item in discovery["installs"]:
        if item.get("kind") != "workshop_item":
            continue
        root = Path(item["path"])
        try:
            for p in root.iterdir():
                if p.is_file() and p.suffix.lower() == ".bzn":
                    candidates.append(p)
        except OSError:
            continue
    # Prefer a small well-known map.
    preferred = [p for p in candidates if p.stem.lower() == "umoonwar"]
    search = preferred + candidates
    for path in search:
        try:
            loader = TemplateLoader(bzn_path=path)
            available = loader.available_prjids()
        except OSError:
            continue
        if "player" in available and "pspwn_1" in available:
            return path
    return None


def _flat_heightmap(width_m, depth_m, base_height):
    if width_m % 1280 or depth_m % 1280:
        raise EditorError(
            "bad_dimensions",
            f"width and depth must be multiples of 1280 (got {width_m}x{depth_m})",
            hint="legal sizes are 1280, 2560, 3840, 5120; non-square is allowed",
        )
    zones_x = int(width_m // 1280)
    zones_z = int(depth_m // 1280)
    data = np.full(
        (zones_z * ZONE_SIZE, zones_x * ZONE_SIZE),
        int(base_height),
        dtype=np.uint16,
    )
    return HeightMap(zones_x, zones_z, data)


def _bake_lgt(heightmap, path):
    """North-light slope bake. Never zero-fill (black in-game radar)."""
    planes = heightmap.zonesX * heightmap.zonesZ + 1
    out = np.full((planes, ZONE_SIZE, ZONE_SIZE), 56, dtype=np.uint8)
    raw = heightmap.data.astype(np.float64)
    # dh/dz: north is +z = increasing row.
    dz = np.zeros_like(raw)
    dz[1:-1, :] = (raw[2:, :] - raw[:-2, :]) / 2.0
    # Lambert from the north at 45°.
    shade = 56 + np.clip((-dz) * 2.0 + 80.0, 0, 199)
    shade = shade.astype(np.uint8)
    plane = 1
    for zz in range(heightmap.zonesZ):
        for zx in range(heightmap.zonesX):
            block = shade[
                zz * ZONE_SIZE:(zz + 1) * ZONE_SIZE,
                zx * ZONE_SIZE:(zx + 1) * ZONE_SIZE,
            ]
            out[plane] = block
            plane += 1
    Path(path).write_bytes(out.tobytes())


def _append_mission_trailer(bzn):
    """Ensure the mission record sits at the end of the last object block."""
    if not bzn.objects:
        return
    last = bzn.objects[-1]
    text = "\r\n".join(last.lines)
    if "sObject =" in text:
        return
    sobject = len(bzn.objects) + 1
    last.lines.append("name = MultSTMission")
    last.lines.append(f"sObject = {sobject:08X}")


def _build_starter_bzns(loader, stem, heightmap, variants):
    """Clone player + spawn-ring scaffolds into one BznFile per variant."""
    width_m = heightmap.width_m
    depth_m = heightmap.depth_m
    cx, cz = width_m / 2.0, depth_m / 2.0
    cy = sample_m(heightmap, cx, cz)
    radius = min(width_m, depth_m) * 0.30

    def spawn_at(i, n):
        ang = (2.0 * math.pi * i) / n
        x = cx + radius * math.cos(ang)
        z = cz + radius * math.sin(ang)
        y = sample_m(heightmap, x, z)
        return x, y, z, ang

    files = {}
    for variant in variants:
        n_spawns = 2 if variant == "_S" else 14
        blocks = []
        # Player first, required, centre.
        player = GameObject.from_template(loader.object("player"))
        player.set_position(cx, cy, cz)
        player.set_yaw(0.0)
        player.set_identity(seqno=0, addr=1, label=f"{stem}0_player")
        try:
            player.set_team(1)
            player.set_is_user(True)
        except KeyError:
            pass
        blocks.append(player)
        for i in range(n_spawns):
            x, y, z, ang = spawn_at(i, n_spawns)
            spawn = GameObject.from_template(loader.object("pspwn_1"))
            spawn.set_position(x, y, z)
            spawn.set_yaw(ang)
            spawn.set_identity(seqno=i + 1, addr=i + 2, label=f"{stem}{i + 1}_spawn")
            try:
                spawn.set_team(0)
                spawn.set_is_user(False)
            except KeyError:
                pass
            blocks.append(spawn)
        header = loader.header()
        tail = loader.tail()
        bzn = BznFile.build(header, blocks, tail)
        bzn.set_header("size [1]", len(blocks))
        bzn.set_header("seq_count [1]", len(blocks))
        # Vestigial names: set to this stem so they aren't the template's.
        try:
            bzn.set_header("msn_filename", f"{stem}.bzn")
        except KeyError:
            pass
        try:
            bzn.set_header("TerrainName", stem)
        except KeyError:
            pass
        _append_mission_trailer(bzn)
        files[variant] = bzn
    return files


def create_map(stem, world, width_m, depth_m, session_dir, game_root,
               base_height=1000, pack_kind="bzp"):
    """Create a new map session. Returns the open-map response dict."""
    stem = str(stem)
    if len(stem) > 8:
        raise EditorError(
            "stem_too_long",
            f"terrain stem {stem!r} is {len(stem)} characters; "
            "the engine truncates script lookups above 8",
            hint="use a stem of 8 characters or fewer",
        )
    if not stem or not stem.replace("_", "").isalnum():
        raise EditorError("bad_stem", f"stem {stem!r} is empty or not alphanumeric")

    game_root = Path(game_root) if game_root else first_game_root()
    if game_root is None:
        raise EditorError(
            "no_game",
            "no game install found; pass --game-root",
            hint="probe first, or install Battlezone 98 Redux",
        )
    game_root = Path(game_root)

    taken = _known_terrain_names(game_root)
    if stem.lower() in taken:
        raise EditorError(
            "stem_collision",
            f"terrain name {stem!r} collides with an installed map",
            hint="terrain names are global across loaded mods",
        )

    world = str(world).lower()
    try:
        available = {w["id"] for w in worlds_from_game(game_root)}
    except EditorError:
        available = set(STOCK_WORLDS)
    if world not in available and world not in STOCK_WORLDS:
        raise EditorError(
            "unknown_world",
            f"unknown world {world!r}",
            hint=f"stock worlds: {', '.join(STOCK_WORLDS)}",
        )

    width_m = int(width_m)
    depth_m = int(depth_m)
    base_height = int(base_height)
    if base_height < 1 or base_height > 4095:
        raise EditorError(
            "bad_base_height",
            f"base_height {base_height} is outside the authoring range 1..4095",
        )

    template_trn = game_root / "Edit" / "trn" / f"{world}.trn"
    if not template_trn.is_file():
        # Case-insensitive fallback.
        trn_dir = game_root / "Edit" / "trn"
        template_trn = None
        if trn_dir.is_dir():
            for p in trn_dir.iterdir():
                if p.is_file() and p.stem.lower() == world and p.suffix.lower() == ".trn":
                    template_trn = p
                    break
        if template_trn is None:
            raise EditorError(
                "no_world_template",
                f"no Edit/trn/{world}.trn in {game_root}",
                path=game_root / "Edit" / "trn",
            )

    paths = ensure_session_dir(session_dir)
    staging = paths["source"]

    heightmap = _flat_heightmap(width_m, depth_m, base_height)
    heightmap.write(staging / f"{stem}.hg2")
    auto_paint(heightmap, _DEFAULT_PAINT_RULES).write(staging / f"{stem}.mat")
    write_complete_trn(staging / f"{stem}.trn", width_m, depth_m, template_path=template_trn)
    write_ini(staging / f"{stem}.ini", mission_name=stem, map_type="multiplayer")
    write_des(
        staging / f"{stem}.des",
        mission_name=stem,
        world=world.capitalize(),
        size=f"{width_m}x{depth_m}",
        geysers=0,
        scrap=0,
        players=14,
    )
    if pack_kind == "bzp":
        write_odf(staging / f"{stem}.odf")
    write_standard_vxt(staging / f"{stem}.vxt")
    _bake_lgt(heightmap, staging / f"{stem}.lgt")

    warnings = []
    template_bzn = _find_template_bzn(game_root)
    variants = ["", "_S", "_ST", "_SW"]
    if template_bzn is not None:
        loader = TemplateLoader(bzn_path=template_bzn)
        bzns = _build_starter_bzns(loader, stem, heightmap, variants)
        for variant, bzn in bzns.items():
            name = f"{stem}{variant}.bzn" if variant else f"{stem}.bzn"
            bzn.write(staging / name)
    else:
        warnings.append(
            "no stock BZN with player + pspwn_1 templates was found; "
            "session has terrain but no objects"
        )

    # Re-enter through open() so residue/session buffers share one code path.
    result = open_map(staging / f"{stem}.trn", session_dir)
    if warnings:
        result.setdefault("warnings", []).extend(warnings)
    # open() set source_path to the session residue; rewrite to mark this as new.
    manifest = result.get("manifest") or {}
    manifest["source_path"] = ""
    manifest["world"] = world
    manifest["pack_context"] = (
        {"kind": "bzp"} if pack_kind == "bzp" else {"kind": "base"}
    )
    from bzmap.editor.session import write_json
    write_json(paths["manifest"], manifest)
    result["manifest"] = manifest
    return result
