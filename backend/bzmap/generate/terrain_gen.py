"""Terrain synthesis: plateau → carve → erode → flatten pads (docs/05).

Produces a :class:`~bzmap.formats.hg2.HeightMap` for a validated
:class:`~bzmap.model.layout.LayoutGraph`, following the "carve, don't
accumulate" approach of docs/04 §7:

1. Start from a flat plateau at a nonzero raw elevation (Rule T2: modal raw
   500–1500, never built up from 0).
2. Carve canyons and basins *downward* along the layout's route corridors so
   the flat plateau between them survives (Rule T1 flat ground).
3. Erode with a Gaussian blur for natural-looking slopes (``scipy``, already a
   WorldBuilder dep).
4. Flatten buildable pads at base sites and geyser pads explicitly *after*
   erosion (Rules B1, E3) so flat ground is guaranteed, not hoped for.
5. Ring the outer boundary with impassable terrain (Rule T4) so players cannot
   drive off the heightmap edge.

Rule T3 (never saturate) is enforced by clipping to the 12-bit ceiling with
headroom below the 3900 warning line.  The synthesis is fully deterministic
given a layout: the same graph always yields the same ``HeightMap``.
"""

from __future__ import annotations

import numpy as np
from scipy import ndimage

from bzmap.formats.hg2 import GRID_M, ZONE_M, ZONE_SIZE, HeightMap
from bzmap.model.layout import BASE, GEYSER, LayoutGraph

#: Raw elevation of the starting plateau (Rule T2: 500–1500 raw).
PLATEAU_RAW = 1000

#: Raw height subtracted at the bottom of a carved corridor.
CARVE_DEPTH_RAW = 300

#: Half-width (metres) of a carved corridor around a route.
CORRIDOR_HALF_WIDTH_M = 90.0

#: Width (metres) of the ramp that blends each carved corridor floor up to the
#: surrounding plateau. A hard step from the corridor (plateau minus
#: ``CARVE_DEPTH_RAW``) to the plateau would leave a >30° wall (Rule C1), and
#: where two corridors meet it would ring a flat plateau mound in impassable
#: terrain, creating an enclosed traversable pocket (Rule C2). Ramping the carve
#: over this band keeps every plateau region connected to the corridor network
#: at ≤30° slope (docs/04 §4). ``CARVE_DEPTH_RAW`` raw is ``0.1 * 300 = 30`` m of
#: rise, which at ≤30° (0.577 m/m) needs at least 52 m of horizontal run.
CARVE_RAMP_M = 75.0

#: Radius (metres) of a flattened buildable pad around a base or geyser.
PAD_RADIUS_M = 60.0

#: Width (metres) of the ramp annulus around each flattened pad that blends the
#: pad down to the surrounding terrain. A pad flattened to the plateau above a
#: carved corridor would otherwise end in a near-vertical cliff (>30°), which
#: the Tier 2 connectivity validator (Rule C1) rejects as unreachable. The ramp
#: keeps the pad reachable at ≤30° slope (docs/04 §4).
PAD_RAMP_M = 90.0

#: Fraction of the map edge raised into impassable terrain (Rule T4).
BOUNDARY_FRACTION = 0.05

#: Raw height of the impassable boundary ring (well above the plateau, below
#: the 3900 saturation warning of Rule T3).
BOUNDARY_RAW = 3800

#: Gaussian sigma (cells) for the erosion pass.
ERODE_SIGMA = 2.0


