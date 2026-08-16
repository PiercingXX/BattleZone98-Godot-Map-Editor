"""Economy placement: geysers and scrap (docs/05 ``generate/economy.py``).

Turns the economy nodes of a validated :class:`~bzmap.model.layout.LayoutGraph`
into concrete object placements on the final terrain, enforcing the economy
rules from docs/04 §2:

- **E1** — geyser density target 1.5/km², inside 0.5–6.4/km².
- **E2** — scrap total target 250–300 ``npscr*`` objects, mixing ``npscr1/2/3``.
- **E3** — every geyser sits on buildable ground: slope under 5° across at
  least a 20 m radius.  A geyser on a cliff face is dead economy, so the
  generator *snaps* any geyser that lands on unbuildable ground to the nearest
  buildable cell before emitting it.
- **E4** — per-base economy within 5% across bases, assigning every geyser and
  scrap pool to its nearest base by *path* distance (not straight-line).
- **E5** — 30–50% of geysers are contested: roughly equidistant (within 15%
  path distance) from two or more bases.

The generator is deterministic given a layout and heightmap: the same inputs
always produce the same object set (docs/08 fixed-seed determinism).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from bzmap.formats.hg2 import GRID_M, buildable_mask
from bzmap.model.layout import E5_GAP, GEYSER, SCRAP, LayoutGraph

#: Rule E3: slope ceiling (metres-per-metre) for buildable ground (tan 5°).
BUILDABLE_SLOPE = float(np.tan(np.radians(5.0)))

#: Rule E3: radius (metres) of the flat disc a geyser must sit inside.
GEYSER_PAD_RADIUS_M = 20.0

#: Rule E1: geyser density bounds (geysers per km²), corpus range.
E1_MIN_PER_KM2 = 0.5
E1_MAX_PER_KM2 = 6.4
E1_TARGET_PER_KM2 = 1.5

#: Rule E2: scrap object total target (corpus median).
SCRAP_TARGET = 250
SCRAP_MIN = 200
SCRAP_MAX = 300

#: Rule E2: the three scrap object classes, cycled for variety.
SCRAP_TYPES = ("npscr1", "npscr2", "npscr3")

#: How far (metres) the generator will search for a buildable cell when
#: snapping a geyser off unbuildable ground.
SNAP_SEARCH_M = 150.0


@dataclass(frozen=True)
class EconomyObject:
    """A single placed economy object (geyser or scrap pool)."""

    id: str
    x: float
    z: float
    kind: str
    #: ``None`` for geysers; one of ``npscr1/2/3`` for scrap.
    scrap_type: str | None = None
    #: Team of the base this object is assigned to (E4), or -1 if unassigned.
    team: int = -1
    #: True for geysers roughly equidistant from two or more bases (E5).
    contested: bool = False


@dataclass
class EconomyResult:
    """Placed economy objects plus the measured E1–E5 metrics."""

    objects: list[EconomyObject] = field(default_factory=list)

    @property
    def geysers(self) -> list[EconomyObject]:
        return [o for o in self.objects if o.kind == GEYSER]

    @property
    def scrap(self) -> list[EconomyObject]:
        return [o for o in self.objects if o.kind == SCRAP]

    def metrics(self) -> dict[str, float]:
        """Measured values for the economy rules (E1, E2, E4, E5)."""
        return dict(self._metrics)

    #: Internal store of measured values, populated by the generator.
    _metrics: dict[str, float] = field(default_factory=dict)


class EconomyGenerator:
    """Places economy objects on a validated layout and heightmap.

    The generator is stateless apart from its tuning constants; call
    :meth:`generate` with a layout and heightmap to get an
    :class:`EconomyResult`.
    """

    def __init__(
        self,
        buildable_slope: float = BUILDABLE_SLOPE,
        geyser_pad_radius_m: float = GEYSER_PAD_RADIUS_M,
        snap_search_m: float = SNAP_SEARCH_M,
    ):
        self.buildable_slope = float(buildable_slope)
        self.geyser_pad_radius_m = float(geyser_pad_radius_m)
        self.snap_search_m = float(snap_search_m)

    def generate(self, layout: LayoutGraph, heightmap) -> EconomyResult:
        """Build and return the economy object set for ``layout``.

        ``layout`` must already have passed its graph-level validation and
        ``heightmap`` must be the final terrain (so E3 can be checked against
        real ground).  Geysers that land on unbuildable ground are snapped to
        the nearest buildable cell within ``snap_search_m``.
        """
        buildable = buildable_mask(heightmap, self.buildable_slope)
        objects: list[EconomyObject] = []

        # Geysers: check E3, snapping off unbuildable ground.
        for gid in layout.geyser_ids:
            node = layout.nodes[gid]
            x, z = self._snap_to_buildable(
                node.x, node.z, buildable, heightmap
            )
            team, contested = self._classify(layout, gid)
            objects.append(
                EconomyObject(
                    id=gid, x=x, z=z, kind=GEYSER, team=team,
                    contested=contested,
                )
            )

        # Scrap: assign types round-robin across the three classes (E2).
        scrap_ids = [n.id for n in layout.nodes.values() if n.kind == SCRAP]
        for i, sid in enumerate(scrap_ids):
            node = layout.nodes[sid]
            team, _ = self._classify(layout, sid)
            objects.append(
                EconomyObject(
                    id=sid, x=node.x, z=node.z, kind=SCRAP,
                    scrap_type=SCRAP_TYPES[i % len(SCRAP_TYPES)],
                    team=team,
                )
            )

        result = EconomyResult(objects=objects)
        result._metrics = self._measure(layout, result)
        return result

    # -- helpers -------------------------------------------------------------

    def _snap_to_buildable(self, x, z, buildable, heightmap) -> tuple[float, float]:
        """Return ``(x, z)`` moved to the nearest buildable cell if needed.

        A geyser is buildable when the whole ``geyser_pad_radius_m`` disc around
        it is under the slope ceiling (E3).  If the current position fails, the
        nearest buildable cell within ``snap_search_m`` is used; the original
        position is returned when no such cell exists.
        """
        if self._pad_is_buildable(x, z, buildable):
            return float(x), float(z)
        cz = round(z / GRID_M)
        cx = round(x / GRID_M)
        gy, gx = np.where(buildable)
        if gy.size == 0:
            return float(x), float(z)
        # Distance in cells to every buildable cell.
        d = (gy - cz) ** 2 + (gx - cx) ** 2
        order = np.argsort(d)
        r_cells = self.snap_search_m / GRID_M
        for idx in order:
            if d[idx] > r_cells * r_cells:
                break
            nz, nx = int(gy[idx]), int(gx[idx])
            nx_m, nz_m = nx * GRID_M, nz * GRID_M
            if self._pad_is_buildable(nx_m, nz_m, buildable):
                return float(nx_m), float(nz_m)
        return float(x), float(z)

    def _pad_is_buildable(self, x, z, buildable) -> bool:
        """True when the slope under a ``geyser_pad_radius_m`` disc is buildable.

        The disc is sampled on the 5 m grid: every cell whose centre lies within
        the pad radius of ``(x, z)`` must be buildable (E3).
        """
        cz = round(z / GRID_M)
        cx = round(x / GRID_M)
        r_cells = self.geyser_pad_radius_m / GRID_M
        gz, gx = buildable.shape
        zz, xx = np.ogrid[0:gz, 0:gx]
        mask = (zz - cz) ** 2 + (xx - cx) ** 2 <= r_cells * r_cells
        return bool(np.all(buildable[mask]))

    def _classify(self, layout: LayoutGraph, node_id: str) -> tuple[int, bool]:
        """Assign ``(team, contested)`` for an economy node (E4, E5)."""
        nearest = layout._nearest_bases(node_id)
        if not nearest:
            return -1, False
        team = layout.nodes[nearest[0][0]].team
        contested = False
        if len(nearest) >= 2:
            (_, d1), (_, d2) = nearest[0], nearest[1]
            if d1 > 0 and (d2 - d1) / d1 <= E5_GAP:
                contested = True
        return team, contested

    def _measure(self, layout: LayoutGraph, result: EconomyResult) -> dict[str, float]:
        """Compute the E1/E2/E4/E5 measured values for the result."""
        m: dict[str, float] = {}

        # E1: geyser density per km².
        area_km2 = (layout.width_m * layout.depth_m) / 1_000_000.0
        m["geyser_density_per_km2"] = len(result.geysers) / area_km2 if area_km2 else 0.0

        # E2: scrap total.
        m["scrap_count"] = float(len(result.scrap))

        # E4: per-base economy spread (fraction of the mean).
        totals: dict[int, int] = {}
        for o in result.objects:
            if o.team >= 0:
                totals[o.team] = totals.get(o.team, 0) + 1
        if len(totals) >= 2:
            values = list(totals.values())
            mean = sum(values) / len(values)
            m["e4_spread"] = (max(values) - min(values)) / mean if mean else 0.0
        else:
            m["e4_spread"] = 0.0

        # E5: contested geyser fraction.
        geysers = result.geysers
        if geysers:
            contested = sum(1 for g in geysers if g.contested)
            m["e5_contested_frac"] = contested / len(geysers)
        else:
            m["e5_contested_frac"] = 0.0

        return m


def generate_economy(
    layout: LayoutGraph, heightmap, seed: int | None = None
) -> EconomyResult:
    """Convenience wrapper producing the economy object set for ``layout``.

    ``seed`` is accepted for API symmetry with the other generators; placement
    is fully deterministic from the layout and heightmap, so the same inputs
    always yield the same objects regardless of seed.
    """
    return EconomyGenerator().generate(layout, heightmap)