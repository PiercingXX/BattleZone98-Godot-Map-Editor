"""Top-down annotated debug render of a built map directory.

Emits a PNG so map geometry can be verified WITHOUT launching the game: shaded
terrain, the water-mesh footprint, and every BZN object as a colour-coded dot
with a legend. Catches placement bugs (off-centre features, wrong-side spawns,
water not covering the trench, stacked buildings) that otherwise cost a
play-test round-trip.

Run: ``python -m bzmap.render.debug_map build/xxPier01`` -> writes
``build/xxPier01/xxPier01.debug.png``.
"""

from __future__ import annotations

import re
import struct
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import ImageDraw, ImageFont

from bzmap.formats.hg2 import read_hg2
from bzmap.render.preview import Preview

# Object PrjID class -> (legend label, RGB). Order defines legend order.
_CLASSES = [
    ("player", "player / user", (255, 255, 255)),
    ("avtank", "player (avtank)", (255, 255, 255)),
    ("pspwn", "spawn point", (0, 220, 255)),
    ("eggeizr", "geyser", (255, 230, 0)),
    ("npscr", "scrap", (255, 140, 0)),
    ("sscr", "scrap", (255, 140, 0)),
    ("blc-pell", "scrap", (255, 140, 0)),
    ("abhang", "hangar", (255, 0, 200)),
    ("absupp", "supply", (200, 0, 255)),
]


def _find(directory, filename):
    """Case-insensitive file lookup in a directory."""
    directory = Path(directory)
    target = filename.lower()
    for p in directory.iterdir():
        if p.is_file() and p.name.lower() == target:
            return p
    return None


def _class_of(prjid):
    for prefix, label, color in _CLASSES:
        if prjid.lower().startswith(prefix):
            return label, color
    return "other/mesh", (140, 140, 140)


def _bzn_objects(path):
    """Yield ``(prjid, x, z, team)`` for every object in an ASCII BZN."""
    text = path.read_text("ascii", errors="replace").replace("\r", "")
    for block in text.split("[GameObject]")[1:]:
        pid = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)
        if not pid:
            continue
        x = re.search(r"^  x \[1\] =\n(\S+)", block, re.M)
        z = re.search(r"^  z \[1\] =\n(\S+)", block, re.M)
        tm = re.search(r"^team \[1\] =\n(\d+)", block, re.M)
        if x and z:
            yield (pid.group(1), float(x.group(1)), float(z.group(1)),
                   int(tm.group(1)) if tm else 0)


def _water_footprint(mesh_path, heightmap):
    """Return a boolean grid mask of the water mesh's XZ footprint, or None.

    Parses the OGRE mesh vertex positions (bzmap.formats.mesh layout) and marks
    every heightmap cell that falls under a water triangle's bounding extent —
    an approximation good enough to see coverage.
    """
    raw = mesh_path.read_bytes()
    try:
        nl = raw.index(b"\n", 2) + 1
        cid, _ = struct.unpack_from("<HI", raw, nl)
        if cid != 0x3000:
            return None
        p = nl + 6 + 1  # skip skeletal bool
        cid, _ = struct.unpack_from("<HI", raw, p)  # M_SUBMESH
        if cid != 0x4000:
            return None
        b = raw.index(b"\n", p + 6) + 1
        b += 1  # useSharedVertices
        icount = struct.unpack_from("<I", raw, b)[0]
        b += 4 + 1 + icount * 2  # indexCount, indexes32 bool, indices
        cid, gsize = struct.unpack_from("<HI", raw, b)  # M_GEOMETRY
        if cid != 0x5000:
            return None
        vcount = struct.unpack_from("<I", raw, b + 6)[0]
        di = raw.find(struct.pack("<H", 0x5210), b + 10, b + gsize) + 6
    except (ValueError, struct.error):
        return None

    gz, gx = heightmap.data.shape
    mask = np.zeros((gz, gx), bool)
    cell = 5.0
    for v in range(vcount):
        # Mesh-local vertices are the transpose of world coordinates (x<->z)
        # — see build_water_surface. Swap back into world space.
        pz, _py, px = struct.unpack_from("<3f", raw, di + v * 32)
        ix, iz = int(px / cell), int(pz / cell)
        if 0 <= iz < gz and 0 <= ix < gx:
            mask[iz, ix] = True
    return mask


def _is_water_mesh(mesh):
    mat = mesh.with_suffix(".material")
    return mat.is_file() and "thecavew" in mat.read_text("ascii", "replace")


