"""``.HG2`` heightmap reader/writer (docs/01 §1).

The file is a 12-byte little-endian header followed by ``zonesX * zonesZ *
256 * 256`` uint16 height samples. **The data is zone-major**: a sequence of
256×256 zone blocks in row-major *zone* order; within each zone the cells are
row-major. Naive row-major decoding produces tiled garbage (verified in
docs/01 and confirmed against WorldBuilder's ``convert_hg2_to_png``).

Scale is ``height_metres = raw * 0.1`` with a 5 m grid spacing. Raw range is
0–4095 (12-bit); a raw value of 0 means *undefined/out-of-play*, not sea
level — playable terrain sits on a plateau well above zero.

The header ``unknownA`` field varies per map with no known pattern, so it is
preserved verbatim from the source map and never invented.
"""

from __future__ import annotations

import struct
from pathlib import Path

import numpy as np

# Header layout: version, depth, zonesX, zonesZ, unknownA, unknownB.
_HEADER = struct.Struct("<HHHHHH")

# Zone edge length in cells. ``depth`` in the header is the log2 of this.
ZONE_SIZE = 256

# Grid spacing in metres between adjacent height samples.
GRID_M = 5.0

# Height scale: raw sample value -> metres.
HEIGHT_SCALE = 0.1

# Metres of horizontal distance spanned by one zone (1280 m per docs/01).
ZONE_M = 1280.0


class HeightMap:
    """In-memory representation of an ``.HG2`` heightmap.

    ``data`` is a 2-D ``numpy.uint16`` array in **world row-major** order with
    shape ``(zonesZ * ZONE_SIZE, zonesX * ZONE_SIZE)`` — i.e. de-zoned. The
    zone-major on-disk layout is applied only at read/write time, so the
    in-memory array is convenient to index and sample while still
    round-tripping byte-identically.
    """

    __slots__ = ("data", "depth", "unknownA", "unknownB", "version", "zonesX", "zonesZ")

    def __init__(self, zonesX, zonesZ, data, version=1, depth=8,
                 unknownA=10, unknownB=0):
        self.version = version
        self.depth = depth
        self.zonesX = int(zonesX)
        self.zonesZ = int(zonesZ)
        self.unknownA = int(unknownA)
        self.unknownB = int(unknownB)
        self.data = np.asarray(data, dtype=np.uint16)

        expected = (self.zonesZ * ZONE_SIZE, self.zonesX * ZONE_SIZE)
        if self.data.shape != expected:
            raise ValueError(
                f"data shape {self.data.shape} does not match header "
                f"{self.zonesX}x{self.zonesZ} zones (expected {expected})"
            )

    # -- geometry ----------------------------------------------------------

    @property
    def grid_x(self):
        """Number of height cells along the X axis."""
        return self.zonesX * ZONE_SIZE

    @property
    def grid_z(self):
        """Number of height cells along the Z axis."""
        return self.zonesZ * ZONE_SIZE

    @property
    def width_m(self):
        """Map width in metres."""
        return self.zonesX * ZONE_M

    @property
    def depth_m(self):
        """Map depth in metres."""
        return self.zonesZ * ZONE_M

    # -- serialization -----------------------------------------------------

    @classmethod
    def read(cls, path):
        """Read an ``.HG2`` file from ``path`` into a :class:`HeightMap`."""
        path = Path(path)
        with open(path, "rb") as fh:
            header = fh.read(_HEADER.size)
            if len(header) != _HEADER.size:
                raise ValueError(f"{path}: truncated header ({len(header)} bytes)")
            version, depth, zonesX, zonesZ, unknownA, unknownB = _HEADER.unpack(header)

            zone_size = 2 ** depth
            if zone_size != ZONE_SIZE:
                raise ValueError(
                    f"{path}: unsupported zone size {zone_size} (depth={depth}); "
                    f"only {ZONE_SIZE} is supported"
                )

            raw = np.frombuffer(fh.read(), dtype=np.uint16)
            expected = zonesX * zonesZ * zone_size * zone_size
            if raw.size != expected:
                raise ValueError(
                    f"{path}: expected {expected} height samples, got {raw.size}"
                )

        # De-zone: reshape the flat zone-major stream into zones, then scatter
        # each zone block into its world position.
        zones = raw.reshape(zonesZ, zonesX, zone_size, zone_size)
        data = np.empty((zonesZ * zone_size, zonesX * zone_size), dtype=np.uint16)
        for zy in range(zonesZ):
            for zx in range(zonesX):
                data[zy * zone_size:(zy + 1) * zone_size,
                     zx * zone_size:(zx + 1) * zone_size] = zones[zy, zx]

        return cls(zonesX, zonesZ, data, version=version, depth=depth,
                   unknownA=unknownA, unknownB=unknownB)

    def write(self, path):
        """Write this heightmap to ``path``, byte-identical to the source zone-major layout."""
        path = Path(path)
        with open(path, "wb") as fh:
            fh.write(_HEADER.pack(self.version, self.depth, self.zonesX,
                                  self.zonesZ, self.unknownA, self.unknownB))
            zone_size = 2 ** self.depth
            for zy in range(self.zonesZ):
                for zx in range(self.zonesX):
                    zone = self.data[zy * zone_size:(zy + 1) * zone_size,
                                     zx * zone_size:(zx + 1) * zone_size]
                    fh.write(zone.tobytes())


