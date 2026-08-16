"""``.MAT`` material grid reader/writer and auto-painter (docs/01 §2).

The file is a little-endian array of ``uint16`` values, one per 20 m terrain
tile. **The data is zone-major, exactly like the HG2**: a sequence of 64x64
zone blocks in row-major *zone* order; within each zone the tiles are
row-major. (An earlier revision claimed "no zone-major trap" — that was wrong,
and shipping a flat row-major grid scrambled the terrain textures of the first
multi-zone map to reach the game, 2026-08-12. Verified against all 13
multi-zone corpus MATs: the zone-major decode is seam-coherent at every 64-tile
boundary, the flat decode is not.) Because one MAT tile spans 4x4 heightmap
cells, the grid is ``(zonesZ * 64) x (zonesX * 64)`` for 256-cell (1280 m)
zones; single-zone (64x64) files are identical under both layouts.

Each 16-bit entry encodes a material transition for its tile:

=====================  ======================================================
bits                    meaning
=====================  ======================================================
15-12                   material A index (base / dominant)  [TextureTypeN]
11-8                    material B index (blend / transition target)
7                       cap flag (diagonal transition)
6                       flip flag
5-4                     rotation (0-3)
3-2                     unused (always 0)
1-0                     tile variant
=====================  ======================================================

This matches the vendored WorldBuilder ``encode_entry`` and the ``A0..A3``
rotation suffixes on the ``.trn`` ``Solid*``/``Diagonal*``/``Cap*`` layer names.

The bit layout is **inferred** (docs/09 E3), not byte-verified against a stock
map, so :class:`MaterialGrid` round-trips whatever 16-bit values it is given
verbatim — decoding is only used for auto-painting, which is the recommended
way to author a ``.MAT`` (docs/01 §2: "Prefer generating it").
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .hg2 import HEIGHT_SCALE, slope

# One MAT tile spans this many heightmap cells along each axis (20 m / 5 m).
TILE_CELLS = 4

# One zone is this many MAT tiles across (1280 m / 20 m).
ZONE_TILES = 64

# One MAT tile is this many metres across.
TILE_M = 20.0

# Material indices are 4-bit (0-15); the low nibble of each is reserved.
MATERIAL_MASK = 0xF


def _closest_factor_pair(n):
    """Return ``(rows, cols)`` factor pair of ``n`` with the least difference.

    Used to infer the 2-D grid shape of a ``.MAT`` file from its flat sample
    count. ``rows <= cols``. For a perfect square this returns ``(sqrt, sqrt)``.
    """
    root = int(n ** 0.5)
    for rows in range(root, 0, -1):
        if n % rows == 0:
            return rows, n // rows
    raise ValueError(f"{n} has no factor pair (should not happen)")


class MaterialGrid:
    """In-memory representation of an ``.MAT`` material grid.

    ``data`` is a 2-D ``numpy.uint16`` array in row-major order with shape
    ``(grid_z, grid_x)`` where ``grid_x = zonesX * 64`` and
    ``grid_z = zonesZ * 64`` (one tile per 4x4 heightmap cells).
    """

    __slots__ = ("data",)

    def __init__(self, data):
        self.data = np.asarray(data, dtype=np.uint16)

    # -- geometry ----------------------------------------------------------

    @property
    def grid_x(self):
        """Number of material tiles along the X axis."""
        return self.data.shape[1]

    @property
    def grid_z(self):
        """Number of material tiles along the Z axis."""
        return self.data.shape[0]

    @property
    def width_m(self):
        """Map width in metres."""
        return self.grid_x * TILE_M

    @property
    def depth_m(self):
        """Map depth in metres."""
        return self.grid_z * TILE_M

    # -- serialization -----------------------------------------------------

    @classmethod
    def read(cls, path):
        """Read an ``.MAT`` file from ``path`` into a :class:`MaterialGrid`.

        The grid shape is inferred from the flat sample count by factoring it
        into the closest pair of dimensions (rows x cols). The grid is always
        ``(zonesZ * 64) x (zonesX * 64)``; for the common square maps this is
        exact, and for the non-square 4x3 case the closest factor pair matches
        the map orientation. The on-disk zone-major layout is undone here, so
        ``data`` is world row-major (single-zone files are unaffected).
        """
        path = Path(path)
        raw = np.fromfile(path, dtype=np.uint16)
        if raw.size == 0:
            raise ValueError(f"{path}: empty MAT file")
        rows, cols = _closest_factor_pair(raw.size)
        zz_count, zx_count = rows // ZONE_TILES, cols // ZONE_TILES
        if rows % ZONE_TILES or cols % ZONE_TILES:
            # Not a whole number of zones — treat as a flat grid.
            return cls(raw.reshape(rows, cols))
        zones = raw.reshape(zz_count, zx_count, ZONE_TILES, ZONE_TILES)
        data = np.empty((rows, cols), dtype=np.uint16)
        for zzi in range(zz_count):
            for zxi in range(zx_count):
                data[zzi * ZONE_TILES:(zzi + 1) * ZONE_TILES,
                     zxi * ZONE_TILES:(zxi + 1) * ZONE_TILES] = zones[zzi, zxi]
        return cls(data)

    def write(self, path):
        """Write this material grid to ``path`` in the zone-major disk layout."""
        path = Path(path)
        rows, cols = self.data.shape
        if rows % ZONE_TILES or cols % ZONE_TILES:
            self.data.tofile(path)
            return
        blocks = []
        for zzi in range(rows // ZONE_TILES):
            for zxi in range(cols // ZONE_TILES):
                blocks.append(np.ascontiguousarray(
                    self.data[zzi * ZONE_TILES:(zzi + 1) * ZONE_TILES,
                              zxi * ZONE_TILES:(zxi + 1) * ZONE_TILES]))
        with open(path, "wb") as fh:
            for b in blocks:
                fh.write(b.tobytes())

    # -- decoding ----------------------------------------------------------

    def decode(self):
        """Decode each tile into ``(mat_a, mat_b, cap, flip, rot, variant)``.

        Returns a 2-D ``numpy`` array of shape ``(grid_z, grid_x, 6)`` with
        dtype ``int``. ``mat_a`` is the base material index, ``mat_b`` the
        transition target (equal to ``mat_a`` for a solid tile).
        """
        d = self.data.astype(np.int64)
        mat_a = (d >> 12) & MATERIAL_MASK
        mat_b = (d >> 8) & MATERIAL_MASK
        cap = (d >> 7) & 1
        flip = (d >> 6) & 1
        rot = (d >> 4) & 0x3
        variant = d & 0x3
        return np.stack([mat_a, mat_b, cap, flip, rot, variant], axis=-1)


# -- encoding ---------------------------------------------------------------


def encode_entry(mat_a, mat_b=0, cap=0, flip=0, rot=0, variant=0):
    """Pack one 16-bit MAT tile value from its parts.

    ``mat_a``/``mat_b`` are 4-bit material indices; ``rot`` is 0-3; ``cap`` and
    ``flip`` are booleans; ``variant`` is 0-3. Values are masked to their field
    widths. This mirrors the vendored WorldBuilder ``encode_entry``.
    """
    entry = 0
    entry |= (variant & 0x3)
    entry |= ((rot & 0x3) << 4)
    entry |= ((flip & 0x1) << 6)
    entry |= ((cap & 0x1) << 7)
    entry |= ((mat_b & MATERIAL_MASK) << 8)
    entry |= ((mat_a & MATERIAL_MASK) << 12)
    return entry


# -- auto-paint --------------------------------------------------------------


def auto_paint(heightmap, rules):
    """Generate a :class:`MaterialGrid` from a heightmap using ``rules``.

    ``heightmap`` is a :class:`~bzmap.formats.hg2.HeightMap`. ``rules`` is a
    list of dicts ``{'mat_id': int, 'min_h': float, 'max_h': float,
    'min_s': float, 'max_s': float}`` ordered by priority (lowest first; later
    rules override earlier ones). Heights are in metres, slopes in metres-per-
    metre gradient.

    The algorithm follows the vendored WorldBuilder ``AutoPainter``:

    1. Classify each heightmap cell to a material by the first matching rule
       (elevation and slope bands).
    2. For each 4x4 cell tile, march the four corner materials: a solid tile
       when all four agree, otherwise a transition tile whose corner mask picks
       a rotation/flip/cap shape and whose base/target materials are the two
       distinct corner values.

    Returns a :class:`MaterialGrid` sized ``(zonesZ * 64) x (zonesX * 64)``.
    """
    raw = heightmap.data
    h, w = raw.shape
    if h % TILE_CELLS or w % TILE_CELLS:
        raise ValueError(
            f"heightmap {w}x{h} is not a multiple of {TILE_CELLS} cells per "
            f"MAT tile"
        )

    heights = raw.astype(np.float64) * HEIGHT_SCALE
    slopes = slope(heightmap)

    vertex_mats = np.zeros_like(raw, dtype=np.uint8)
    for rule in rules:
        mat_id = int(rule["mat_id"])
        mask = (
            (heights >= rule["min_h"]) & (heights <= rule["max_h"])
            & (slopes >= rule["min_s"]) & (slopes <= rule["max_s"])
        )
        vertex_mats[mask] = mat_id

    mat_h, mat_w = h // TILE_CELLS, w // TILE_CELLS
    mat_data = np.zeros((mat_h, mat_w), dtype=np.uint16)

    for y in range(mat_h):
        for x in range(mat_w):
            # Four corner cells of this tile in (row, col) order TL, TR, BR, BL.
            colors = [
                int(vertex_mats[y * TILE_CELLS, x * TILE_CELLS]),          # TL
                int(vertex_mats[y * TILE_CELLS, x * TILE_CELLS + 1]),      # TR
                int(vertex_mats[y * TILE_CELLS + 1, x * TILE_CELLS + 1]),  # BR
                int(vertex_mats[y * TILE_CELLS + 1, x * TILE_CELLS]),      # BL
            ]
            mat_data[y, x] = _march_square(colors)

    return MaterialGrid(mat_data)


def _march_square(colors):
    """Encode one tile from its four corner material ids (TL, TR, BR, BL)."""
    unique = sorted(set(colors))
    base = unique[0]
    if len(unique) == 1:
        # Solid tile: one material everywhere.
        return encode_entry(base, base)

    nxt = unique[-1]
    # 4-bit mask of corners that take the higher-priority (next) material:
    # TL=8, TR=4, BR=2, BL=1.
    mask = 0
    if colors[0] == nxt:
        mask |= 8
    if colors[1] == nxt:
        mask |= 4
    if colors[2] == nxt:
        mask |= 2
    if colors[3] == nxt:
        mask |= 1

    cap, flip, rot = 0, 0, 0

    if mask == 15:
        # All corners are the next material -> promote it to base.
        base, nxt = nxt, base
    elif mask == 8:      # TL
        cap, flip, rot = 0, 0, 0
    elif mask == 4:      # TR
        cap, flip, rot = 0, 0, 3
    elif mask == 2:      # BR
        cap, flip, rot = 0, 0, 2
    elif mask == 1:      # BL
        cap, flip, rot = 0, 0, 1
    elif mask == 12:     # top half (TL+TR)
        cap, flip, rot = 0, 1, 0
    elif mask == 6:      # right half (TR+BR)
        cap, flip, rot = 0, 1, 3
    elif mask == 3:      # bottom half (BR+BL)
        cap, flip, rot = 0, 1, 2
    elif mask == 9:      # left half (TL+BL)
        cap, flip, rot = 0, 1, 1
    elif mask == 10:     # diagonal TL+BR
        cap, flip, rot = 1, 0, 0
    elif mask == 5:      # diagonal TR+BL
        cap, flip, rot = 1, 1, 0
    elif mask in (7, 11, 13, 14):
        # Three corners high, one low: swap base/target and treat the single
        # low corner as the transition shape.
        base, nxt = nxt, base
        inv = (~mask) & 15
        if inv == 8:
            cap, flip, rot = 0, 0, 0
        elif inv == 4:
            cap, flip, rot = 0, 0, 3
        elif inv == 2:
            cap, flip, rot = 0, 0, 2
        elif inv == 1:
            cap, flip, rot = 0, 0, 1

    return encode_entry(base, nxt, cap, flip, rot)


# -- convenience wrappers ----------------------------------------------------


def read_mat(path):
    """Read an ``.MAT`` file into a :class:`MaterialGrid`."""
    return MaterialGrid.read(path)


def write_mat(path, grid):
    """Write a :class:`MaterialGrid` to ``path``."""
    grid.write(path)