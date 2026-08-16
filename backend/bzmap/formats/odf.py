"""``.odf`` per-map settings writer (docs/01 §7).

Read by the game-mode scripts at runtime via ``OpenODF(GetMapTRNFilename())``. The section name is
``[SBPMapSettings]`` — legacy SBP naming that the game-mode Lua reads literally, so it
must **not** be renamed. Control points are
optional (used by ``GAMEMODESub_ControlPoints.lua``); the scripts also read an optional
``[ScrapImpactZone]`` section (``SIZ_IncludeSpawnPoints``, default true).
"""

from __future__ import annotations

from pathlib import Path

_EOL = "\r\n"


def write_odf(path, control_points=None, scrap_include_spawn_points=True):
    """Write an ``.odf`` settings file to ``path``.

    ``control_points`` is an optional iterable of ``(name, x, z)`` triples
    rendered as ``CP<n>Name`` / ``CP<n>X`` / ``CP<n>Z``. When omitted, only the
    ``[SBPMapSettings]`` header and the optional ``[ScrapImpactZone]`` section are
    written.
    """
    path = Path(path)
    lines = ["[SBPMapSettings]", ""]
    if control_points:
        for i, (name, x, z) in enumerate(control_points, start=1):
            lines.extend(
                [
                    f"CP{i}Name = {name}",
                    f"CP{i}X = {x}",
                    f"CP{i}Z = {z}",
                ]
            )
    lines.append("")
    lines.append("[ScrapImpactZone]")
    lines.append(f"SIZ_IncludeSpawnPoints = {int(scrap_include_spawn_points)}")
    text = _EOL.join(lines) + _EOL
    path.write_text(text, encoding="utf-8", newline="")

#: PrjIDs whose ODF declares ``classLabel = "scrap"`` across the map corpus.
#: Counting scrap by the ``npscr*`` prefix alone under-counts: 10 corpus maps also
#: place ``sscr_1``, and Pac-Man's 434 pellets are ``blc-pell`` (measured
#: 2026-08-11, measured across the corpus). The durable rule is the ODF classLabel; this frozen
#: set is the corpus-measured expansion for callers working from BZN text
#: without ODF resolution.
KNOWN_SCRAP_PRJIDS = frozenset(
    {"npscr1", "npscr2", "npscr3", "sscr_1", "blc-pell"}
)


def is_scrap_prjid(prjid):
    """True when ``prjid`` is a known scrap class (see :data:`KNOWN_SCRAP_PRJIDS`)."""
    return prjid.lower() in KNOWN_SCRAP_PRJIDS
