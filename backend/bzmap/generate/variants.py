"""Variant object sets from one layout (docs/05 ``generate/variants.py``).

The economy of the whole project is that **terrain is authored once and reused
across every variant** — only the object set changes (corpus conventions: "The variant
system"). This module turns the layout plus the economy/spawn results into the
four BZN object sets the game-mode scripts select by filename suffix:

- **base** (deathmatch, no suffix) — only the player and the 14-spawn _SW
  cluster set. No economy at all (corpus convention: ``uexmap10`` base carries 15 objects:
  1 player + 14 spawns).
- **_S** (strategy) — the full economy (geysers + scrap) plus one spawn per
  base (the real strategy player count) plus the player.
- **_ST** (strategy teams) — the full economy plus the full 14-spawn set plus
  the player. Optional in the corpus (present on 17 of 35 maps) but cheap to
  ship.
- **_SW** (wingman teams) — the full economy, the full 14-spawn set, the
  player, and a pre-placed repair depot (``abhang``) and supply depot
  (``absupp``) for each team (corpus convention: teams 1 and 8).

Every object carries a ground-snapped ``y`` (bilinear sample of the heightmap,
docs/02 §6 R3) and a per-class label ``<PrjID><index>_<role>`` (docs/02 §5).
The derivation is deterministic given the layout, heightmap, economy and spawn
results: the same inputs always produce the same object sets (docs/08
fixed-seed determinism).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from math import atan2, degrees

from bzmap.formats.hg2 import sample_m
from bzmap.generate.economy import EconomyResult
from bzmap.generate.spawns import SpawnResult
from bzmap.model.layout import LayoutGraph

#: Object classes the variants emit (corpus conventions, "Object classes").
PLAYER = "player"
SPAWN_POINT = "pspwn_1"
GEYSER_CLASS = "eggeizr1"
SCRAP_CLASSES = ("npscr1", "npscr2", "npscr3")
REPAIR_DEPOT = "abhang"
SUPPLY_DEPOT = "absupp"

#: Label role suffixes (docs/02 §5).
_ROLE_PLAYER = "wingman"
_ROLE_SPAWN = "spawnpnt"
_ROLE_GEYSER = "geyser"
_ROLE_SCRAP = "scrap"
_ROLE_REPAIR = "repairdepot"
_ROLE_SUPPLY = "supplydepot"

#: Team of the second wingman cluster / depot set (corpus convention: teams 1 and 8).
TEAM_TWO = 8

#: Offset (metres) of the team depots from their base site so they do not
#: overlap the spawn cluster.
DEPOT_OFFSET_M = 60.0


@dataclass(frozen=True)
class VariantObject:
    """One object in a variant set (a BZN ``[GameObject]`` in the making).

    ``y`` is the ground-snapped height in metres (docs/02 §6 R3). ``yaw`` is
    degrees about Y. ``team`` is 0 (neutral), 1 (team one) or 8 (team two).
    ``scrap_type`` is set only for the ``npscr1/2/3`` scrap classes.
    """

    prjid: str
    x: float
    z: float
    y: float
    yaw: float
    team: int
    label: str
    scrap_type: str | None = None


@dataclass
class VariantSet:
    """One named variant's object set, with typed accessors."""

    name: str
    objects: list[VariantObject] = field(default_factory=list)

    @property
    def player(self) -> list[VariantObject]:
        return [o for o in self.objects if o.prjid == PLAYER]

    @property
    def spawns(self) -> list[VariantObject]:
        return [o for o in self.objects if o.prjid == SPAWN_POINT]

    @property
    def geysers(self) -> list[VariantObject]:
        return [o for o in self.objects if o.prjid == GEYSER_CLASS]

    @property
    def scrap(self) -> list[VariantObject]:
        return [o for o in self.objects if o.prjid in SCRAP_CLASSES]

    @property
    def depots(self) -> list[VariantObject]:
        return [o for o in self.objects if o.prjid in (REPAIR_DEPOT, SUPPLY_DEPOT)]


@dataclass
class VariantsResult:
    """The four object sets derived from one layout."""

    base: VariantSet
    s: VariantSet
    st: VariantSet
    sw: VariantSet

    def variants(self) -> dict[str, VariantSet]:
        """Name -> set, keyed by the BZN filename suffix (``""`` for base)."""
        return {"": self.base, "_S": self.s, "_ST": self.st, "_SW": self.sw}


