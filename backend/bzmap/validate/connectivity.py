"""Tier 2 connectivity validation — rules C1-C4 (docs/06, docs/04 §4).

The hard failure conditions. These are pass/fail, not tuning: a map that
fails any of them is broken however pretty it looks. All four run over the
5 m heightmap grid (docs/04 §4):

- **C1** (error) — every base, geyser and scrap pool is reachable from every
  base by a ground path over terrain with slope ≤ 30°. Any unreachable
  economy object is a hard error.
- **C2** (warning — RECALIBRATED 2026-08-11) — disconnected traversable
  pockets above the corpus p99 (~5,000 m²) are flagged for review. The first
  full corpus calibration run failed all 36 stock maps under the original
  200 m² *error*: hand-made maps carry thousands of small pockets (max
  7.7 km² on Canyon Madness, whose shelves ARE the map). Anything that
  matters being unreachable is C1's error already.
- **C3** (error) — at least **2 topologically distinct** routes between any
  pair of bases. Verify by computing a shortest path, deleting a 30 m-wide
  corridor around it, and re-running the search — a second path must still
  exist.
- **C4** (warning) — no corridor on a main route narrower than **30 m**.
  Battlezone vehicles have real turning radii; narrower than this and
  pathfinding jams [INFERRED — see docs/09].

The traversable mask is slope ≤ 30° over the 5 m grid. Components are found
with a deque flood fill and routes with A*, both using only numpy (the
validators must run without scipy — docs/05).
"""

from __future__ import annotations

from collections import deque

import numpy as np

from bzmap.formats.hg2 import GRID_M, HeightMap, read_hg2, slope
from bzmap.model.layout import BASE, GEYSER, SCRAP, LayoutGraph

#: 30° slope in metres-per-metre (tan 30°). Rule C1/C2 traversable threshold.
SLOPE_30_DEG = float(np.tan(np.radians(30.0)))

#: Rule C2 — a disconnected traversable pocket larger than this (m²) is a trap.
#: Retained for the measured values; the check itself warns at C2_WARN_AREA_M2.
C2_MAX_TRAP_AREA_M2 = 200.0

#: C2 warning threshold — the corpus p99 pocket size (measured 2026-08-11
#: across 39,942 pockets in the 36 stock maps). Below this, pockets are normal
#: terrain texture on rugged worlds.
C2_WARN_AREA_M2 = 5000.0

#: Rule C3 — corridor width (m) deleted around the shortest path before re-search.
C3_CORRIDOR_WIDTH_M = 30.0

#: Rule C4 — a main-route corridor narrower than this (m) is a warning.
C4_MIN_WIDTH_M = 30.0

#: Severity prefixes used in problem strings (mirror validate/terrain.py).
ERROR = "[error]"
WARNING = "[warning]"

#: Node kinds that must be reachable from every base (Rule C1).
_REACHABLE_KINDS = frozenset({BASE, GEYSER, SCRAP})


def _cell_of(x: float, z: float) -> tuple[int, int]:
    """Grid cell ``(z, x)`` for a world coordinate in metres."""
    return round(z / GRID_M), round(x / GRID_M)


def _in_grid(arr: np.ndarray, cell: tuple[int, int]) -> bool:
    """True when ``cell`` lies inside ``arr``'s bounds."""
    iz, ix = cell
    return 0 <= iz < arr.shape[0] and 0 <= ix < arr.shape[1]


def _label_at(labels: np.ndarray, cell: tuple[int, int]) -> int:
    """Component label at ``cell``, or 0 (untraversable) when off-grid.

    Off-grid nodes are real: stock campaign-derived maps carry world
    coordinates offset by the ``.trn`` ``[Size]`` ``MinX``/``MinZ`` (e.g.
    ``MinZ=98560``), and a caller that forgets to normalize used to crash this
    validator with an IndexError instead of getting a legible verdict. An
    off-grid node is simply not on traversable ground.
    """
    iz, ix = cell
    if 0 <= iz < labels.shape[0] and 0 <= ix < labels.shape[1]:
        return int(labels[iz, ix])
    return 0


