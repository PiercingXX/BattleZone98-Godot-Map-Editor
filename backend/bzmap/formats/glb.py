"""Minimal glTF 2.0 / GLB writer. No third-party glTF library."""

from __future__ import annotations

import json
import struct
from io import BytesIO
from pathlib import Path

from PIL import Image


def _pad(buf: bytes, align=4, fill=b" "):
    n = (-len(buf)) % align
    return buf + fill * n


def _minmax(values, n):
    if not values:
        return [0.0] * n, [0.0] * n
    lo = [min(v[i] for v in values) for i in range(n)]
    hi = [max(v[i] for v in values) for i in range(n)]
    return lo, hi


def write_glb(path, primitives, images=None):
    """Write a GLB.

    ``primitives`` is a list of dicts with ``positions``, ``normals``,
    ``uvs``, ``indices``, optional ``image`` (index into ``images``) and
    optional ``color`` (r,g,b 0-255).
    ``images`` is a list of ``PIL.Image``.
    """
    images = images or []
    bin_blob = bytearray()
    views = []
    accessors = []
    prims_json = []
    materials = []
    gltf_images = []
    textures = []

    def add_blob(data: bytes, target=None):
        if target == 34963:  # ELEMENT_ARRAY
            data = _pad(data, 4, b"\x00")
        else:
            data = _pad(data, 4, b"\x00")
        views.append({
            "buffer": 0,
            "byteOffset": len(bin_blob),
            "byteLength": len(data),
            **({"target": target} if target else {}),
        })
        bin_blob.extend(data)
        return len(views) - 1

    for img in images:
        buf = BytesIO()
        img.convert("RGBA").save(buf, format="PNG")
        png = buf.getvalue()
        view = add_blob(png)
        gltf_images.append({"bufferView": view, "mimeType": "image/png"})
        textures.append({"source": len(gltf_images) - 1})

    for prim in primitives:
        pos = list(prim["positions"])
        nrm = list(prim.get("normals") or [(0.0, 1.0, 0.0)] * len(pos))
        uvs = list(prim.get("uvs") or [(0.0, 0.0)] * len(pos))
        idx = list(prim["indices"])
        if not pos or not idx:
            continue
        pos_b = b"".join(struct.pack("<3f", *p) for p in pos)
        nrm_b = b"".join(struct.pack("<3f", *n) for n in nrm)
        uv_b = b"".join(struct.pack("<2f", *u) for u in uvs)
        if max(idx) > 65535:
            idx_b = struct.pack(f"<{len(idx)}I", *idx)
            idx_type = 5125
        else:
            idx_b = struct.pack(f"<{len(idx)}H", *idx)
            idx_type = 5123
        pv = add_blob(pos_b, 34962)
        nv = add_blob(nrm_b, 34962)
        uv = add_blob(uv_b, 34962)
        iv = add_blob(idx_b, 34963)
        plo, phi = _minmax(pos, 3)
        nlo, nhi = _minmax(nrm, 3)
        ulo, uhi = _minmax(uvs, 2)
        accessors.extend([
            {"bufferView": pv, "componentType": 5126, "count": len(pos),
             "type": "VEC3", "min": plo, "max": phi},
            {"bufferView": nv, "componentType": 5126, "count": len(nrm),
             "type": "VEC3", "min": nlo, "max": nhi},
            {"bufferView": uv, "componentType": 5126, "count": len(uvs),
             "type": "VEC2", "min": ulo, "max": uhi},
            {"bufferView": iv, "componentType": idx_type, "count": len(idx),
             "type": "SCALAR"},
        ])
        base = len(accessors) - 4
        colour = prim.get("colour") or (180, 180, 180)
        mat = {
            "pbrMetallicRoughness": {
                "baseColorFactor": [
                    colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0, 1.0
                ],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.9,
            },
        }
        img_i = prim.get("image")
        if img_i is not None and 0 <= img_i < len(textures):
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": img_i}
        materials.append(mat)
        prims_json.append({
            "attributes": {
                "POSITION": base,
                "NORMAL": base + 1,
                "TEXCOORD_0": base + 2,
            },
            "indices": base + 3,
            "material": len(materials) - 1,
            "mode": 4,
        })

    if not prims_json:
        raise ValueError("no primitives to write")

    root = {
        "asset": {"version": "2.0", "generator": "bzmap"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": prims_json}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_blob)}],
        "materials": materials,
    }
    if gltf_images:
        root["images"] = gltf_images
        root["textures"] = textures

    js = _pad(json.dumps(root, separators=(",", ":")).encode("utf-8"), 4, b" ")
    blob = _pad(bytes(bin_blob), 4, b"\x00")
    total = 12 + 8 + len(js) + 8 + len(blob)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    Path(path).write_bytes(out)
    return Path(path)
