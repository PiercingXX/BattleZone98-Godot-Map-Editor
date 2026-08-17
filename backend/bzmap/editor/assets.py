"""``bzmap editor assets`` — live class index + proxy cache.

The editor ships no game content. This walks the user's install, enumerates
every placeable ODF, and writes Godot-loadable PNG icons plus an index.
Meshes stay on the proxy rung unless a converted ``.glb`` is already in cache.
"""

from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from bzmap.editor.discover import discover, first_game_root, is_game_install
from bzmap.editor.errors import EditorError
from bzmap.editor.jsonio import emit  # noqa: F401 — imported for symmetry
from bzmap.formats.bzn import read_bzn

_ODF_SUFFIXES = {".odf"}

# Classes that are known-safe BZN clones across the corpus (docs/02 §6).
_ALWAYS_VERIFIED = {
    "player", "pspwn_1", "eggeizr1",
    "npscr1", "npscr2", "npscr3", "sscr_1",
}

_CATEGORY_COLORS = {
    "craft": (60, 140, 80),
    "building": (80, 90, 150),
    "prop": (130, 120, 90),
    "scrap": (200, 160, 40),
    "geyser": (210, 90, 40),
    "spawn": (220, 200, 50),
    "environment": (70, 130, 110),
    "other": (110, 110, 115),
}

_DEFAULT_FOOTPRINT = {
    "craft": (10.0, 10.0),
    "building": (24.0, 24.0),
    "prop": (8.0, 8.0),
    "scrap": (4.0, 4.0),
    "geyser": (16.0, 16.0),
    "spawn": (6.0, 6.0),
    "environment": (32.0, 32.0),
    "other": (8.0, 8.0),
}

_DEFAULT_HEIGHT = {
    "craft": 4.0,
    "building": 12.0,
    "prop": 4.0,
    "scrap": 1.5,
    "geyser": 8.0,
    "spawn": 1.0,
    "environment": 6.0,
    "other": 4.0,
}


def _parse_odf(path):
    data = {}
    section = ""
    try:
        text = Path(path).read_text(encoding="latin-1", errors="replace")
    except OSError:
        return data
    for raw in text.splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and "]" in line:
            section = line[1:line.index("]")].strip()
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        key_l = key.strip().lower()
        data[key_l] = value
        if section:
            data[f"{section.lower()}.{key_l}"] = value
    return data


def _categorize(prjid, class_label):
    p = (prjid or "").lower()
    cl = (class_label or "").lower()
    if p == "player" or "player" in cl:
        return "craft"
    if "scrap" in cl or p.startswith("npscr") or p in {"sscr_1", "blc-pell"}:
        return "scrap"
    if "geyser" in cl or "geiz" in p:
        return "geyser"
    if "spawn" in cl or p.startswith("pspwn"):
        return "spawn"
    if any(token in cl for token in (
        "i76building2", "i76building", "environment",
    )):
        return "environment"
    if any(token in cl for token in (
        "building", "factory", "recycler", "constructor", "silo",
        "extractor", "powerplant", "armory", "barracks", "gun",
    )):
        return "building"
    if any(token in cl for token in (
        "wingman", "craft", "hover", "tank", "walker", "turret",
        "scout", "bomber", "apc", "tug", "howitzer",
    )):
        return "craft"
    return "prop"


def _faction(prjid):
    p = (prjid or "").lower()
    if not p:
        return None
    first = p[0]
    return {
        "a": "NSDF",
        "s": "CCA",
        "b": "Black Dog",
        "c": "Chinese",
        "f": "Fury",
        "i": "ISDF",
        "e": None,
        "n": None,
        "p": None,
    }.get(first)


def _float_field(data, *names, default=None):
    for name in names:
        raw = data.get(name)
        if raw is None:
            continue
        try:
            return float(str(raw).split()[0])
        except ValueError:
            continue
    return default


def _scan_odfs(root, source_id):
    """Yield ``(prjid, path, source_id)`` for every ``.odf`` under ``root``.

    Workshop items are flat; the base game uses nested trees. Walk both.
    Matching is case-insensitive on the suffix only.
    """
    root = Path(root)
    if not root.is_dir():
        return
    try:
        iterator = root.rglob("*")
    except OSError:
        return
    for path in iterator:
        try:
            if not path.is_file():
                continue
        except OSError:
            continue
        if path.suffix.lower() not in _ODF_SUFFIXES:
            continue
        yield path.stem.lower(), path, source_id


def _verified_prjids(pack_dirs):
    verified = set(_ALWAYS_VERIFIED)
    scanned = 0
    for pack in pack_dirs:
        pack = Path(pack)
        if not pack.is_dir():
            continue
        try:
            children = list(pack.iterdir())
        except OSError:
            continue
        for path in children:
            if not path.is_file() or path.suffix.lower() != ".bzn":
                continue
            scanned += 1
            if scanned > 24:
                # A couple of dozen corpus BZNs already cover the verified set.
                # Full 128 is slow and does not change the safety gate.
                return verified
            try:
                bzn = read_bzn(path)
            except (OSError, ValueError, UnicodeDecodeError):
                continue
            for obj in bzn.objects:
                if obj.prjid:
                    verified.add(obj.prjid.lower())
    return verified