def _traversable_mask(heightmap: HeightMap) -> np.ndarray:
    """Boolean mask of cells with slope ≤ 30° (Rule C1/C2 traversable ground)."""
    return slope(heightmap) <= SLOPE_30_DEG


def _components(mask: np.ndarray) -> np.ndarray:
    """Label 4-connected components of ``mask``; returns an int label array.

    Cells outside the mask are labelled 0. Labels start at 1. O(cells) deque
    flood fill; the validators must run with only numpy (docs/05).
    """
    gz, gx = mask.shape
    labels = np.zeros((gz, gx), dtype=np.int32)
    label = 0
    for start in zip(*np.nonzero(mask)):
        if labels[start] != 0:
            continue
        label += 1
        queue = deque([start])
        labels[start] = label
        while queue:
            z, x = queue.popleft()
            for dz, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nz, nx = z + dz, x + dx
                if (0 <= nz < gz and 0 <= nx < gx
                        and mask[nz, nx] and labels[nz, nx] == 0):
                    labels[nz, nx] = label
                    queue.append((nz, nx))
    return labels


def _astar(mask: np.ndarray, start: tuple[int, int],
           goal: tuple[int, int]) -> list[tuple[int, int]] | None:
    """Shortest 4-connected path over ``mask`` from ``start`` to ``goal``.

    Returns the ordered cell list, or ``None`` when no path exists. A* with
    Manhattan heuristic over the uniform-cost 5 m grid.
    """
    import heapq

    gz, gx = mask.shape
    if not mask[start] or not mask[goal]:
        return None
    if start == goal:
        return [start]
    open_heap: list[tuple[int, int, tuple[int, int]]] = []
    g_score: dict[tuple[int, int], int] = {start: 0}
    prev: dict[tuple[int, int], tuple[int, int]] = {}
    heapq.heappush(open_heap, (0, 0, start))
    # Tie-break counter so equal f-scores do not compare equal tuples.
    counter = 1
    while open_heap:
        _, _, cur = heapq.heappop(open_heap)
        if cur == goal:
            break
        z, x = cur
        for dz, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nz, nx = z + dz, x + dx
            if not (0 <= nz < gz and 0 <= nx < gx and mask[nz, nx]):
                continue
            nxt = (nz, nx)
            tentative = g_score[cur] + 1
            if tentative < g_score.get(nxt, float("inf")):
                g_score[nxt] = tentative
                prev[nxt] = cur
                f = tentative + abs(nxt[0] - goal[0]) + abs(nxt[1] - goal[1])
                heapq.heappush(open_heap, (f, counter, nxt))
                counter += 1
    if goal not in g_score:
        return None
    path = [goal]
    while path[-1] != start:
        path.append(prev[path[-1]])
    path.reverse()
    return path


def _dilate(path: list[tuple[int, int]], radius_cells: int,
            shape: tuple[int, int]) -> set[tuple[int, int]]:
    """Cells within ``radius_cells`` (Chebyshev) of any path cell."""
    gz, gx = shape
    out: set[tuple[int, int]] = set()
    for z, x in path:
        for dz in range(-radius_cells, radius_cells + 1):
            for dx in range(-radius_cells, radius_cells + 1):
                nz, nx = z + dz, x + dx
                if 0 <= nz < gz and 0 <= nx < gx:
                    out.add((nz, nx))
    return out