def read_hg2(path):
    """Read an ``.HG2`` file into a :class:`HeightMap` (convenience wrapper)."""
    return HeightMap.read(path)


def write_hg2(path, heightmap):
    """Write a :class:`HeightMap` to ``path`` (convenience wrapper)."""
    heightmap.write(path)


# -- sampling ---------------------------------------------------------------


def _cell(raw, x, z):
    """Return the raw height sample at integer grid cell ``(x, z)``.

    Out-of-range cells clamp to the nearest edge cell.
    """
    x = max(0, min(raw.shape[1] - 1, int(x)))
    z = max(0, min(raw.shape[0] - 1, int(z)))
    return int(raw[z, x])


def sample_m(heightmap, x, z):
    """Bilinearly sample the height in **metres** at world coordinate ``(x, z)``.

    ``x`` and ``z`` are metres in map space (``0 <= x < width_m``,
    ``0 <= z < depth_m``). The sample is bilinearly interpolated between the
    four surrounding grid cells and scaled by ``HEIGHT_SCALE``. Cells outside
    the grid clamp to the map edge.
    """
    raw = heightmap.data
    # Convert world metres to fractional grid-cell coordinates.
    gx = x / GRID_M
    gz = z / GRID_M

    x0 = int(np.floor(gx))
    z0 = int(np.floor(gz))
    fx = gx - x0
    fz = gz - z0

    # Clamp the base cell so the interpolation window stays in bounds.
    x0 = max(0, min(raw.shape[1] - 2, x0))
    z0 = max(0, min(raw.shape[0] - 2, z0))

    h00 = _cell(raw, x0, z0)
    h10 = _cell(raw, x0 + 1, z0)
    h01 = _cell(raw, x0, z0 + 1)
    h11 = _cell(raw, x0 + 1, z0 + 1)

    top = h00 + fx * (h10 - h00)
    bottom = h01 + fx * (h11 - h01)
    return (top + fz * (bottom - top)) * HEIGHT_SCALE


# -- slope / buildability ---------------------------------------------------


def slope(heightmap):
    """Return a 2-D ``float`` array of terrain gradient magnitude per cell.

    Gradient is computed with central differences over the 5 m grid spacing,
    in metres of rise per metre of run. Edge cells use one-sided differences.
    """
    raw = heightmap.data.astype(np.float64) * HEIGHT_SCALE
    dz, dx = np.gradient(raw, GRID_M, GRID_M)
    return np.hypot(dx, dz)


def buildable_mask(heightmap, max_slope=0.25):
    """Return a boolean 2-D mask of cells gentle enough to build on.

    A cell is buildable when its gradient (see :func:`slope`) is at or below
    ``max_slope`` metres-per-metre. The default 0.25 (≈14°) is a permissive
    construction threshold; callers may tighten it per rule.
    """
    return slope(heightmap) <= max_slope