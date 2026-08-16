"""Tier 2 balance validation — rules E4-E5, B1-B3 (docs/06, docs/04 §2-§3).

The fairness and spawn-placement rules. Unlike connectivity (pass/fail) these
mix errors and warnings; the severity split follows docs/06 §Tier 2:

- **E4** (error) — per-base economy within **5%** across bases. Every geyser
  and scrap pool is assigned to its nearest base by *path* distance and the
  totals compared (docs/04 §2).
- **E5** (warning) — **30–50%** of geysers are contested: roughly equidistant
  (within 15% path distance) from two or more bases (docs/04 §2).
- **B1** (error) — each base needs a contiguous buildable pocket of **≥ 4,000
  m²** with slope under 5° — enough for a recycler plus a production line
  (docs/04 §3).
- **B2** (warning) — base separation: path distance between nearest bases is
  **35–60%** of the map diagonal (docs/04 §3).
- **B3** (error) — spawn cluster geometry: ``_SW``/deathmatch is 14 spawns in
  ``n_teams`` clusters, spawns within a cluster 12–70 m apart facing outward;
  ``_S`` is one spawn per base (docs/04 §3).

The buildable mask (B1) comes from the heightmap; the path distances (E4/E5/B2)
and spawns (B3) come from the layout graph. Measured values are exposed
separately from the verdicts so the report task can record *what was measured*
(docs/06 §Reporting).
"""

from __future__ import annotations

from collections import deque

import numpy as np

from bzmap.formats.hg2 import GRID_M, HeightMap, buildable_mask, read_hg2
from bzmap.model.layout import (
    B2_MAX_FRAC,
    B2_MIN_FRAC,
    E4_MAX_SPREAD,
    E5_GAP,
    E5_MAX_FRAC,
    E5_MIN_FRAC,
    SPAWN,
    SW_SPAWN_COUNT,
    LayoutGraph,
)

#: Rule E3/B1: slope ceiling (metres-per-metre) for buildable ground (tan 5°).
BUILDABLE_SLOPE = float(np.tan(np.radians(5.0)))

#: Rule B1: minimum contiguous buildable pocket area (m²) per base.
B1_MIN_POCKET_M2 = 4000.0

#: Rule B3: spawn spacing bounds (metres) within a cluster, corpus range.
B3_MIN_SPACING_M = 12.0
B3_MAX_SPACING_M = 70.0

#: Severity prefixes used in problem strings (mirror the other validators).
ERROR = "[error]"
WARNING = "[warning]"


def _cell_of(x: float, z: float) -> tuple[int, int]:
    """Grid cell ``(z, x)`` for a world coordinate in metres."""
    return round(z / GRID_M), round(x / GRID_M)


def _buildable_component_area(buildable: np.ndarray, start: tuple[int, int]) -> float:
    """Area (m²) of the 4-connected buildable component containing ``start``.

    Returns 0.0 when ``start`` is not buildable. O(cells) deque flood fill; the
    validators must run with only numpy (docs/05).
    """
    gz, gx = buildable.shape
    if not buildable[start]:
        return 0.0
    visited = np.zeros_like(buildable, dtype=bool)
    queue = deque([start])
    visited[start] = True
    count = 0
    while queue:
        z, x = queue.popleft()
        count += 1
        for dz, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nz, nx = z + dz, x + dx
            if (0 <= nz < gz and 0 <= nx < gx
                    and buildable[nz, nx] and not visited[nz, nx]):
                visited[nz, nx] = True
                queue.append((nz, nx))
    return count * GRID_M * GRID_M