def _fingerprint(game_root, pack_dirs):
    h = hashlib.sha256()
    roots = [Path(game_root)] + [Path(p) for p in pack_dirs]
    for root in roots:
        h.update(str(root).encode("utf-8", "replace"))
        try:
            st = root.stat()
            h.update(str(int(st.st_mtime)).encode())
            h.update(str(int(st.st_size if hasattr(st, "st_size") else 0)).encode())
        except OSError:
            continue
        models = root / "BZ_ASSETS" / "common" / "models"
        if models.is_dir():
            try:
                h.update(str(int(models.stat().st_mtime)).encode())
            except OSError:
                pass
    return "sha256:" + h.hexdigest()


def _icon(prjid, category, out_path):
    color = _CATEGORY_COLORS.get(category, _CATEGORY_COLORS["other"])
    img = Image.new("RGB", (64, 64), color)
    draw = ImageDraw.Draw(img)
    draw.rectangle((1, 1, 62, 62), outline=(240, 240, 240))
    label = (prjid or "?")[:8]
    try:
        font = ImageFont.load_default()
    except OSError:
        font = None
    draw.text((4, 24), label, fill=(250, 250, 250), font=font)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, format="PNG")


def _class_record(prjid, path, source, verified, cache_dir):
    data = _parse_odf(path)
    class_label = (
        data.get("classlabel")
        or data.get("classlabel")
        or data.get("gameobjectclass.classlabel")
        or ""
    )
    category = _categorize(prjid, class_label)
    radius = _float_field(
        data, "collisionradius", "boundingradius", "radius",
        default=_DEFAULT_FOOTPRINT[category][0] * 0.5,
    )
    width = _float_field(data, "width", "size", default=radius * 2.0)
    length = _float_field(data, "length", "depth", default=radius * 2.0)
    height = _float_field(
        data, "height", "boundingheight",
        default=_DEFAULT_HEIGHT[category],
    )
    icon_rel = Path("icons") / f"{prjid}.png"
    icon_path = cache_dir / icon_rel
    if not icon_path.is_file():
        _icon(prjid, category, icon_path)
    glb = cache_dir / "meshes" / f"{prjid}.glb"
    if glb.is_file():
        mesh = str(glb)
        fidelity = "geo_textured"
    else:
        mesh = ""
        fidelity = "proxy"
    is_verified = prjid.lower() in verified
    return {
        "prjid": prjid,
        "odf": path.name,
        "source": source,
        "category": category,
        "label": class_label or prjid,
        "faction": _faction(prjid),
        "radius_m": float(radius),
        "footprint_m": [float(width), float(length)],
        "height_m": float(height),
        "mesh": mesh,
        "mesh_fidelity": fidelity,
        "icon": str(icon_rel).replace("\\", "/"),
        "template_verified": is_verified,
        "placement_mode": "bzn" if is_verified else "runtime",
        "class_label": class_label,
    }


def build_assets(game_root, cache_dir, pack_paths=None, refresh=False):
    """Build or refresh the asset cache. Returns the contract payload."""
    game_root = Path(game_root) if game_root else first_game_root()
    if game_root is None or not is_game_install(game_root):
        raise EditorError(
            "no_game",
            "no game install found; pass --game-root",
            hint="run probe first",
        )
    game_root = Path(game_root)
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    index_path = cache_dir / "index.json"

    discovery = discover()
    if not pack_paths:
        pack_paths = [
            item["path"]
            for item in discovery["installs"]
            if item.get("kind") == "workshop_item"
        ]

    fingerprint = _fingerprint(game_root, pack_paths)
    if index_path.is_file() and not refresh:
        try:
            existing = json.loads(index_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            existing = {}
        if existing.get("source_fingerprint") == fingerprint:
            existing["ok"] = True
            existing["cache_dir"] = str(cache_dir.resolve())
            return existing

    print("enumerating ODFs…", flush=True)
    found = {}
    # Base game first; packs override by prjid so BZP classes win their layer.
    for prjid, path, source in _scan_odfs(game_root / "BZ_ASSETS", "game"):
        found[prjid] = (path, source)
    # Also loose ODFs at the install root (rare).
    for prjid, path, source in _scan_odfs(game_root / "addon", "game"):
        found.setdefault(prjid, (path, source))

    for pack in pack_paths:
        pack = Path(pack)
        source_id = pack.name
        for prjid, path, source in _scan_odfs(pack, source_id):
            found[prjid] = (path, source)

    print(f"found {len(found)} classes; scanning templates…", flush=True)
    verified = _verified_prjids(pack_paths)

    classes = []
    unresolved = []
    for prjid in sorted(found):
        path, source = found[prjid]
        try:
            classes.append(_class_record(prjid, path, source, verified, cache_dir))
        except OSError as exc:
            unresolved.append({"prjid": prjid, "reason": str(exc)})

    payload = {
        "ok": True,
        "cache_dir": str(cache_dir.resolve()),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source_fingerprint": fingerprint,
        "classes": classes,
        "unresolved": unresolved,
    }
    index_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(classes)} classes to {index_path}", flush=True)
    return payload
