"""OGRE ``.mesh`` reader for MeshSerializer_v1.100 (docs/formats/F7)."""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

_H_HEADER = 0x1000
_M_MESH = 0x3000
_M_SUBMESH = 0x4000
_M_SUBMESH_OP = 0x4010
_M_GEOMETRY = 0x5000
_M_GEOM_DECL = 0x5100
_M_GEOM_ELEM = 0x5110
_M_GEOM_VBUF = 0x5200
_M_GEOM_VDATA = 0x5210
_M_BOUNDS = 0x9000

_VES_POSITION = 1
_VES_NORMAL = 4
_VES_COLOUR = 5
_VES_TEXCOORD = 7

_TYPE_SIZE = {
    0: 4, 1: 8, 2: 12, 3: 16, 4: 4, 5: 2, 6: 4, 7: 6, 8: 8, 9: 4,
    10: 4, 11: 4, 12: 8, 13: 16, 14: 24, 15: 32, 16: 2, 17: 4, 18: 6,
    19: 8, 20: 4, 21: 8, 22: 12, 23: 16, 24: 4, 25: 8, 26: 12, 27: 16,
    28: 4, 29: 4, 30: 4, 31: 4, 32: 8, 33: 4, 34: 8,
}


class _Buf:
    def __init__(self, data: bytes, le=True):
        self.data = data
        self.pos = 0
        self.le = le
        self.en = "<" if le else ">"

    def remaining(self):
        return len(self.data) - self.pos

    def at_end(self):
        return self.pos >= len(self.data)

    def u8(self):
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self):
        v = struct.unpack_from(self.en + "H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def u32(self):
        v = struct.unpack_from(self.en + "I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def f32(self):
        v = struct.unpack_from(self.en + "f", self.data, self.pos)[0]
        self.pos += 4
        return v

    def bytes(self, n):
        v = self.data[self.pos:self.pos + n]
        self.pos += n
        return v

    def string(self):
        end = self.data.find(b"\n", self.pos)
        if end < 0:
            end = len(self.data)
        s = self.data[self.pos:end].decode("ascii", errors="ignore")
        self.pos = end + 1 if end < len(self.data) else end
        return s

    def peek_u16(self):
        if self.remaining() < 2:
            return None
        return struct.unpack_from(self.en + "H", self.data, self.pos)[0]


@dataclass
class OgreSubmesh:
    material: str
    positions: list = field(default_factory=list)
    normals: list = field(default_factory=list)
    uvs: list = field(default_factory=list)
    indices: list = field(default_factory=list)


@dataclass
class OgreMesh:
    version: str
    submeshes: list


def read_ogre_mesh(path) -> OgreMesh:
    data = Path(path).read_bytes()
    if len(data) < 4:
        raise ValueError(f"{path}: too short")
    le = data[0] == 0x00 and data[1] == 0x10
    if not le and not (data[0] == 0x10 and data[1] == 0x00):
        # still try LE
        le = True
    buf = _Buf(data, le=le)
    hid = buf.u16()
    if hid != _H_HEADER and hid != 0x0010:
        # accept either endian interpretation of the header id
        pass
    version = buf.string()
    mesh = OgreMesh(version=version, submeshes=[])
    shared = None
    while not buf.at_end():
        cid = buf.peek_u16()
        if cid is None:
            break
        if cid == _M_MESH:
            _read_mesh(buf, mesh)
        else:
            _skip_chunk(buf)
    if shared is None:
        pass
    return mesh


def _skip_chunk(buf: _Buf):
    if buf.remaining() < 6:
        buf.pos = len(buf.data)
        return
    _cid = buf.u16()
    size = buf.u32()
    body = max(size - 6, 0)
    buf.pos = min(len(buf.data), buf.pos + body)


def _read_mesh(buf: _Buf, mesh: OgreMesh):
    start = buf.pos
    _cid = buf.u16()
    size = buf.u32()
    end = start + size
    _skel = buf.u8()
    shared = None
    while buf.pos < end:
        cid = buf.peek_u16()
        if cid is None:
            break
        if cid == _M_SUBMESH:
            mesh.submeshes.append(_read_submesh(buf, shared))
        elif cid == _M_GEOMETRY:
            shared = _read_geometry(buf)
        elif cid == _M_BOUNDS:
            _skip_chunk(buf)
        else:
            _skip_chunk(buf)
    buf.pos = end


def _read_submesh(buf: _Buf, shared) -> OgreSubmesh:
    start = buf.pos
    _cid = buf.u16()
    size = buf.u32()
    end = start + size
    material = buf.string()
    use_shared = buf.u8()
    index_count = buf.u32()
    idx32 = buf.u8()
    ib_size = index_count * (4 if idx32 else 2)
    raw = buf.bytes(ib_size)
    en = buf.en
    if idx32:
        indices = list(struct.unpack(f"{en}{index_count}I", raw))
    else:
        indices = list(struct.unpack(f"{en}{index_count}H", raw))
    geom = shared if use_shared else None
    while buf.pos < end:
        cid = buf.peek_u16()
        if cid is None:
            break
        if cid == _M_GEOMETRY:
            geom = _read_geometry(buf)
        else:
            _skip_chunk(buf)
    buf.pos = end
    sm = OgreSubmesh(material=material, indices=indices)
    if geom:
        sm.positions, sm.normals, sm.uvs = geom
        if not sm.normals:
            sm.normals = [(0.0, 1.0, 0.0)] * len(sm.positions)
        if not sm.uvs:
            sm.uvs = [(0.0, 0.0)] * len(sm.positions)
    return sm


def _read_geometry(buf: _Buf):
    start = buf.pos
    _cid = buf.u16()
    size = buf.u32()
    end = start + size
    vcount = buf.u32()
    elements = []  # (source, type, semantic, offset, index)
    buffers = {}  # bind -> (stride, bytes)
    while buf.pos < end:
        cid = buf.peek_u16()
        if cid is None:
            break
        if cid == _M_GEOM_DECL:
            elements.extend(_read_decl(buf))
        elif cid == _M_GEOM_VBUF:
            bind, stride, blob = _read_vbuf(buf)
            buffers[bind] = (stride, blob)
        else:
            _skip_chunk(buf)
    buf.pos = end
    return _decode_vertices(vcount, elements, buffers)


def _read_decl(buf: _Buf):
    start = buf.pos
    _cid = buf.u16()
    size = buf.u32()
    end = start + size
    elems = []
    while buf.pos < end:
        cid = buf.peek_u16()
        if cid != _M_GEOM_ELEM:
            break
        buf.u16()
        esize = buf.u32()
        eend = buf.pos + max(esize - 6, 0)
        source, typ, sem, offset, index = (
            buf.u16(), buf.u16(), buf.u16(), buf.u16(), buf.u16()
        )
        elems.append((source, typ, sem, offset, index))
        buf.pos = eend
    buf.pos = end
    return elems


def _read_vbuf(buf: _Buf):
    start = buf.pos
    _cid = buf.u16()
    size = buf.u32()
    end = start + size
    bind = buf.u16()
    stride = buf.u16()
    blob = b""
    while buf.pos < end:
        cid = buf.peek_u16()
        if cid == _M_GEOM_VDATA:
            buf.u16()
            dsize = buf.u32()
            blob = buf.bytes(max(dsize - 6, 0))
        else:
            if cid is None:
                break
            _skip_chunk(buf)
    buf.pos = end
    return bind, stride, blob


def _decode_vertices(vcount, elements, buffers):
    positions = [(0.0, 0.0, 0.0)] * vcount
    normals = []
    uvs = []
    have_n = False
    have_uv = False
    for i in range(vcount):
        nrm = (0.0, 1.0, 0.0)
        uv = (0.0, 0.0)
        pos = (0.0, 0.0, 0.0)
        for source, typ, sem, offset, _index in elements:
            if source not in buffers:
                continue
            stride, blob = buffers[source]
            off = i * stride + offset
            if off + 4 > len(blob):
                continue
            if sem == _VES_POSITION and typ == 2:
                pos = struct.unpack_from("<3f", blob, off)
            elif sem == _VES_NORMAL and typ == 2:
                nrm = struct.unpack_from("<3f", blob, off)
                have_n = True
            elif sem == _VES_TEXCOORD and typ in (1, 2, 3):
                uv = struct.unpack_from("<2f", blob, off)
                have_uv = True
        positions[i] = pos
        normals.append(nrm)
        uvs.append(uv)
    if not have_n:
        normals = []
    if not have_uv:
        uvs = []
    return positions, normals, uvs
