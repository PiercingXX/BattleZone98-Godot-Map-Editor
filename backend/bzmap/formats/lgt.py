"""``.LGT`` baked lightmap reader/writer — copy-only (docs/01 §3, docs/09 E1).

The ``.LGT`` format is **unresolved** (docs/09 E1, highest priority). All that is
verified is its size across the five map dimensions:

    bytes = (zonesX * zonesZ + 1) * 65536

The base term is one byte per heightmap cell; the ``+1`` extra 65536-byte plane
is unexplained. Contents are real baked lighting (~200 distinct byte values per
file, map-specific modal values), and neither ``MakeTRN.exe`` nor WorldBuilder
generates one.

Because the byte layout is unknown, :class:`LightMap` is deliberately **copy-only**:
it round-trips whatever bytes it is given verbatim and never decodes or invents
values. This satisfies the round-trip gate (Rule 4) while the format question stays
open — a generator that fabricates bytes would bake a wrong guess into every map.
"""

from __future__ import annotations

from pathlib import Path

# One 65536-byte plane per zone, plus one unexplained extra plane.
_PLANE_BYTES = 65536


class LightMap:
    """In-memory representation of an ``.LGT`` lightmap.

    ``data`` is the raw file bytes, held verbatim. The object is opaque by design:
    the byte layout is unresolved (docs/09 E1), so no decoding or synthesis is
    attempted. ``zonesX``/``zonesZ`` are carried for size validation only.
    """

    __slots__ = ("data", "zonesX", "zonesZ")

    def __init__(self, data, zonesX, zonesZ):
        self.zonesX = int(zonesX)
        self.zonesZ = int(zonesZ)
        self.data = bytes(data)

        expected = (self.zonesX * self.zonesZ + 1) * _PLANE_BYTES
        if len(self.data) != expected:
            raise ValueError(
                f"LGT size {len(self.data)} does not match expected "
                f"({self.zonesX}x{self.zonesZ} zones -> {expected} bytes)"
            )

    @property
    def plane_count(self):
        """Number of 65536-byte planes (``zonesX * zonesZ + 1``)."""
        return self.zonesX * self.zonesZ + 1

    # -- serialization -----------------------------------------------------

    @classmethod
    def read(cls, path, zonesX, zonesZ):
        """Read an ``.LGT`` file from ``path`` into a :class:`LightMap`.

        ``zonesX``/``zonesZ`` are the map's zone dimensions (from the ``.HG2``
        header or the ``.trn`` ``Width``/``Depth``); they are used to validate
        the file size against the documented formula.
        """
        path = Path(path)
        data = path.read_bytes()
        return cls(data, zonesX, zonesZ)

    def write(self, path):
        """Write this lightmap to ``path``, byte-identical to the source."""
        Path(path).write_bytes(self.data)


# -- convenience wrappers ----------------------------------------------------


def read_lgt(path, zonesX, zonesZ):
    """Read an ``.LGT`` file into a :class:`LightMap`."""
    return LightMap.read(path, zonesX, zonesZ)


def write_lgt(path, lightmap):
    """Write a :class:`LightMap` to ``path``."""
    lightmap.write(path)