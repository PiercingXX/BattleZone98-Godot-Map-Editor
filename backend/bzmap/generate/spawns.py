"""Spawn cluster placement (docs/05 ``generate/spawns.py``).

Turns the base sites of a validated :class:`~bzmap.model.layout.LayoutGraph`
into concrete spawn objects on the final terrain, enforcing the spawn rules
from docs/04 §3:

- **B1** — every spawn sits on buildable ground: slope under 5° across at
  least a 20 m radius.  A spawn on a cliff face is dead, so the generator
  *snaps* any spawn that lands on unbuildable ground to the nearest buildable
  cell before emitting it (the same snap the economy generator uses for
  geysers).
- **B3** — ``_SW``/deathmatch gets **14 spawns in ``N_teams`` clusters** (one
  cluster per base, evenly split); within a cluster spawns sit 12–70 m apart
  and face outward toward the map centre.  ``_S`` gets **one spawn per base**,
  placed at the base site.

The generator is deterministic given a layout and heightmap: the same inputs
always produce the same spawn set (docs/08 fixed-seed determinism).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from math import atan2, cos, degrees, hypot, sin

import numpy as np

from bzmap.formats.hg2 import GRID_M, buildable_mask
from bzmap.model.layout import SPAWN, SW_SPAWN_COUNT, LayoutGraph

#: Rule B3: cluster spawn spacing bounds (metres), corpus range.
SPAWN_MIN_SPACING_M = 12.0
SPAWN_MAX_SPACING_M = 70.0

#: Rule B3: radius (metres) of the spawn ring around each base site.
CLUSTER_RADIUS_M = 45.0

#: Rule B3: angular jitter (radians) applied around the ring so spawns are not
#: perfectly collinear with their neighbours (kept small so spacing stays in
#: the corpus range).
CLUSTER_ANGLE_JITTER = 0.15

#: Rule E3/B1: slope ceiling (metres-per-metre) for buildable ground (tan 5°).
BUILDABLE_SLOPE = float(np.tan(np.radians(5.0)))

#: Rule B1: radius (metres) of the flat disc a spawn must sit inside.
SPAWN_PAD_RADIUS_M = 20.0

#: How far (metres) the generator will search for a buildable cell when
#: snapping a spawn off unbuildable ground.
SNAP_SEARCH_M = 150.0


@dataclass(frozen=True)
class SpawnObject:
    """A single placed spawn object (``pspwn_1``)."""

    id: str
    x: float
    z: float
    kind: str = SPAWN
    #: Team of the base cluster this spawn belongs to (B3).
    team: int = -1
    #: Facing (degrees) toward the map centre, so units spawn looking outward.
    yaw: float = 0.0


@dataclass
class SpawnResult:
    """Placed spawn objects plus the measured B3 metrics."""

    objects: list[SpawnObject] = field(default_factory=list)

    @property
    def spawns(self) -> list[SpawnObject]:
        return [o for o in self.objects if o.kind == SPAWN]

    def metrics(self) -> dict[str, float]:
        """Measured values for the spawn rules (B3)."""
        return dict(self._metrics)

    #: Internal store of measured values, populated by the generator.
    _metrics: dict[str, float] = field(default_factory=dict)


class SpawnGenerator:
    """Places spawn objects on a validated layout and heightmap.

    The generator is stateless apart from its tuning constants; call
    :meth:`generate` with a layout and heightmap to get a :class:`SpawnResult`.
    """

    def __init__(
        self,
        cluster_radius_m: float = CLUSTER_RADIUS_M,
        angle_jitter: float = CLUSTER_ANGLE_JITTER,
        min_spacing_m: float = SPAWN_MIN_SPACING_M,
        max_spacing_m: float = SPAWN_MAX_SPACING_M,
        buildable_slope: float = BUILDABLE_SLOPE,
        spawn_pad_radius_m: float = SPAWN_PAD_RADIUS_M,
        snap_search_m: float = SNAP_SEARCH_M,
    ):
        self.cluster_radius_m = float(cluster_radius_m)
        self.angle_jitter = float(angle_jitter)
        self.min_spacing_m = float(min_spacing_m)
        self.max_spacing_m = float(max_spacing_m)
        self.buildable_slope = float(buildable_slope)
        self.spawn_pad_radius_m = float(spawn_pad_radius_m)
        self.snap_search_m = float(snap_search_m)

    def generate(
        self, layout: LayoutGraph, heightmap, mode: str = "sw"
    ) -> SpawnResult:
        """Build and return the spawn set for ``layout``.

        ``layout`` must already have passed its graph-level validation and
        ``heightmap`` must be the final terrain (so B1 can be checked against
        real ground).  Spawns that land on unbuildable ground are snapped to
        the nearest buildable cell within ``snap_search_m``.

        ``mode`` is ``"sw"`` for the 14-spawn deathmatch/_SW set or ``"s"`` for
        the one-spawn-per-base strategy set.
        """
        buildable = buildable_mask(heightmap, self.buildable_slope)
        objects: list[SpawnObject] = []

        if mode == "s":
            objects = self._strategy_spawns(layout, buildable)
        else:
            objects = self._sw_spawns(layout, buildable)

        result = SpawnResult(objects=objects)
        result._metrics = self._measure(layout, result)
        return result

    # -- placement -------------------------------------------------------------

    def _strategy_spawns(
        self, layout: LayoutGraph, buildable: np.ndarray
    ) -> list[SpawnObject]:
        """Rule B3 (_S): one spawn per base, at the base site."""
        objects: list[SpawnObject] = []
        for bid in layout.base_ids:
            base = layout.nodes[bid]
            x, z = self._snap_to_buildable(base.x, base.z, buildable)
            objects.append(
                SpawnObject(
                    id=f"{bid}_spawn",
                    x=x,
                    z=z,
                    team=base.team,
                    yaw=self._facing(x, z, layout),
                )
            )
        return objects

    def _sw_spawns(
        self, layout: LayoutGraph, buildable: np.ndarray
    ) -> list[SpawnObject]:
        """Rule B3 (_SW): ``SW_SPAWN_COUNT`` spawns in ``n_teams`` clusters.

        Each base gets ``SW_SPAWN_COUNT // n_teams`` spawns on a ring around
        the base site, facing outward toward the map centre.  A small angular
        jitter keeps neighbours from being perfectly collinear while staying
        within the corpus 12–70 m spacing.
        """
        bases = layout.base_ids
        if not bases:
            return []
        per_cluster = max(1, SW_SPAWN_COUNT // layout.n_teams)
        objects: list[SpawnObject] = []
        for ci, bid in enumerate(bases):
            base = layout.nodes[bid]
            for i in range(per_cluster):
                angle = 2.0 * np.pi * i / per_cluster + ci * 0.3
                angle += self.angle_jitter * (0.5 - (i % 2))
                x = base.x + self.cluster_radius_m * cos(angle)
                z = base.z + self.cluster_radius_m * sin(angle)
                x, z = self._snap_to_buildable(x, z, buildable)
                objects.append(
                    SpawnObject(
                        id=f"{bid}_spawn{i}",
                        x=x,
                        z=z,
                        team=base.team,
                        yaw=self._facing(x, z, layout),
                    )
                )
        return objects

    # -- helpers ---------------------------------------------------------------

    def _snap_to_buildable(self, x, z, buildable) -> tuple[float, float]:
        """Return ``(x, z)`` moved to the nearest buildable cell if needed.

        A spawn is buildable when the whole ``spawn_pad_radius_m`` disc around
        it is under the slope ceiling (B1).  If the current position fails, the
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
        """True when the slope under a ``spawn_pad_radius_m`` disc is buildable.

        The disc is sampled on the 5 m grid: every cell whose centre lies within
        the pad radius of ``(x, z)`` must be buildable (B1).
        """
        cz = round(z / GRID_M)
        cx = round(x / GRID_M)
        r_cells = self.spawn_pad_radius_m / GRID_M
        gz, gx = buildable.shape
        zz, xx = np.ogrid[0:gz, 0:gx]
        mask = (zz - cz) ** 2 + (xx - cx) ** 2 <= r_cells * r_cells
        return bool(np.all(buildable[mask]))

    def _facing(self, x: float, z: float, layout: LayoutGraph) -> float:
        """Yaw (degrees) from ``(x, z)`` toward the map centre (B3 outward)."""
        cx = layout.width_m / 2.0
        cz = layout.depth_m / 2.0
        return degrees(atan2(cx - x, cz - z))

    def _measure(self, layout: LayoutGraph, result: SpawnResult) -> dict[str, float]:
        """Compute the B3 measured values for the result."""
        m: dict[str, float] = {}

        spawns = result.spawns
        m["spawn_count"] = float(len(spawns))
        m["cluster_count"] = float(len({s.team for s in spawns if s.team >= 0}))

        # B3: within a cluster each spawn's nearest neighbour must sit 12–70 m
        # away (corpus min spacing 47 m).  Report the min/max nearest-neighbour
        # distance across all spawns.
        clusters: dict[int, list[SpawnObject]] = {}
        for s in spawns:
            clusters.setdefault(s.team, []).append(s)
        nearest_gaps: list[float] = []
        for members in clusters.values():
            if len(members) < 2:
                continue  # nearest-neighbour is undefined for a lone spawn
            for i, a in enumerate(members):
                gap = min(
                    hypot(a.x - b.x, a.z - b.z)
                    for j, b in enumerate(members)
                    if j != i
                )
                nearest_gaps.append(gap)
        m["min_cluster_spacing_m"] = min(nearest_gaps) if nearest_gaps else 0.0
        m["max_cluster_spacing_m"] = max(nearest_gaps) if nearest_gaps else 0.0

        return m


def generate_spawns(
    layout: LayoutGraph, heightmap, mode: str = "sw", seed: int | None = None
) -> SpawnResult:
    """Convenience wrapper producing the spawn set for ``layout``.

    ``seed`` is accepted for API symmetry with the other generators; placement
    is fully deterministic from the layout and heightmap, so the same inputs
    always yield the same spawns regardless of seed.
    """
    return SpawnGenerator().generate(layout, heightmap, mode=mode)