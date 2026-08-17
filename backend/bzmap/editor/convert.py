"""Convert a placeable class to a Godot-loadable ``.glb``."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from bzmap.formats.bwd2 import read_bwd2, visible_primary, xform_dir, xform_point
from bzmap.formats.geo import geo_to_primitives, read_geo
from bzmap.formats.glb import write_glb
from bzmap.formats.maptex import read_act, read_map
from bzmap.formats.ogre import read_ogre_mesh


def casefold_index(roots):
    """Map lowercased name → path for files under ``roots``."""
    index = {}
    for root in roots:
        root = Path(root)
        if not root.is_dir():
            continue
        try:
            walker = root.rglob("*")
        except OSError:
            continue
        for path in walker:
            try:
                if path.is_file():
                    index.setdefault(path.name.lower(), path)
            except OSError:
                continue
    return index


def resolve(index, name, suffixes):
    stem = Path(name).stem.lower()
    raw = name.lower()
    for suf in suffixes:
        hit = index.get(raw if raw.endswith(suf) else stem + suf)
        if hit is not None:
            return hit
    return None


def parse_material_diffuse(path):
    try:
        text = Path(path).read_text(encoding="latin-1", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        s = line.strip()
        if "set_texture_alias" in s.lower() and "diffusemap" in s.lower():
            parts = s.split()
            if parts:
                return parts[-1].strip('"')
        if s.lower().startswith("texture "):
            return s.split(None, 1)[1].strip().strip('"')
    return None


def _open_image(index, name):
    if not name:
        return None
    path = resolve(index, name, (".png", ".dds", ".jpg", ".tga", ".map"))
    if path is None:
        return None
    suf = path.suffix.lower()
    try:
        if suf == ".map":
            act = None
            for cand in path.parent.iterdir():
                if cand.suffix.lower() == ".act":
                    try:
                        act = read_act(cand)
                        break
                    except ValueError:
                        continue
            return read_map(path, act)
        return Image.open(path).convert("RGBA")
    except (OSError, ValueError):
        return None


def convert_hd(stem, index, dest):
    mesh_path = resolve(index, stem, (".mesh",))
    if mesh_path is None:
        return None, "no .mesh"
    ogre = read_ogre_mesh(mesh_path)
    images = []
    prims = []
    for sm in ogre.submeshes:
        if not sm.positions or not sm.indices:
            continue
        img_i = None
        mat_path = resolve(index, sm.material or stem, (".material",))
        tex_name = parse_material_diffuse(mat_path) if mat_path else None
        if tex_name is None and sm.material:
            tex_name = sm.material
        img = _open_image(index, tex_name) if tex_name else None
        if img is None:
            img = _open_image(index, stem + "_d") or _open_image(index, stem + "_D")
        if img is not None:
            img_i = len(images)
            images.append(img)
        prims.append({
            "positions": sm.positions,
            "normals": sm.normals or [(0.0, 1.0, 0.0)] * len(sm.positions),
            "uvs": sm.uvs or [(0.0, 0.0)] * len(sm.positions),
            "indices": sm.indices,
            "image": img_i,
            "colour": (200, 200, 200),
        })
    if not prims:
        return None, "empty ogre mesh"
    write_glb(dest, prims, images)
    return dest, "hd"


def convert_geo_file(geo_path, index, dest, xform=None):
    mesh = read_geo(geo_path)
    groups = geo_to_primitives(mesh)
    images = []
    prims = []
    for g in groups:
        verts = g["verts"]
        norms = g["norms"]
        if xform is not None:
            verts = [xform_point(xform, v) for v in verts]
            norms = [xform_dir(xform, n) for n in norms]
        img_i = None
        if g["texture"]:
            img = _open_image(index, g["texture"])
            if img is not None:
                img_i = len(images)
                images.append(img)
        prims.append({
            "positions": verts,
            "normals": norms,
            "uvs": g["uvs"],
            "indices": g["indices"],
            "image": img_i,
            "colour": g["colour"],
        })
    if not prims:
        return None, "empty geo"
    write_glb(dest, prims, images)
    return dest, "geo_flat" if not images else "geo_textured"


def convert_bwd2(stem, index, dest):
    container = resolve(index, stem, (".sdf", ".vdf"))
    if container is None:
        geo = resolve(index, stem, (".geo",))
        if geo is None:
            return None, "no sdf/vdf/geo"
        return convert_geo_file(geo, index, dest)
    model = read_bwd2(container)
    nodes = visible_primary(model.nodes)
    if not nodes:
        geo = resolve(index, stem, (".geo",))
        if geo is None:
            return None, "no visible nodes"
        return convert_geo_file(geo, index, dest)
    images = []
    prims = []
    for node in nodes:
        geo_path = resolve(index, node.name, (".geo",))
        if geo_path is None:
            continue
        mesh = read_geo(geo_path)
        for g in geo_to_primitives(mesh):
            verts = [xform_point(node.transform, v) for v in g["verts"]]
            norms = [xform_dir(node.transform, n) for n in g["norms"]]
            img_i = None
            if g["texture"]:
                img = _open_image(index, g["texture"])
                if img is not None:
                    img_i = len(images)
                    images.append(img)
            prims.append({
                "positions": verts,
                "normals": norms,
                "uvs": g["uvs"],
                "indices": g["indices"],
                "image": img_i,
                "colour": g["colour"],
            })
    if not prims:
        return None, "bwd2 produced no geometry"
    fidelity = "geo_textured" if images else "geo_flat"
    write_glb(dest, prims, images)
    return dest, fidelity


def convert_class(stem, search_roots, dest):
    """Best-effort convert. Returns ``(path_or_None, fidelity, reason)``."""
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    index = casefold_index(search_roots)
    try:
        path, why = convert_hd(stem, index, dest)
        if path is not None:
            return path, "hd", ""
        hd_reason = why
    except Exception as exc:  # noqa: BLE001
        hd_reason = f"hd: {exc}"
    try:
        path, why = convert_bwd2(stem, index, dest)
        if path is not None:
            return path, why, ""
        geo_reason = why
    except Exception as exc:  # noqa: BLE001
        geo_reason = f"geo: {exc}"
    return None, "proxy", f"{hd_reason}; {geo_reason}"
