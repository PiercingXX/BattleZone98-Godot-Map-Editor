"""Layout graph for a generated map (docs/05 ``model/layout.py``).

The layout is the *first* thing built (docs/04 §7 step 1): base sites,
economy nodes (geysers, scrap pools) and the routes that will become
terrain corridors.  The graph is validated **before** terrain synthesis,
because rejecting a bad layout costs milliseconds while rejecting it after
erosion costs seconds (docs/05 "validate the layout graph before
generating terrain").

This module owns the graph-level rules from docs/04 that do not need a
heightmap:

- **C1** — every node reachable from every base over the route graph.
- **C3** — at least two topologically distinct routes between any two bases.
- **B2** — path distance between the nearest bases is 35–60% of the map
  diagonal.
- **E4** — per-base economy (geysers + scrap assigned to their nearest base
  by path distance) within 5% across bases.
- **E5** — 30–50% of geysers are contested (roughly equidistant from two or
  more bases).
- **B3** — deathmatch/_SW spawn set is 14 spawns in ``n_teams`` clusters;
  _S is one spawn per base (checked when spawn nodes are present).

Terrain-dependent rules (B1, B4, C2, C4, T1–T4, E3) belong to the
``validate/`` layer, not here.
"""

from __future__ import annotations

import heapq
from dataclasses import dataclass, field
from math import hypot

#: Node kinds the layout graph understands.
BASE = "base"
GEYSER = "geyser"
SCRAP = "scrap"
SPAWN = "spawn"
#: A route waypoint: structural, carries no economy value.
WAYPOINT = "waypoint"

#: Rule B2: nearest-base separation as a fraction of the map diagonal.
B2_MIN_FRAC = 0.35
B2_MAX_FRAC = 0.60

#: Rule E4: maximum allowed per-base economy spread (fraction of the mean).
E4_MAX_SPREAD = 0.05

#: Rule E5: contested geysers must be this fraction of all geysers.
E5_MIN_FRAC = 0.30
E5_MAX_FRAC = 0.50

#: Rule E5: a geyser is contested when its two nearest bases are within this
#: relative path-distance gap.
E5_GAP = 0.15

#: Rule B3: deathmatch/_SW spawn count.
SW_SPAWN_COUNT = 14


@dataclass(frozen=True)
class Node:
    """A single node in the layout graph.

    ``x``/``z`` are world coordinates in metres.  ``kind`` is one of
    :data:`BASE`, :data:`GEYSER`, :data:`SCRAP`, :data:`SPAWN`.  ``team``
    is only meaningful for base and spawn nodes.
    """

    id: str
    x: float
    z: float
    kind: str
    team: int = -1


@dataclass
class RuleResult:
    """Outcome of one graph-level validation rule."""

    name: str
    passed: bool
    measured: float | None = None
    message: str = ""

    def __bool__(self) -> bool:
        return self.passed


@dataclass
class LayoutReport:
    """Aggregate result of :meth:`LayoutGraph.validate`."""

    rules: list[RuleResult] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        """True when every error-severity rule passes."""
        return all(r.passed for r in self.rules)

    def by_name(self, name: str) -> RuleResult | None:
        for r in self.rules:
            if r.name == name:
                return r
        return None


