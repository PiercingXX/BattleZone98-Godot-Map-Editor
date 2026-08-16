"""Per-candidate validation report — one JSON + one PNG (docs/06 §Reporting).

For every candidate map the pipeline writes a directory under
``build/candidates/<seed>/`` containing ``report.json`` and ``preview.png``
plus the generated files in ``map/``. The report must record **measured
values, not just verdicts** (docs/06 §Reporting) — ``"flat_pct": 22.4`` not
``"T1": "pass"`` — so that when a rule needs retuning later the measurements
let you retune against history instead of guessing.

This module collects the measured values from every validator:

- :mod:`bzmap.validate.formats` — Tier 1 structural checks (round-trip,
  invariants, cross-file consistency, ground snapping). These are pure file
  checks over the candidate directory, so the caller passes the problem list
  in; this module does not re-read files it does not need.
- :mod:`bzmap.validate.terrain` — rules T1-T4 over the heightmap.
- :mod:`bzmap.validate.connectivity` — rules C1-C4 over heightmap + layout.
- :mod:`bzmap.validate.balance` — rules E4-E5, B1-B3 over heightmap + layout
  (+ optional spawns).

The JSON is deterministic (stable key order, ``sort_keys=True``) so a fixed
seed reproduces byte-identical reports (docs/08 fixed-seed determinism). The
PNG is the top-down shaded terrain with the layout's economy/spawn nodes and
routes overlaid, produced by :mod:`bzmap.render.preview`.
"""

from __future__ import annotations

import json
from pathlib import Path

from bzmap.formats.hg2 import HeightMap, read_hg2
from bzmap.model.layout import BASE, GEYSER, SCRAP, SPAWN, LayoutGraph
from bzmap.render.preview import render_preview
from bzmap.validate.balance import BalanceValidator
from bzmap.validate.connectivity import ConnectivityValidator
from bzmap.validate.terrain import TerrainValidator

#: Default preview pixel size (docs/06 §Reporting preview.png).
DEFAULT_PREVIEW_SIZE = (512, 512)


def _severity(problem: str) -> str:
    """Classify a problem string by its ``[error]``/``[warning]`` prefix."""
    if problem.startswith("[error]"):
        return "error"
    if problem.startswith("[warning]"):
        return "warning"
    return "info"


class CandidateReport:
    """Aggregate the measured values and verdicts for one candidate.

    ``heightmap`` may be a :class:`HeightMap` or a path to an ``.HG2`` file;
    ``layout`` is a :class:`~bzmap.model.layout.LayoutGraph`; ``spawns`` is an
    optional iterable of placed spawn objects (each with ``x``, ``z`` and
    ``team``) used by the balance validator's B3 check. ``structural_problems``
    is the list returned by :func:`bzmap.validate.formats.validate_map` for
    the candidate's file directory (Tier 1). ``seed`` is the candidate's seed,
    recorded verbatim for provenance.
    """

    def __init__(self, heightmap, layout: LayoutGraph, *,
                 spawns=None, structural_problems=None, seed=None,
                 preview_size=DEFAULT_PREVIEW_SIZE):
        if isinstance(heightmap, HeightMap):
            self.heightmap = heightmap
        else:
            self.heightmap = read_hg2(heightmap)
        self.layout = layout
        self.spawns = list(spawns) if spawns is not None else None
        self.structural_problems = list(structural_problems or [])
        self.seed = seed
        self.preview_size = tuple(preview_size)

        self.terrain = TerrainValidator(self.heightmap)
        self.connectivity = ConnectivityValidator(self.heightmap, layout)
        self.balance = BalanceValidator(self.heightmap, layout, spawns=self.spawns)

    # -- measured values -----------------------------------------------------

    def measured(self) -> dict:
        """Return the measured values from every validator, keyed by rule set.

        The dict records *measured values, not just verdicts* (docs/06
        §Reporting). Values are JSON-serialisable (dicts/lists/floats/ints).
        """
        return {
            "terrain": self.terrain.measure(),
            "connectivity": self.connectivity.measure(),
            "balance": self.balance.measure(),
        }

    # -- problems ------------------------------------------------------------

    def problems(self) -> list[str]:
        """All problems across every validator, Tier 1 first."""
        out = list(self.structural_problems)
        out.extend(self.terrain.validate())
        out.extend(self.connectivity.validate())
        out.extend(self.balance.validate())
        return out

    def _problems_by_severity(self) -> dict[str, list[str]]:
        grouped = {"error": [], "warning": [], "info": []}
        for p in self.problems():
            grouped[_severity(p)].append(p)
        return grouped

    # -- report dict ---------------------------------------------------------

    def to_dict(self) -> dict:
        """The full report as a JSON-serialisable dict.

        Contains the measured values, the per-severity problem lists, the
        overall verdict, and provenance (seed, map dimensions).
        """
        by_severity = self._problems_by_severity()
        return {
            "seed": self.seed,
            "width_m": self.heightmap.width_m,
            "depth_m": self.heightmap.depth_m,
            "grid": [self.heightmap.grid_x, self.heightmap.grid_z],
            "measured": self.measured(),
            "problems": {
                "error": by_severity["error"],
                "warning": by_severity["warning"],
                "info": by_severity["info"],
            },
            "verdict": "pass" if not by_severity["error"] else "fail",
        }

    # -- rendering -----------------------------------------------------------

    def preview(self):
        """Render the top-down preview with layout overlays.

        Overlays: economy nodes (geysers/scrap) and spawns as points, base
        sites as points, and the route graph as polylines. Returns a
        :class:`~bzmap.render.preview.Preview`.
        """
        objects = []
        for n in self.layout.nodes.values():
            if n.kind in (BASE, GEYSER, SCRAP, SPAWN):
                objects.append((n.x, n.z))
        routes = []
        seen = set()
        for n in self.layout.nodes.values():
            for nxt, _ in self.layout.neighbours(n.id):
                edge = tuple(sorted((n.id, nxt)))
                if edge in seen:
                    continue
                seen.add(edge)
                nb = self.layout.nodes[nxt]
                routes.append([(n.x, n.z), (nb.x, nb.z)])
        return render_preview(
            self.heightmap,
            objects=objects,
            routes=routes,
            size=self.preview_size,
        )

    # -- writing -------------------------------------------------------------

    def write(self, out_dir) -> Path:
        """Write ``report.json`` and ``preview.png`` into ``out_dir``.

        ``out_dir`` is created if absent. Returns the path to ``report.json``.
        """
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        json_path = out_dir / "report.json"
        json_path.write_text(
            json.dumps(self.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        self.preview().save(out_dir / "preview.png")
        return json_path


def write_report(out_dir, heightmap, layout: LayoutGraph, *,
                 spawns=None, structural_problems=None, seed=None,
                 preview_size=DEFAULT_PREVIEW_SIZE) -> Path:
    """Write a candidate's ``report.json`` and ``preview.png``; return the JSON path.

    Convenience wrapper around :class:`CandidateReport` — see its docstring for
    the argument semantics.
    """
    report = CandidateReport(
        heightmap,
        layout,
        spawns=spawns,
        structural_problems=structural_problems,
        seed=seed,
        preview_size=preview_size,
    )
    return report.write(out_dir)