class TerrainGenerator:
    """Synthesises a :class:`HeightMap` from a validated :class:`LayoutGraph`.

    The generator is stateless apart from its tuning constants; call
    :meth:`generate` with a layout to get a heightmap.
    """

    def __init__(
        self,
        plateau_raw: int = PLATEAU_RAW,
        carve_depth_raw: int = CARVE_DEPTH_RAW,
        corridor_half_width_m: float = CORRIDOR_HALF_WIDTH_M,
        carve_ramp_m: float = CARVE_RAMP_M,
        pad_radius_m: float = PAD_RADIUS_M,
        pad_ramp_m: float = PAD_RAMP_M,
        boundary_fraction: float = BOUNDARY_FRACTION,
        boundary_raw: int = BOUNDARY_RAW,
        erode_sigma: float = ERODE_SIGMA,
    ):
        self.plateau_raw = int(plateau_raw)
        self.carve_depth_raw = int(carve_depth_raw)
        self.corridor_half_width_m = float(corridor_half_width_m)
        self.carve_ramp_m = float(carve_ramp_m)
        self.pad_radius_m = float(pad_radius_m)
        self.pad_ramp_m = float(pad_ramp_m)
        self.boundary_fraction = float(boundary_fraction)
        self.boundary_raw = int(boundary_raw)
        self.erode_sigma = float(erode_sigma)

    def generate(self, layout: LayoutGraph) -> HeightMap:
        """Build and return the heightmap for ``layout``.

        ``layout`` must already have passed its graph-level validation
        (docs/04 §7 step 1).  The grid is sized to whole zones from the
        layout's width/depth.
        """
        zones_x = max(1, round(layout.width_m / ZONE_M))
        zones_z = max(1, round(layout.depth_m / ZONE_M))
        grid_x = zones_x * ZONE_SIZE
        grid_z = zones_z * ZONE_SIZE

        data = np.full((grid_z, grid_x), self.plateau_raw, dtype=np.float64)

        # 1. Carve corridors downward along every route so the flat plateau
        #    between them survives (Rule T1).  The carve is a smooth ramp from
        #    the corridor floor up to the plateau over ``carve_ramp_m``, so the
        #    plateau connects to every corridor at ≤30° (Rule C1) instead of
        #    leaving enclosed plateau mounds ringed by steep walls (Rule C2).
        segments = [
            (layout.nodes[a], layout.nodes[b])
            for a, b in layout._edges
        ]
        dist = _corridor_distance(
            (grid_z, grid_x),
            [(na.x, na.z, nb.x, nb.z) for na, nb in segments],
        )
        hw = self.corridor_half_width_m / GRID_M
        ramp_w = max(1.0, self.carve_ramp_m / GRID_M)
        # t: 0 inside the corridor (full carve), 1 at the ramp edge (no carve).
        t = np.clip((dist - hw) / ramp_w, 0.0, 1.0)
        carve_depth = self.carve_depth_raw * (1.0 - t)
        data -= carve_depth

        # 2. Erode: blur the carved walls into natural slopes.
        data = ndimage.gaussian_filter(data, sigma=self.erode_sigma)

        # 3. Flatten buildable pads at base sites and geyser pads (B1, E3),
        #    ramping each pad down to the surrounding terrain so it stays
        #    reachable at ≤30° (Rule C1).
        for node in layout.nodes.values():
            if node.kind in (BASE, GEYSER):
                _flatten_pad(
                    data, node.x, node.z,
                    self.pad_radius_m, self.plateau_raw, self.pad_ramp_m,
                )

        # 4. Ring the boundary with impassable terrain (Rule T4), last so it
        #    always wins over any pad that strayed to the edge.
        _ring_boundary(
            data, self.boundary_fraction, self.boundary_raw, self.plateau_raw
        )

        # Rule T3: never saturate.  Clip with headroom below the 3900 warning
        # line; raw 0 means undefined, so floor at 1.
        data = np.clip(data, 1, 4095)

        return HeightMap(zones_x, zones_z, data.astype(np.uint16))


def generate_terrain(layout: LayoutGraph, seed: int | None = None) -> HeightMap:
    """Convenience wrapper producing a heightmap for ``layout``.

    ``seed`` is accepted for API symmetry with the other generators; the
    synthesis is fully deterministic from the layout alone, so the same layout
    always yields the same heightmap regardless of seed.
    """
    return TerrainGenerator().generate(layout)


# -- helpers ------------------------------------------------------------------


