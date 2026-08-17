"""``.vdf`` / ``.sdf`` BWD2 node containers (docs/formats/F5)."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

VDF_RECORD = 100
SDF_RECORD = 120
LOD_VDF, REP_VDF = 7, 4
LOD_SDF, REP_SDF = 3, 2

SKIP_CLASS = {
    0x26, 0x28, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
}


def _cname(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("ascii", errors="ignore")


@dataclass
class Bwd2Node:
    name: str
    parent: str
    transform: tuple  # 12 floats
    class_id: int
    lod: int
    rep: int
    radius: float


@dataclass
class Bwd2Model:
    kind: str  # vdf or sdf
    nodes: list


def read_bwd2(path) -> Bwd2Model:
    data = Path(path).read_bytes()
    off = 0
    kind = "sdf" if path.suffix.lower() == ".sdf" else "vdf"
    nodes = []
    while off + 8 <= len(data):
        name = data[off:off + 4]
        size = struct.unpack_from("<i", data, off + 4)[0]
        if size < 8 or off + size > len(data):
            break
        payload = data[off + 8:off + size]
        tag = name[:3] if name[:3] == b"REV" else name.rstrip(b"\x00")
        if tag in (b"VGEO", b"SGEO"):
            nodes = _parse_geo_table(payload, sdf=(tag == b"SGEO"))
        off += size
    return Bwd2Model("sdf" if kind == "sdf" else "vdf", nodes)


def _parse_geo_table(payload: bytes, sdf: bool):
    if len(payload) < 4:
        return []
    count = struct.unpack_from("<I", payload, 0)[0]
    rec = SDF_RECORD if sdf else VDF_RECORD
    lod_n = LOD_SDF if sdf else LOD_VDF
    rep_n = REP_SDF if sdf else REP_VDF
    expected = lod_n * rep_n * count
    nodes = []
    off = 4
    slot = 0
    for lod in range(lod_n):
        for rep in range(rep_n):
            for _ in range(count):
                if off + rec > len(payload):
                    return nodes
                raw = payload[off:off + rec]
                off += rec
                name = _cname(raw[0:8])
                if name.upper() == "NULL" or not name:
                    slot += 1
                    continue
                xform = struct.unpack_from("<12f", raw, 8)
                parent = _cname(raw[0x38:0x40])
                radius = struct.unpack_from("<f", raw, 0x4C)[0]
                class_id = struct.unpack_from("<I", raw, 0x5C)[0]
                nodes.append(Bwd2Node(name, parent, xform, class_id, lod, rep, radius))
                slot += 1
    _ = expected
    return nodes


def visible_primary(nodes):
    """LOD 0 / REP 0 renderable geometry nodes."""
    out = []
    for n in nodes:
        if n.lod != 0 or n.rep != 0:
            continue
        if n.class_id in SKIP_CLASS:
            continue
        out.append(n)
    return out


def xform_point(xform, p):
    """Apply a 12-float right/up/front/posit transform to a point."""
    rx, ry, rz, ux, uy, uz, fx, fy, fz, px, py, pz = xform
    return (
        rx * p[0] + ux * p[1] + fx * p[2] + px,
        ry * p[0] + uy * p[1] + fy * p[2] + py,
        rz * p[0] + uz * p[1] + fz * p[2] + pz,
    )


def xform_dir(xform, p):
    rx, ry, rz, ux, uy, uz, fx, fy, fz, _px, _py, _pz = xform
    return (
        rx * p[0] + ux * p[1] + fx * p[2],
        ry * p[0] + uy * p[1] + fy * p[2],
        rz * p[0] + uz * p[1] + fz * p[2],
    )