def _distance_to_wall(mask: np.ndarray) -> np.ndarray:
    """Distance (cells) from each cell to the nearest non-traversable cell.

    Multi-source BFS seeded from every impassable cell; impassable cells are
    distance 0. Used to measure corridor width (Rule C4).
    """
    gz, gx = mask.shape
    dist = np.full((gz, gx), -1, dtype=np.int32)
    queue = deque()
    for z, x in zip(*np.nonzero(~mask)):
        dist[z, x] = 0
        queue.append((z, x))
    while queue:
        z, x = queue.popleft()
        for dz, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nz, nx = z + dz, x + dx
            if (0 <= nz < gz and 0 <= nx < gx and dist[nz, nx] < 0):
                dist[nz, nx] = dist[z, x] + 1
                queue.append((nz, nx))
    return dist


class ConnectivityValidator:
    """Tier 2 connectivity validator for one heightmap + layout.

    ``heightmap`` may be a :class:`HeightMap` or a path to an ``.HG2`` file;
    ``layout`` is a :class:`~bzmap.model.layout.LayoutGraph`. :meth:`validate`
    returns a list of human-readable problem strings prefixed with ``[error]``
    or ``[warning]``; an empty list means the map passes every C-rule.
    :meth:`measure` returns the raw measured values.
    """

    def __init__(self, heightmap, layout: LayoutGraph):
        if isinstance(heightmap, HeightMap):
            self.heightmap = heightmap
        else:
            self.heightmap = read_hg2(heightmap)
        self.layout = layout

    # -- entry points ---------------------------------------------------------

    def measure(self) -> dict:
        """Return the raw measured values for this map.

        Records *measured values, not just verdicts* (docs/06 §Reporting) so
        the report task can retune thresholds against history.
        """
        mask = _traversable_mask(self.heightmap)
        labels = _components(mask)
        base_cells = {
            n.id: _cell_of(n.x, n.z)
            for n in self.layout.nodes.values()
            if n.kind == BASE
        }
        base_labels = {_label_at(labels, c) for c in base_cells.values()}
        base_labels.discard(0)

        # C1: every base/geyser/scrap node reachable from *every* base. A node
        # is reachable from every base only when its component is the single
        # component that all bases share.
        unreachable = []
        if not base_labels:
            # No base sits on traversable ground — nothing is reachable.
            for n in self.layout.nodes.values():
                if n.kind in _REACHABLE_KINDS:
                    unreachable.append(n.id)
        elif len(base_labels) > 1:
            # Bases are not mutually connected, so no node is reachable from
            # every base.
            for n in self.layout.nodes.values():
                if n.kind in _REACHABLE_KINDS:
                    unreachable.append(n.id)
        else:
            reachable_label = next(iter(base_labels))
            for n in self.layout.nodes.values():
                if n.kind not in _REACHABLE_KINDS:
                    continue
                if _label_at(labels, _cell_of(n.x, n.z)) != reachable_label:
                    unreachable.append(n.id)

        # C2: traversable components disconnected from every base, area > limit.
        trap_areas = []
        for label in range(1, labels.max() + 1):
            if label in base_labels:
                continue
            area_cells = int((labels == label).sum())
            area_m2 = area_cells * GRID_M * GRID_M
            if area_m2 > C2_MAX_TRAP_AREA_M2:
                trap_areas.append(area_m2)

        # C3/C4: per base-pair shortest-path analysis.
        single_corridor = []
        min_width_m = float("inf")
        base_ids = self.layout.base_ids
        for i, a in enumerate(base_ids):
            for b in base_ids[i + 1:]:
                start = _cell_of(self.layout.nodes[a].x, self.layout.nodes[a].z)
                goal = _cell_of(self.layout.nodes[b].x, self.layout.nodes[b].z)
                if not _in_grid(labels, start) or not _in_grid(labels, goal):
                    # An off-grid base cannot be pathed to; report it as a
                    # missing corridor rather than crashing the search.
                    single_corridor.append((a, b))
                    continue
                path = _astar(mask, start, goal)
                if path is None:
                    single_corridor.append((a, b))
                    continue
                # C3: delete a 30 m-wide corridor around the path, re-search.
                radius = round(C3_CORRIDOR_WIDTH_M / 2.0 / GRID_M)
                removed = _dilate(path, radius, mask.shape)
                blocked = mask.copy()
                for cell in removed:
                    blocked[cell] = False
                # Keep a buffer around the endpoints open so the search can
                # leave them and route around the removed corridor.
                for cell in _dilate([start], radius, mask.shape):
                    blocked[cell] = True
                for cell in _dilate([goal], radius, mask.shape):
                    blocked[cell] = True
                if _astar(blocked, start, goal) is None:
                    single_corridor.append((a, b))
                # C4: measure the corridor width along this main route.
                dist = _distance_to_wall(mask)
                for cell in path:
                    d = dist[cell]
                    if d < 0:
                        # No impassable cell anywhere (e.g. a fully flat map):
                        # the corridor is effectively unbounded.
                        continue
                    w = max(0, d - 1) * 2 * GRID_M
                    min_width_m = min(min_width_m, w)

        return {
            "traversable_pct": float(mask.mean()) * 100.0,
            "unreachable_economy": sorted(unreachable),
            "trap_areas_m2": sorted(trap_areas),
            "single_corridor_pairs": single_corridor,
            "min_corridor_width_m": None if min_width_m == float("inf")
            else min_width_m,
        }

    def validate(self) -> list[str]:
        """Run every C-rule and return the list of problems."""
        m = self.measure()
        problems = []
        problems.extend(self._check_c1(m))
        problems.extend(self._check_c2(m))
        problems.extend(self._check_c3(m))
        problems.extend(self._check_c4(m))
        return problems

    # -- rules ----------------------------------------------------------------

    def _check_c1(self, m: dict) -> list[str]:
        if m["unreachable_economy"]:
            return [
                (
                    f"{ERROR} C1: economy nodes unreachable from every base by "
                    f"a ≤30° ground path: {m['unreachable_economy']}"
                )
            ]
        return []

    def _check_c2(self, m: dict) -> list[str]:
        # RECALIBRATED 2026-08-11 (docs/06 calibration test): C2 was an error,
        # and the first full run against the stock corpus — unblocked by the
        # off-grid crash fix — failed all 36 maps on it. Stock maps carry
        # thousands of disconnected traversable pockets (corpus p50 25 m²,
        # p99 ~5,000 m², max 7.7 km² on Canyon Madness, whose canyon shelves
        # ARE the map). Free-standing pockets are corpus-normal terrain
        # texture; anything that matters being unreachable (bases, economy)
        # is exactly what C1 already errors on. C2 is therefore a WARNING,
        # and only for pockets big enough to matter (> p99 of the corpus).
        big = [a for a in m["trap_areas_m2"] if a > C2_WARN_AREA_M2]
        if big:
            return [
                (
                    f"{WARNING} C2: {len(big)} disconnected traversable "
                    f"pocket(s) > {C2_WARN_AREA_M2:.0f} m² (largest "
                    f"{max(big):.0f} m²) — corpus-normal on rugged worlds, "
                    "review that no intended play space is cut off"
                )
            ]
        return []

    def _check_c3(self, m: dict) -> list[str]:
        if m["single_corridor_pairs"]:
            return [
                (
                    f"{ERROR} C3: single corridor between base pair(s) "
                    f"{m['single_corridor_pairs']} (no second route after "
                    f"removing a {C3_CORRIDOR_WIDTH_M:.0f} m-wide corridor)"
                )
            ]
        return []

    def _check_c4(self, m: dict) -> list[str]:
        w = m["min_corridor_width_m"]
        if w is not None and w < C4_MIN_WIDTH_M:
            return [
                (
                    f"{WARNING} C4: main-route corridor as narrow as "
                    f"{w:.0f} m; want at least {C4_MIN_WIDTH_M:.0f} m"
                )
            ]
        return []


def validate_connectivity(heightmap, layout: LayoutGraph) -> list[str]:
    """Validate a heightmap+layout against rules C1-C4; return the problem list."""
    return ConnectivityValidator(heightmap, layout).validate()