class LayoutGraph:
    """Base sites, economy nodes, and the routes connecting them.

    Nodes are keyed by id; routes are undirected edges with a path length
    in metres.  When a route is added without an explicit length the
    straight-line distance is used, but callers may supply a longer
    *path* distance (the graph models routes that will become terrain
    corridors, whose ground path is usually longer than the chord).
    """

    def __init__(self, width_m: float, depth_m: float, n_teams: int = 2):
        self.width_m = float(width_m)
        self.depth_m = float(depth_m)
        self.n_teams = int(n_teams)
        self._nodes: dict[str, Node] = {}
        self._edges: dict[tuple[str, str], float] = {}

    # -- construction ------------------------------------------------------

    def add_node(
        self,
        id: str,
        x: float,
        z: float,
        kind: str,
        team: int = -1,
    ) -> Node:
        """Add a node, replacing any existing node with the same id."""
        node = Node(id=id, x=float(x), z=float(z), kind=kind, team=team)
        self._nodes[id] = node
        return node

    def add_route(self, a: str, b: str, length: float | None = None) -> float:
        """Add an undirected route between two existing nodes.

        ``length`` is the path length in metres; when omitted the
        straight-line distance is used.  Returns the stored length.
        """
        if a not in self._nodes or b not in self._nodes:
            raise KeyError(f"route references unknown node: {a!r} or {b!r}")
        if length is None:
            na, nb = self._nodes[a], self._nodes[b]
            length = hypot(na.x - nb.x, na.z - nb.z)
        edge = tuple(sorted((a, b)))
        self._edges[edge] = float(length)
        return float(length)

    # -- accessors ---------------------------------------------------------

    @property
    def nodes(self) -> dict[str, Node]:
        return dict(self._nodes)

    @property
    def base_ids(self) -> list[str]:
        return [n.id for n in self._nodes.values() if n.kind == BASE]

    @property
    def economy_ids(self) -> list[str]:
        return [n.id for n in self._nodes.values() if n.kind in (GEYSER, SCRAP)]

    @property
    def waypoint_ids(self) -> list[str]:
        return [n.id for n in self._nodes.values() if n.kind == WAYPOINT]

    @property
    def geyser_ids(self) -> list[str]:
        return [n.id for n in self._nodes.values() if n.kind == GEYSER]

    def diagonal_m(self) -> float:
        """Length of the map diagonal in metres."""
        return hypot(self.width_m, self.depth_m)

    def neighbours(self, node: str) -> list[tuple[str, float]]:
        """(neighbour id, edge length) pairs for ``node``."""
        out = []
        for (a, b), length in self._edges.items():
            if a == node:
                out.append((b, length))
            elif b == node:
                out.append((a, length))
        return out

    def path_distance(self, start: str, goal: str) -> float | None:
        """Shortest path length (Dijkstra) from ``start`` to ``goal``.

        Returns ``None`` when no route connects them.
        """
        if start not in self._nodes or goal not in self._nodes:
            raise KeyError("path endpoints must be existing nodes")
        if start == goal:
            return 0.0
        dist: dict[str, float] = {start: 0.0}
        heap: list[tuple[float, str]] = [(0.0, start)]
        while heap:
            d, cur = heapq.heappop(heap)
            if cur == goal:
                return d
            if d > dist.get(cur, float("inf")):
                continue
            for nxt, length in self.neighbours(cur):
                nd = d + length
                if nd < dist.get(nxt, float("inf")):
                    dist[nxt] = nd
                    heapq.heappush(heap, (nd, nxt))
        return None

    def shortest_path(self, start: str, goal: str) -> list[str] | None:
        """Ordered node list on the shortest route, or ``None`` if none."""
        if start not in self._nodes or goal not in self._nodes:
            raise KeyError("path endpoints must be existing nodes")
        if start == goal:
            return [start]
        prev: dict[str, str] = {}
        dist: dict[str, float] = {start: 0.0}
        heap: list[tuple[float, str]] = [(0.0, start)]
        while heap:
            d, cur = heapq.heappop(heap)
            if cur == goal:
                break
            if d > dist.get(cur, float("inf")):
                continue
            for nxt, length in self.neighbours(cur):
                nd = d + length
                if nd < dist.get(nxt, float("inf")):
                    dist[nxt] = nd
                    prev[nxt] = cur
                    heapq.heappush(heap, (nd, nxt))
        if goal not in dist:
            return None
        path = [goal]
        while path[-1] != start:
            path.append(prev[path[-1]])
        path.reverse()
        return path

    def nearest_base(self, node_id: str) -> tuple[str, float] | None:
        """Id and path distance of the nearest base to ``node_id``."""
        dists = [
            (bid, d)
            for bid in self.base_ids
            if (d := self.path_distance(node_id, bid)) is not None
        ]
        if not dists:
            return None
        return min(dists, key=lambda t: t[1])

    def _nearest_bases(self, node_id: str) -> list[tuple[str, float]]:
        """All bases sorted by path distance (reachable ones only)."""
        dists = [
            (bid, d)
            for bid in self.base_ids
            if (d := self.path_distance(node_id, bid)) is not None
        ]
        return sorted(dists, key=lambda t: t[1])

    # -- graph-level validation --------------------------------------------

    def validate(self) -> LayoutReport:
        """Run every graph-level rule; reject before terrain synthesis.

        Returns a :class:`LayoutReport`; ``report.ok`` is False when any
        error-severity rule fails.  Rules that need a heightmap (B1, B4,
        C2, C4, T*, E3) are deliberately not evaluated here.
        """
        report = LayoutReport()
        report.rules.append(self._check_connectivity())
        report.rules.append(self._check_multiple_routes())
        report.rules.append(self._check_base_separation())
        report.rules.append(self._check_economy_balance())
        report.rules.append(self._check_contested_geysers())
        report.rules.append(self._check_spawns())
        return report

    # -- individual rules --------------------------------------------------

    def _check_connectivity(self) -> RuleResult:
        """Rule C1: every node reachable from every base over the graph."""
        if not self.base_ids:
            return RuleResult("C1", False, message="no base sites in layout")
        unreachable: set[str] = set()
        for node_id in self._nodes:
            for bid in self.base_ids:
                if self.path_distance(bid, node_id) is None:
                    unreachable.add(node_id)
                    break
        if unreachable:
            return RuleResult(
                "C1",
                False,
                measured=len(unreachable),
                message=f"unreachable nodes from every base: {sorted(unreachable)}",
            )
        return RuleResult("C1", True, measured=0, message="all nodes reachable")

    def _check_multiple_routes(self) -> RuleResult:
        """Rule C3: ≥2 topologically distinct routes between every base pair.

        Computes the shortest path, removes its edges, and re-runs the
        search; a surviving second path means the pair is not a
        single-corridor choke.
        """
        bases = self.base_ids
        if len(bases) < 2:
            return RuleResult(
                "C3", False, message="need at least two bases for C3"
            )
        for i, a in enumerate(bases):
            for b in bases[i + 1 :]:
                first = self.shortest_path(a, b)
                if first is None:
                    return RuleResult(
                        "C3", False, message=f"no route between bases {a} and {b}"
                    )
                # Remove the edges of the first path, then look for another.
                removed = self._remove_path_edges(first)
                try:
                    second = self.shortest_path(a, b)
                    if second is None:
                        return RuleResult(
                            "C3",
                            False,
                            message=f"single corridor between bases {a} and {b}",
                        )
                finally:
                    self._restore_edges(removed)
        return RuleResult("C3", True, message="≥2 routes between every base pair")

    def _check_base_separation(self) -> RuleResult:
        """Rule B2: nearest-base path distance is 35–60% of the diagonal."""
        bases = self.base_ids
        if len(bases) < 2:
            return RuleResult(
                "B2", False, message="need at least two bases for B2"
            )
        nearest = min(
            d
            for i, a in enumerate(bases)
            for b in bases[i + 1 :]
            if (d := self.path_distance(a, b)) is not None
        )
        diag = self.diagonal_m()
        frac = nearest / diag if diag else 0.0
        if not (B2_MIN_FRAC <= frac <= B2_MAX_FRAC):
            return RuleResult(
                "B2",
                False,
                measured=frac,
                message=(
                    f"nearest-base separation {nearest:.0f} m = {frac:.2%} of "
                    f"diagonal; want {B2_MIN_FRAC:.0%}–{B2_MAX_FRAC:.0%}"
                ),
            )
        return RuleResult("B2", True, measured=frac, message="separation in range")

    def _check_economy_balance(self) -> RuleResult:
        """Rule E4: per-base economy within 5% of the mean across bases."""
        totals = self._per_base_economy()
        if len(totals) < 2:
            return RuleResult(
                "E4", False, message="need at least two bases for E4"
            )
        values = list(totals.values())
        mean = sum(values) / len(values)
        if mean == 0:
            return RuleResult(
                "E4", False, message="no economy nodes assigned to any base"
            )
        spread = (max(values) - min(values)) / mean
        if spread > E4_MAX_SPREAD:
            return RuleResult(
                "E4",
                False,
                measured=spread,
                message=(
                    f"per-base economy spread {spread:.1%} exceeds "
                    f"{E4_MAX_SPREAD:.0%}: {totals}"
                ),
            )
        return RuleResult("E4", True, measured=spread, message="economy balanced")

    def _check_contested_geysers(self) -> RuleResult:
        """Rule E5: 30–50% of geysers are contested (near two+ bases)."""
        geysers = self.geyser_ids
        if not geysers:
            return RuleResult(
                "E5", False, message="no geysers in layout for E5"
            )
        if len(self.base_ids) < 2:
            return RuleResult(
                "E5", False, message="need at least two bases for E5"
            )
        contested = 0
        for gid in geysers:
            nearest = self._nearest_bases(gid)
            if len(nearest) < 2:
                continue
            (_, d1), (_, d2) = nearest[0], nearest[1]
            if d1 > 0 and (d2 - d1) / d1 <= E5_GAP:
                contested += 1
        frac = contested / len(geysers)
        if not (E5_MIN_FRAC <= frac <= E5_MAX_FRAC):
            return RuleResult(
                "E5",
                False,
                measured=frac,
                message=(
                    f"contested geysers {frac:.0%} ({contested}/{len(geysers)}); "
                    f"want {E5_MIN_FRAC:.0%}–{E5_MAX_FRAC:.0%}"
                ),
            )
        return RuleResult("E5", True, measured=frac, message="contested share ok")

    def _check_spawns(self) -> RuleResult:
        """Rule B3: 14 spawns in n_teams clusters; _S one spawn per base.

        Only evaluated when spawn nodes are present; a layout with no
        spawns yet (spawns are placed by a later generator) is skipped.
        """
        spawns = [n for n in self._nodes.values() if n.kind == SPAWN]
        if not spawns:
            return RuleResult("B3", True, message="no spawns yet (skipped)")
        if len(spawns) != SW_SPAWN_COUNT:
            return RuleResult(
                "B3",
                False,
                measured=len(spawns),
                message=(
                    f"deathmatch/_SW needs {SW_SPAWN_COUNT} spawns, "
                    f"got {len(spawns)}"
                ),
            )
        clusters = {n.team for n in spawns if n.team >= 0}
        if len(clusters) != self.n_teams:
            return RuleResult(
                "B3",
                False,
                measured=len(clusters),
                message=(
                    f"spawns must form {self.n_teams} team clusters, "
                    f"got {len(clusters)}"
                ),
            )
        return RuleResult("B3", True, message="spawn count and clusters ok")

    # -- helpers -----------------------------------------------------------

    def _per_base_economy(self) -> dict[str, int]:
        """Map base id -> count of economy nodes assigned to it (nearest by path)."""
        totals = {bid: 0 for bid in self.base_ids}
        for nid in self.economy_ids:
            nearest = self.nearest_base(nid)
            if nearest is not None:
                totals[nearest[0]] += 1
        return totals

    def _remove_path_edges(self, path: list[str]) -> list[tuple[tuple[str, str], float]]:
        """Remove the edges along ``path``; return them for restoration."""
        removed = []
        for a, b in zip(path, path[1:]):
            edge = tuple(sorted((a, b)))
            if edge in self._edges:
                removed.append((edge, self._edges.pop(edge)))
        return removed

    def _restore_edges(self, removed: list[tuple[tuple[str, str], float]]) -> None:
        for edge, length in removed:
            self._edges[edge] = length