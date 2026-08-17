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
    atlas_name = atlas.strip()
    # Edit/trn/mars.trn → game root is parents[2]
    game_root = path.parent.parent.parent
    atlas_image, tile_uvs = _atlas_lookup(game_root, atlas_name, world_id)
    return {
        "id": world_id,
        "label": world_id.capitalize(),
        "trn_template": str(Path("Edit") / "trn" / path.name),
        "atlas": atlas_name,
        "atlas_image": atlas_image,
        "tile_uvs": tile_uvs,
        "sky": sky.strip(),
        "texture_types": texture_types,
    }


def _atlas_lookup(game_root, atlas_name, world_id):
    """Return (atlas_image_path, [16] uv rects) for solid tiles."""
    stem = atlas_name
    if stem.lower().endswith("_atlas"):
        stem = stem[: -len("_atlas")]
    if not stem:
        stem = f"{world_id[:2]}_detail"
    game_root = Path(game_root)
    candidates = [
        game_root / "Edit" / "Detail_PNG" / f"{stem}.png",
        game_root / "Edit" / "Detail" / f"{stem}.dds",
        game_root / "BZ_ASSETS" / "pc" / "textures" / "TerrainTextures" / "Detail" / f"{stem}.dds",
    ]
    image = ""
    for c in candidates:
        if c.is_file():
            image = str(c)
            break
    uvs = [[0.0, 0.0, 0.125, 0.125]] * 16
    csv = game_root / "Edit" / "PlanetMaterials" / f"{atlas_name}.csv"
    if not csv.is_file():
        csv = game_root / "Edit" / "PlanetMaterials" / f"{stem}_atlas.csv"
    prefix = world_id[:2].upper()
    if csv.is_file():
        try:
            text = csv.read_text(encoding="ascii", errors="replace")
        except OSError:
            text = ""
        found = {}
        for line in text.splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) < 5:
                continue
            name = parts[0].upper()
            try:
                u, v, w, h = float(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])
            except ValueError:
                continue
            found[name] = [u, v, w, h]
        for i in range(16):
            key = f"{prefix}{i}{i}SA0.MAP"
            alt = f"{prefix}{i:X}{i:X}SA0.MAP"
            if key in found:
                uvs[i] = found[key]
            elif alt in found:
                uvs[i] = found[alt]
    return image, uvs


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
