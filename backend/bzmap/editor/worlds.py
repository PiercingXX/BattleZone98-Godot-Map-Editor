"""``bzmap editor worlds`` — stock terrain templates for the new-map wizard."""

from __future__ import annotations

import re
from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.formats.trn import read_trn

# The nine stock worlds in Edit/trn/.
STOCK_WORLDS = (
    "achilles", "elysium", "europa", "ganymede", "io",
    "mars", "moon", "titan", "venus",
)

_TEXTURE_HEADER = re.compile(r"^\[TextureType(\d+)\](.*)$")
_FLAT_RGB = re.compile(r"(\d+)\s+(\d+)\s+(\d+)")


def worlds_from_game(game_root):
    """Enumerate ``Edit/trn/*.trn`` into the contract's worlds list."""
    game_root = Path(game_root)
    trn_dir = game_root / "Edit" / "trn"
    if not trn_dir.is_dir():
        raise EditorError(
            "no_trn_templates",
            f"no Edit/trn directory under {game_root}",
            hint="the game install is missing its terrain templates",
            path=trn_dir,
        )

    by_id = {}
    for path in trn_dir.iterdir():
        if not path.is_file() or path.suffix.lower() != ".trn":
            continue
        world_id = path.stem.lower()
        by_id[world_id] = _describe_world(path, world_id)

    worlds = []
    for world_id in STOCK_WORLDS:
        if world_id in by_id:
            worlds.append(by_id.pop(world_id))
    # Any extra templates (mods) after the stock nine.
    for world_id in sorted(by_id):
        worlds.append(by_id[world_id])
    if not worlds:
        raise EditorError(
            "no_trn_templates",
            f"Edit/trn exists but contains no .trn files: {trn_dir}",
            path=trn_dir,
        )
    return worlds


def _describe_world(path, world_id):
    cfg = read_trn(path)
    atlas = cfg.get("Atlases", "MaterialName") or ""
    sky = cfg.get("Sky", "SkyTexture") or cfg.get("Sky", "SkyType") or ""
    labels = _texture_labels(cfg)
    texture_types = []
    for i in range(16):
        section = cfg.section(f"TextureType{i}")
        if section is None:
            continue
        flat = section.get("FlatColor") or ""
        texture_types.append({
            "index": i,
            "flat_color": _parse_flat_color(flat),
            "label": labels.get(i) or "",
        })
    return {
        "id": world_id,
        "label": world_id.capitalize(),
        "trn_template": str(Path("Edit") / "trn" / path.name),
        "atlas": atlas.strip(),
        "sky": sky.strip(),
        "texture_types": texture_types,
    }


def _texture_labels(cfg):
    """Pull ``// Sandy`` comments off ``[TextureTypeN]`` header lines."""
    labels = {}
    for line in cfg._lines:
        match = _TEXTURE_HEADER.match(line.strip())
        if not match:
            continue
        index = int(match.group(1))
        rest = match.group(2)
        comment = rest.split("//", 1)
        if len(comment) == 2:
            labels[index] = comment[1].strip()
        elif rest.strip() and not rest.strip().startswith(";"):
            labels[index] = rest.strip()
    return labels


def _parse_flat_color(value):
    """Return an RGB triple. A single number is a palette index, expanded."""
    value = (value or "").strip()
    rgb = _FLAT_RGB.search(value)
    if rgb:
        return [int(rgb.group(1)), int(rgb.group(2)), int(rgb.group(3))]
    try:
        n = int(value.split()[0])
    except (ValueError, IndexError):
        return [128, 128, 128]
    return [n, n, n]