def _corridor_distance(shape: tuple[int, int],
                       segments: list[tuple[float, float, float, float]]) -> np.ndarray:
    """Distance (cells) from each cell to the nearest route segment.

    ``shape`` is ``(grid_z, grid_x)``; ``segments`` is a list of
    ``(x0, z0, x1, z1)`` world-coordinate (metres) segment endpoints. Returns a
    float array of the Euclidean distance from each cell centre to the nearest
    point on any segment.
    """
    grid_z, grid_x = shape
    zz, xx = np.mgrid[0:grid_z, 0:grid_x]
    dist = np.full((grid_z, grid_x), np.inf)
    for x0, z0, x1, z1 in segments:
        gx0, gz0 = x0 / GRID_M, z0 / GRID_M
        gx1, gz1 = x1 / GRID_M, z1 / GRID_M
        seg_x, seg_z = gx1 - gx0, gz1 - gz0
        seg_len2 = seg_x * seg_x + seg_z * seg_z
        dx, dz = xx - gx0, zz - gz0
        if seg_len2 == 0.0:
            d = np.hypot(dx, dz)
        else:
            t = np.clip((dx * seg_x + dz * seg_z) / seg_len2, 0.0, 1.0)
            d = np.hypot(xx - (gx0 + t * seg_x), zz - (gz0 + t * seg_z))
        dist = np.minimum(dist, d)
    return dist


def _flatten_pad(data: np.ndarray, x: float, z: float, radius_m: float,
                 plateau_raw: int, ramp_m: float) -> None:
    """Flatten a buildable disc around world ``(x, z)`` and ramp it down.

    Mutates ``data`` in place. Every cell inside a disc of ``radius_m`` is set
    to ``plateau_raw``, guaranteeing a buildable pocket (Rules B1, E3). The
    annulus from the disc edge out to ``radius_m + ramp_m`` is blended linearly
    from ``plateau_raw`` down to the surrounding (pre-flatten) terrain, so a
    pad sitting above a carved corridor meets it at ≤30° slope instead of a
    cliff (Rule C1 reachability). The operation is bounded to a box around the
    pad rather than the whole grid, so it stays cheap on large maps.
    """
    cz = round(z / GRID_M)
    cx = round(x / GRID_M)
    r_cells = radius_m / GRID_M
    ramp_cells = max(1.0, ramp_m / GRID_M)
    span = int(np.ceil(r_cells + ramp_cells)) + 1

    z0 = max(0, cz - span)
    z1 = min(data.shape[0], cz + span + 1)
    x0 = max(0, cx - span)
    x1 = min(data.shape[1], cx + span + 1)

    region = data[z0:z1, x0:x1]
    original = region.copy()
    zz, xx = np.ogrid[0:region.shape[0], 0:region.shape[1]]
    dist = np.sqrt((zz - (cz - z0)) ** 2 + (xx - (cx - x0)) ** 2)

    pad = dist <= r_cells
    region[pad] = plateau_raw

    ramp = (dist > r_cells) & (dist <= r_cells + ramp_cells)
    t = np.clip((dist[ramp] - r_cells) / ramp_cells, 0.0, 1.0)
    region[ramp] = plateau_raw + t * (original[ramp] - plateau_raw)


def _ring_boundary(data: np.ndarray, fraction: float, raw: int,
                   plateau_raw: int) -> None:
    """Ring the map edge with steep impassable terrain (Rule T4).

    The outer ``fraction`` band is ramped linearly from ``plateau_raw`` at the
    play-area edge up to ``raw`` at the map edge, so every boundary cell has a
    steep (>30°) slope and is impassable. A flat wall would leave the outermost
    cells with zero slope (flat), forming a traversable ring that the Tier 2
    connectivity validator (Rule C2) rejects as an enclosed pocket.
    """
    grid_z, grid_x = data.shape
    b = max(1, round(fraction * min(grid_z, grid_x)))
    for i in range(b):
        t = (i + 1) / b  # ~0 at the play-area edge, 1 at the map edge
        h = plateau_raw + t * (raw - plateau_raw)
        data[i, :] = h
        data[grid_z - 1 - i, :] = h
        data[:, i] = h
        data[:, grid_x - 1 - i] = h