class BalanceValidator:
    """Tier 2 balance validator for one heightmap + layout (+ optional spawns).

    ``heightmap`` may be a :class:`HeightMap` or a path to an ``.HG2`` file;
    ``layout`` is a :class:`~bzmap.model.layout.LayoutGraph`. ``spawns`` is an
    optional iterable of placed spawn objects (each with ``x``, ``z`` and
    ``team``) used for the B3 cluster-geometry check; when omitted, SPAWN nodes
    already present in the layout are used. :meth:`validate` returns a list of
    human-readable problem strings prefixed with ``[error]`` or ``[warning]``;
    an empty list means the map passes every E4/E5/B1/B2/B3 rule.
    :meth:`measure` returns the raw measured values.
    """

    def __init__(self, heightmap, layout: LayoutGraph, spawns=None):
        if isinstance(heightmap, HeightMap):
            self.heightmap = heightmap
        else:
            self.heightmap = read_hg2(heightmap)
        self.layout = layout
        if spawns is None:
            spawns = [
                n for n in layout.nodes.values() if n.kind == SPAWN
            ]
        self.spawns = list(spawns)

    # -- entry points ---------------------------------------------------------

    def measure(self) -> dict:
        """Return the raw measured values for this map.

        Records *measured values, not just verdicts* (docs/06 §Reporting) so the
        report task can retune thresholds against history.
        """
        buildable = buildable_mask(self.heightmap, BUILDABLE_SLOPE)

        # E4: per-base economy totals (geyser + scrap assigned to nearest base
        # by path distance).
        totals = {bid: 0 for bid in self.layout.base_ids}
        for nid in self.layout.economy_ids:
            nearest = self.layout.nearest_base(nid)
            if nearest is not None:
                totals[nearest[0]] += 1
        values = list(totals.values())
        mean = sum(values) / len(values) if values else 0.0
        e4_spread = (max(values) - min(values)) / mean if mean else 0.0

        # E5: contested geyser fraction.
        geysers = self.layout.geyser_ids
        contested = 0
        for gid in geysers:
            nearest = self.layout._nearest_bases(gid)
            if len(nearest) < 2:
                continue
            (_, d1), (_, d2) = nearest[0], nearest[1]
            if d1 > 0 and (d2 - d1) / d1 <= E5_GAP:
                contested += 1
        e5_frac = contested / len(geysers) if geysers else 0.0

        # B1: contiguous buildable pocket area at each base.
        pocket_areas = {}
        for bid in self.layout.base_ids:
            base = self.layout.nodes[bid]
            pocket_areas[bid] = _buildable_component_area(
                buildable, _cell_of(base.x, base.z)
            )

        # B2: nearest-base path distance as a fraction of the diagonal.
        base_ids = self.layout.base_ids
        nearest_dist = None
        for i, a in enumerate(base_ids):
            for b in base_ids[i + 1:]:
                d = self.layout.path_distance(a, b)
                if d is not None and (nearest_dist is None or d < nearest_dist):
                    nearest_dist = d
        diag = self.layout.diagonal_m()
        b2_frac = nearest_dist / diag if (nearest_dist and diag) else 0.0

        # B3: spawn count, cluster count, and within-cluster spacing.
        spawn_count = len(self.spawns)
        clusters: dict[int, list] = {}
        for s in self.spawns:
            clusters.setdefault(getattr(s, "team", -1), []).append(s)
        cluster_count = len([c for c in clusters.values() if c])
        nearest_gaps = []
        for members in clusters.values():
            if len(members) < 2:
                continue
            for i, a in enumerate(members):
                gap = min(
                    ((a.x - b.x) ** 2 + (a.z - b.z) ** 2) ** 0.5
                    for j, b in enumerate(members)
                    if j != i
                )
                nearest_gaps.append(gap)
        min_spacing = min(nearest_gaps) if nearest_gaps else 0.0
        max_spacing = max(nearest_gaps) if nearest_gaps else 0.0

        return {
            "per_base_economy": totals,
            "e4_spread": e4_spread,
            "e5_contested_frac": e5_frac,
            "base_pocket_m2": pocket_areas,
            "nearest_base_m": nearest_dist,
            "b2_separation_frac": b2_frac,
            "spawn_count": spawn_count,
            "spawn_cluster_count": cluster_count,
            "min_cluster_spacing_m": min_spacing,
            "max_cluster_spacing_m": max_spacing,
        }

    def validate(self) -> list[str]:
        """Run every E4/E5/B1/B2/B3 rule and return the list of problems."""
        m = self.measure()
        problems = []
        problems.extend(self._check_e4(m))
        problems.extend(self._check_e5(m))
        problems.extend(self._check_b1(m))
        problems.extend(self._check_b2(m))
        problems.extend(self._check_b3(m))
        return problems

    # -- rules ----------------------------------------------------------------

    def _check_e4(self, m: dict) -> list[str]:
        totals = m["per_base_economy"]
        if len(totals) < 2:
            return [
                f"{ERROR} E4: need at least two bases to compare per-base economy"
            ]
        if sum(totals.values()) == 0:
            return [
                f"{ERROR} E4: no economy nodes assigned to any base"
            ]
        spread = m["e4_spread"]
        if spread > E4_MAX_SPREAD:
            return [
                (
                    f"{ERROR} E4: per-base economy spread {spread:.1%} exceeds "
                    f"{E4_MAX_SPREAD:.0%}: {totals}"
                )
            ]
        return []

    def _check_e5(self, m: dict) -> list[str]:
        frac = m["e5_contested_frac"]
        if not (E5_MIN_FRAC <= frac <= E5_MAX_FRAC):
            return [
                (
                    f"{WARNING} E5: contested geysers {frac:.0%}; want "
                    f"{E5_MIN_FRAC:.0%}-{E5_MAX_FRAC:.0%}"
                )
            ]
        return []

    def _check_b1(self, m: dict) -> list[str]:
        problems = []
        for bid, area in m["base_pocket_m2"].items():
            if area < B1_MIN_POCKET_M2:
                problems.append(
                    f"{ERROR} B1: base {bid} buildable pocket only "
                    f"{area:.0f} m²; need at least {B1_MIN_POCKET_M2:.0f} m² "
                    f"under 5° slope"
                )
        return problems

    def _check_b2(self, m: dict) -> list[str]:
        frac = m["b2_separation_frac"]
        if not (B2_MIN_FRAC <= frac <= B2_MAX_FRAC):
            return [
                (
                    f"{WARNING} B2: nearest-base separation {frac:.2%} of "
                    f"diagonal; want {B2_MIN_FRAC:.0%}-{B2_MAX_FRAC:.0%}"
                )
            ]
        return []

    def _check_b3(self, m: dict) -> list[str]:
        problems = []
        count = m["spawn_count"]
        if count != SW_SPAWN_COUNT:
            problems.append(
                f"{ERROR} B3: deathmatch/_SW needs {SW_SPAWN_COUNT} spawns, "
                f"got {count}"
            )
        if m["spawn_cluster_count"] != self.layout.n_teams:
            problems.append(
                f"{ERROR} B3: spawns must form {self.layout.n_teams} team "
                f"clusters, got {m['spawn_cluster_count']}"
            )
        if m["min_cluster_spacing_m"] < B3_MIN_SPACING_M:
            problems.append(
                f"{ERROR} B3: spawns as close as "
                f"{m['min_cluster_spacing_m']:.0f} m; want at least "
                f"{B3_MIN_SPACING_M:.0f} m apart"
            )
        if m["max_cluster_spacing_m"] > B3_MAX_SPACING_M:
            problems.append(
                f"{ERROR} B3: spawns as far as "
                f"{m['max_cluster_spacing_m']:.0f} m; want at most "
                f"{B3_MAX_SPACING_M:.0f} m apart"
            )
        return problems


def validate_balance(heightmap, layout: LayoutGraph, spawns=None) -> list[str]:
    """Validate a heightmap+layout against rules E4-E5, B1-B3.

    Returns the problem list; an empty list means the map passes every rule.
    """
    return BalanceValidator(heightmap, layout, spawns=spawns).validate()