"""``.ini`` workshop + multiplayer metadata writer (docs/01 §5).

A small INI with three sections:

- ``[DESCRIPTION]`` — ``missionName`` (the user-facing map name).
- ``[WORKSHOP]`` — ``mapType`` and ``customtags``.
- ``[MULTIPLAYER]`` — ``minPlayers`` / ``maxPlayers`` / ``gameType``.

The pack is uniform on the multiplayer fields: **every one of the 36 corpus maps
uses ``gameType = K``** and 35 of 36 use ``maxPlayers = 14`` (docs/01 §5,
corpus conventions). Those are the defaults here so a caller gets pack-matching output
without having to remember them.
"""

from __future__ import annotations

from pathlib import Path

_EOL = "\r\n"


def write_ini(
    path,
    mission_name,
    *,
    map_type="multiplayer",
    customtags="",
    min_players=1,
    max_players=14,
    game_type="K",
):
    """Write a ``.ini`` metadata file to ``path``.

    ``mission_name`` is the user-facing name (e.g. ``Silver Pools``).
    ``game_type`` defaults to ``K`` and ``max_players`` to ``14`` to match the
    pack (docs/01 §5). Values are written quoted, as the corpus does.
    """
    path = Path(path)
    tags = f'customtags = "{customtags}"' if customtags else 'customtags = ""'
    text = (
        "[DESCRIPTION]" + _EOL
        + f'missionName = "{mission_name}"' + _EOL
        + _EOL
        + "[WORKSHOP]" + _EOL
        + ';mapType = "instant_action"' + _EOL
        + f'mapType = "{map_type}"' + _EOL
        + tags + _EOL
        + _EOL
        + "[MULTIPLAYER]" + _EOL
        + f'minPlayers = "{min_players}"' + _EOL
        + f'maxPlayers = "{max_players}"' + _EOL
        + f'gameType = "{game_type}"' + _EOL
    )
    path.write_text(text, encoding="utf-8", newline="")