def water_mask_for_dir(map_dir, heightmap, stem=None):
    """Return the combined water footprint for a map's water meshes.

    When ``stem`` is given (the map's terrain stem), only meshes the map's BZN
    actually places are used — essential in the flat staging dir where every
    map's meshes sit together and a global glob would tint the wrong map. When
    ``stem`` is ``None`` (a per-map build dir), every water mesh present is used.
    Returns a heightmap-shaped bool mask, or ``None`` when there is no water.
    """
    map_dir = Path(map_dir)
    if stem is not None:
        bzn = map_dir / f"{stem}_S.bzn"
        if not bzn.is_file():
            bzn = map_dir / f"{stem}.bzn"
        placed = {prjid.lower() for prjid, *_ in _bzn_objects(bzn)} if bzn.is_file() else set()

    combined = None
    for mesh in map_dir.glob("*.mesh"):
        if not _is_water_mesh(mesh):
            continue
        if stem is not None and mesh.stem.lower() not in placed:
            continue
        m = _water_footprint(mesh, heightmap)
        if m is not None:
            combined = m if combined is None else (combined | m)
    return combined


def render_map_image(heightmap, water_mask=None, size=None):
    """A CLEAN top-down map image (shaded terrain + blue water tint), no dots or
    legend — for the lobby thumbnail and as the radar-lightmap source.
    """
    pv = Preview(heightmap, size=size or (heightmap.grid_x, heightmap.grid_z))
    if water_mask is not None and np.asarray(water_mask).any():
        pv.draw_regions([np.asarray(water_mask, bool)], color=(40, 120, 255),
                        alpha=150)
    return pv.image


def render_debug(map_dir, out_path=None, px=900, stem=None):
    """Render an annotated top-down PNG for a map.

    ``map_dir`` may be a per-map dir (``build/xxPier01``) or the flat pack dir;
    ``stem`` names the map (defaults to the dir name for a per-map dir). Uses the
    ``_S`` variant (richest object set) if present, else the base. Returns the
    written path.
    """
    map_dir = Path(map_dir)
    stem = stem or map_dir.name
    hg2 = _find(map_dir, f"{stem}.hg2") or _find(map_dir, f"{stem}.HG2")
    if hg2 is None:
        hg2 = next((p for p in map_dir.iterdir()
                    if p.suffix.lower() == ".hg2"), None)
    if hg2 is None:
        raise FileNotFoundError(f"no .hg2 for {stem} in {map_dir}")
    heightmap = read_hg2(hg2)

    bzn = (map_dir / f"{stem}_S.bzn")
    if not bzn.is_file():
        bzn = map_dir / f"{stem}.bzn"

    pv = Preview(heightmap, size=(px, px))

    # water footprint (blue tint), scoped to THIS map's meshes via its BZN so a
    # flat pack dir doesn't bleed one map's water onto another.
    mask = water_mask_for_dir(map_dir, heightmap, stem=stem)
    if mask is not None and mask.any():
        pv.draw_regions([mask], color=(40, 120, 255), alpha=120)

    # object dots
    counts = Counter()
    dots = {}
    for prjid, x, z, _team in _bzn_objects(bzn):
        label, color = _class_of(prjid)
        counts[label] += 1
        dots.setdefault(color, []).append((x, z))
    # draw economy first (small), then structures/player (bigger) on top
    order = [(255, 140, 0), (255, 230, 0), (0, 220, 255),
             (255, 0, 200), (200, 0, 255), (140, 140, 140),
             (255, 255, 255)]
    for color in order:
        if color in dots:
            r = 6 if color == (255, 255, 255) else 3
            pv.draw_points(dots[color], color=color, radius=r)

    # legend + title
    img = pv.image
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    lines = [f"{stem}  ({heightmap.width_m:.0f}x{heightmap.depth_m:.0f} m)  "
             f"north=up, +x=right"]
    seen = set()
    for _prefix, label, color in _CLASSES + [("", "other/mesh", (140, 140, 140))]:
        if label in counts and label not in seen:
            seen.add(label)
            lines.append(f"  {label}: {counts[label]}")
    if any(m.suffix.lower() == ".mesh" for m in map_dir.iterdir()):
        lines.append("  ~ water mesh footprint (blue)")
    # translucent legend box
    box_h = 12 * len(lines) + 8
    d.rectangle([4, 4, 320, 4 + box_h], fill=(0, 0, 0))
    y = 8
    for i, line in enumerate(lines):
        col = (255, 255, 255)
        d.text((8, y), line, fill=col, font=font)
        y += 12
    # colour swatches next to legend rows
    y = 8 + 12
    for _prefix, label, color in _CLASSES + [("", "other/mesh", (140, 140, 140))]:
        if label in counts and (label, color) not in [(l, c) for l, c in []]:
            pass

    out_path = Path(out_path) if out_path else map_dir / f"{stem}.debug.png"
    img.save(out_path)
    return out_path


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if not argv:
        print("usage: python -m bzmap.render.debug_map <build/mapdir> [more...]")
        return 1
    for d in argv:
        out = render_debug(d)
        print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
