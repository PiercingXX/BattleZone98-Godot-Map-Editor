"""``.geo`` classic mesh reader (docs/formats/F4)."""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

_HEADER = struct.Struct("<4s i 16s i i i")
_FACE_FIXED = struct.Struct("<ii3B3ff f BBB 13s i I")
_NODE = struct.Struct("<ii ff")

_MAGICS = {b".GEO", b"OEG."}


def _cstr(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("ascii", errors="ignore")


@dataclass
class GeoFace:
    colour: tuple
    texture_name: str
    nodes: list  # (pos_i, nrm_i, u, v)


@dataclass
class GeoMesh:
    name: str
    flags: int
    checksum: int
    positions: list
    normals: list
    faces: list


def read_geo(path) -> GeoMesh:
    data = Path(path).read_bytes()
    if len(data) < _HEADER.size:
        raise ValueError(f"{path}: too short for a .geo header")
    magic, checksum, name, nvert, nface, flags = _HEADER.unpack_from(data, 0)
    if magic not in _MAGICS:
        raise ValueError(f"{path}: bad magic {magic!r}")
    if nvert < 0 or nface < 0:
        raise ValueError(f"{path}: negative counts")
    off = _HEADER.size
    pos_bytes = 12 * nvert
    nrm_bytes = 12 * nvert
    if off + pos_bytes + nrm_bytes > len(data):
        raise ValueError(f"{path}: truncated vertex data")
    positions = [
        struct.unpack_from("<3f", data, off + i * 12) for i in range(nvert)
    ]
    off += pos_bytes
    normals = [
        struct.unpack_from("<3f", data, off + i * 12) for i in range(nvert)
    ]
    off += nrm_bytes
    faces = []
    for _ in range(nface):
        if off + _FACE_FIXED.size > len(data):
            raise ValueError(f"{path}: truncated face at {off}")
        (
            _idx, node_count, cr, cg, cb,
            _pnx, _pny, _pnz, _pd, _area,
            _shade, _tt, _xl, tex, _parent, _tree,
        ) = _FACE_FIXED.unpack_from(data, off)
        off += _FACE_FIXED.size
        nodes = []
        for _n in range(node_count):
            if off + _NODE.size > len(data):
                raise ValueError(f"{path}: truncated face node at {off}")
            pi, ni, u, v = _NODE.unpack_from(data, off)
            off += _NODE.size
            nodes.append((pi, ni, u, 1.0 - v))
        if node_count >= 3:
            faces.append(GeoFace((cr, cg, cb), _cstr(tex), nodes))
    return GeoMesh(_cstr(name), flags, checksum, positions, normals, faces)


def geo_to_primitives(mesh: GeoMesh):
    """Fan-triangulate, split on (pos, nrm, uv). Group by material key."""
    groups = {}
    for face in mesh.faces:
        key = face.texture_name.lower() if face.texture_name else f"rgb:{face.colour}"
        prim = groups.setdefault(key, {
            "verts": [], "norms": [], "uvs": [], "indices": [],
            "colour": face.colour, "texture": face.texture_name,
            "lookup": {},
        })
        idxs = []
        for pi, ni, u, v in face.nodes:
            if pi < 0 or pi >= len(mesh.positions):
                idxs = []
                break
            nrm = mesh.normals[ni] if 0 <= ni < len(mesh.normals) else (0.0, 1.0, 0.0)
            tup = (mesh.positions[pi], nrm, (u, v))
            slot = prim["lookup"].get(tup)
            if slot is None:
                slot = len(prim["verts"])
                prim["lookup"][tup] = slot
                prim["verts"].append(tup[0])
                prim["norms"].append(tup[1])
                prim["uvs"].append(tup[2])
            idxs.append(slot)
        for i in range(1, len(idxs) - 1):
            a, b, c = idxs[0], idxs[i], idxs[i + 1]
            if a == b or b == c or a == c:
                continue
            prim["indices"].extend((a, b, c))
    return [g for g in groups.values() if g["indices"]]
