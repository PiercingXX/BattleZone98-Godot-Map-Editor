"""``.des`` map description writer — free text generated from real counts (docs/01 §6).

The ``.des`` file is the free-text blurb shown in the map browser. There is no
enforced schema, but the corpus is consistent about one thing: the stated
``GEYSERS`` and ``SCRAP`` counts match the **actual object counts in the ``_S``
BZN** (docs/01 §6, docs/06 Tier-1 cross-file consistency). The validator checks
this, so the counts must be derived from the real objects, never templated and
left to drift.

This module therefore takes the geyser and scrap counts as arguments and renders
them into the description; it never fabricates them.
"""

from __future__ import annotations

from pathlib import Path

_EOL = "\r\n"


def write_des(
    path,
    *,
    mission_name,
    world,
    size,
    geysers,
    scrap,
    players,
    author=None,
):
    """Write a ``.des`` description to ``path``.

    ``geysers`` and ``scrap`` must be the real object counts from the ``_S``
    BZN (geyser ``eggeizr1`` count; scrap = ``npscr1 + npscr2 + npscr3``). They
    are rendered verbatim into the text so the description cannot drift from the
    mission objects. ``author`` defaults to **Skippy** — the toolchain's builder credit (operator
    directive 2026-08-11: Skippy-original maps are "Made by Skippy", never
    "AI-generated"; the Workshop description still discloses machine generation).
    """
    path = Path(path)
    if author is None:
        author = "Skippy"
    lines = [
        f"WORLD: {world}\tSIZE: {size}",
        f"GEYSERS: {geysers}\tSCRAP: {scrap}",
        f"PLAYERS: {players}",
        f"Made by {author}",
    ]
    text = _EOL.join(lines) + _EOL
    path.write_text(text, encoding="utf-8", newline="")


def write_des_text(*, mission_name, world, size, geysers, scrap, players, author=None):
    """Return the ``.des`` text (CRLF) that :func:`write_des` would write.

    Useful for tests and for callers that want the string without touching disk.
    """
    if author is None:
        author = "Skippy"
    lines = [
        f"WORLD: {world}\tSIZE: {size}",
        f"GEYSERS: {geysers}\tSCRAP: {scrap}",
        f"PLAYERS: {players}",
        f"Made by {author}",
    ]
    return _EOL.join(lines) + _EOL

#: SIZE bands by map width. The corpus' own labels are authorial and
#: inconsistent (six 2560 m maps say "Small"; 5120 m spans Small..Huge —
#: measured 2026-08-11), so the bands follow the corpus majority per width.
SIZE_BANDS = ((2560, "Small"), (3840, "Medium"), (float("inf"), "Large"))


def size_band(width_m):
    """Derive the ``.des`` SIZE label from map width (metres).

    Replaces the hardcoded ``"Medium"`` that shipped on every generated map —
    wrong for 7 of the original 10 (generator-fixes audit).
    """
    for ceiling, label in SIZE_BANDS:
        if width_m <= ceiling:
            return label
    raise AssertionError("unreachable")