class VariantGenerator:
    """Derives the base/_S/_ST/_SW object sets from one layout.

    The generator is stateless apart from its tuning constants; call
    :meth:`generate` with a layout, heightmap, economy result and spawn results
    to get a :class:`VariantsResult`.
    """

    def __init__(self, depot_offset_m: float = DEPOT_OFFSET_M):
        self.depot_offset_m = float(depot_offset_m)

    def generate(
        self,
        layout: LayoutGraph,
        heightmap,
        economy: EconomyResult,
        spawns_sw: SpawnResult,
        spawns_s: SpawnResult,
    ) -> VariantsResult:
        """Build the four variant object sets.

        ``spawns_sw`` is the 14-spawn _SW/deathmatch set and ``spawns_s`` the
        one-per-base strategy set (both from :mod:`bzmap.generate.spawns`).
        ``economy`` is the geyser/scrap placement from
        :mod:`bzmap.generate.economy`.  ``heightmap`` is the final terrain used
        to ground-snap every object's ``y``.
        """
        player = self._player(layout, heightmap)
        economy_objs = self._economy(layout, heightmap, economy)
        sw_spawns = self._spawns(layout, heightmap, spawns_sw)
        s_spawns = self._spawns(layout, heightmap, spawns_s)

        return VariantsResult(
            base=VariantSet("base", [player, *sw_spawns]),
            s=VariantSet("_S", [player, *s_spawns, *economy_objs]),
            st=VariantSet("_ST", [player, *sw_spawns, *economy_objs]),
            sw=VariantSet(
                "_SW",
                [player, *sw_spawns, *economy_objs, *self._depots(layout, heightmap)],
            ),
        )

    # -- derivation -----------------------------------------------------------

    def _player(self, layout: LayoutGraph, heightmap) -> VariantObject:
        """Exactly one player object, team 1, at the first base site."""
        bid = layout.base_ids[0]
        base = layout.nodes[bid]
        x, z = base.x, base.z
        return VariantObject(
            prjid=PLAYER,
            x=x,
            z=z,
            y=sample_m(heightmap, x, z),
            yaw=self._facing(x, z, layout),
            team=1,
            label=f"{PLAYER}0_{_ROLE_PLAYER}",
        )

    def _spawns(
        self, layout: LayoutGraph, heightmap, result: SpawnResult
    ) -> list[VariantObject]:
        """Convert a spawn result into variant objects (ground-snapped)."""
        objs = []
        for i, s in enumerate(result.spawns):
            objs.append(
                VariantObject(
                    prjid=SPAWN_POINT,
                    x=s.x,
                    z=s.z,
                    y=sample_m(heightmap, s.x, s.z),
                    yaw=s.yaw,
                    team=s.team,
                    label=f"{SPAWN_POINT}{i}_{_ROLE_SPAWN}",
                )
            )
        return objs

    def _economy(
        self, layout: LayoutGraph, heightmap, result: EconomyResult
    ) -> list[VariantObject]:
        """Geysers and scrap pools, ground-snapped, in the layout's order."""
        objs = []
        for i, g in enumerate(result.geysers):
            objs.append(
                VariantObject(
                    prjid=GEYSER_CLASS,
                    x=g.x,
                    z=g.z,
                    y=sample_m(heightmap, g.x, g.z),
                    yaw=0.0,
                    team=g.team,
                    label=f"{GEYSER_CLASS}{i}_{_ROLE_GEYSER}",
                )
            )
        for i, s in enumerate(result.scrap):
            objs.append(
                VariantObject(
                    prjid=s.scrap_type or SCRAP_CLASSES[0],
                    x=s.x,
                    z=s.z,
                    y=sample_m(heightmap, s.x, s.z),
                    yaw=0.0,
                    team=s.team,
                    label=f"{s.scrap_type or SCRAP_CLASSES[0]}{i}_{_ROLE_SCRAP}",
                    scrap_type=s.scrap_type,
                )
            )
        return objs

    def _depots(self, layout: LayoutGraph, heightmap) -> list[VariantObject]:
        """_SW-only repair/supply depots, one pair per team (teams 1 and 8).

        Each base gets a repair depot (``abhang``) and a supply depot
        (``absupp``), offset from the base site so they do not collide with the
        spawn cluster (corpus convention: ``uexmap10`` ships 2 abhang + 2 absupp on
        teams 1 and 8).
        """
        teams = [1, TEAM_TWO] if layout.n_teams >= 2 else [1]
        objs = []
        for ti, bid in enumerate(layout.base_ids):
            team = teams[ti % len(teams)]
            base = layout.nodes[bid]
            # The two depots must NOT share a point: both previously landed at
            # base + (offset, offset), leaving two solid buildings
            # interpenetrating — a pathological collision-churn class (two
            # solids at one point never come to
            # rest and re-send reliable state every frame). Split them to
            # opposite sides of the base site: separation = 2 * depot_offset_m.
            for cls, role, side in (
                (REPAIR_DEPOT, _ROLE_REPAIR, 1.0),
                (SUPPLY_DEPOT, _ROLE_SUPPLY, -1.0),
            ):
                x = base.x + side * self.depot_offset_m
                z = base.z + self.depot_offset_m
                objs.append(
                    VariantObject(
                        prjid=cls,
                        x=x,
                        z=z,
                        y=sample_m(heightmap, x, z),
                        yaw=self._facing(x, z, layout),
                        team=team,
                        label=f"{cls}{ti}_{role}",
                    )
                )
        return objs

    # -- helpers --------------------------------------------------------------

    def _facing(self, x: float, z: float, layout: LayoutGraph) -> float:
        """Yaw (degrees) from ``(x, z)`` toward the map centre."""
        cx = layout.width_m / 2.0
        cz = layout.depth_m / 2.0
        return degrees(atan2(cx - x, cz - z))


def generate_variants(
    layout: LayoutGraph,
    heightmap,
    economy: EconomyResult,
    spawns_sw: SpawnResult,
    spawns_s: SpawnResult,
    seed: int | None = None,
) -> VariantsResult:
    """Convenience wrapper producing the four variant object sets.

    ``seed`` is accepted for API symmetry with the other generators; derivation
    is fully deterministic from the layout, heightmap, economy and spawn
    results, so the same inputs always yield the same sets regardless of seed.
    """
    return VariantGenerator().generate(layout, heightmap, economy, spawns_sw, spawns_s)