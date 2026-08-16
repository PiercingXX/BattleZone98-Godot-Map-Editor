"""OGRE ``.mesh`` binary writer — ``MeshSerializer_v1.100`` (the BZ98R dialect).

This is the tooling that makes automated per-map geometry possible: water
surfaces, plant fields, any static mesh, generated in Python with **no Blender
and no manual step**. The format was reverse-engineered from the corpus pack's own
``desrten1.mesh`` (Oasis's water surface); the chunk layout below matches it
byte-for-byte in structure.

Chunk grammar (each chunk: ``<u16 id><u32 size>`` where ``size`` counts the
6-byte header + body + all nested chunks):

    0x1000 header        : u16 id, then version string + '\n'  (NOT length-prefixed)
    0x3000 M_MESH        : u8 skeletallyAnimated, then subchunks
      0x4000 M_SUBMESH   : material name + '\n', u8 useSharedVertices,
                           u32 indexCount, u8 indexes32bit, indices[], then geometry
        0x5000 M_GEOMETRY: u32 vertexCount, then:
          0x5100 vertex declaration: sequence of
            0x5110 element: u16 source,type,semantic,offset,index
          0x5200 vertex buffer: u16 bindIndex, u16 vertexSize, then
            0x5210 buffer data: raw interleaved vertex bytes
      0x9000 M_MESH_BOUNDS: min float3, max float3, radius float

Vertex element type/semantic codes are OGRE's ``VertexElementType`` /
``VertexElementSemantic`` enums. We emit the minimal useful vertex —
POSITION + NORMAL + TEXCOORD (32-byte stride) — which the engine accepts; the
water/plant *look* lives in the paired ``.material`` (blend mode, texture,
scroll), not the mesh.
"""

from __future__ import annotations

import struct
from pathlib import Path

_VERSION = b"[MeshSerializer_v1.100]\n"

# Chunk ids
_H_HEADER = 0x1000
_M_MESH = 0x3000
_M_SUBMESH = 0x4000
_M_GEOMETRY = 0x5000
_M_GEOM_VERTEX_DECL = 0x5100
_M_GEOM_VERTEX_ELEMENT = 0x5110
_M_GEOM_VERTEX_BUFFER = 0x5200
_M_GEOM_VERTEX_BUFFER_DATA = 0x5210
_M_MESH_BOUNDS = 0x9000

# VertexElementType
_VET_FLOAT2 = 1
_VET_FLOAT3 = 2
# VertexElementSemantic
_VES_POSITION = 1
_VES_NORMAL = 4
_VES_TEXCOORD = 7


def _chunk(cid: int, body: bytes) -> bytes:
    """Wrap ``body`` in a chunk header (size includes the 6-byte header)."""
    return struct.pack("<HI", cid, len(body) + 6) + body


def write_mesh(path, vertices, normals, uvs, indices, material_name: str):
    """Write a single-submesh OGRE mesh.

    ``vertices``/``normals`` are sequences of ``(x, y, z)``; ``uvs`` of
    ``(u, v)``; ``indices`` a flat sequence of triangle vertex indices
    (16-bit). ``material_name`` is the OGRE material the submesh uses (a
    matching ``<name>.material`` must ship alongside).

    All three vertex arrays must be the same length. Coordinates are in the
    game's world space (metres); the mesh is placed at a BZN object's position,
    so build vertices in world coordinates and place the object at the origin,
    exactly as the corpus ``desrten1`` does (it sits at ``0,0,0``).
    """
    n = len(vertices)
    if not (len(normals) == n and len(uvs) == n):
        raise ValueError("vertices, normals and uvs must be the same length")
    if max(indices, default=0) >= n:
        raise ValueError("index out of range")
    if n > 65535:
        raise ValueError(
            f"{n} vertices exceeds the 16-bit index limit; split the mesh"
        )

    # Interleaved vertex buffer: pos(3) + normal(3) + uv(2) = 32 bytes.
    buf = bytearray()
    minv = [float("inf")] * 3
    maxv = [float("-inf")] * 3
    for (px, py, pz), (nx, ny, nz), (u, v) in zip(vertices, normals, uvs):
        buf += struct.pack("<8f", px, py, pz, nx, ny, nz, u, v)
        for i, c in enumerate((px, py, pz)):
            minv[i] = min(minv[i], c)
            maxv[i] = max(maxv[i], c)

    # Vertex declaration
    decl = b""
    for typ, sem, off in (
        (_VET_FLOAT3, _VES_POSITION, 0),
        (_VET_FLOAT3, _VES_NORMAL, 12),
        (_VET_FLOAT2, _VES_TEXCOORD, 24),
    ):
        decl += _chunk(_M_GEOM_VERTEX_ELEMENT,
                       struct.pack("<5H", 0, typ, sem, off, 0))
    decl_chunk = _chunk(_M_GEOM_VERTEX_DECL, decl)

    vbuf = _chunk(
        _M_GEOM_VERTEX_BUFFER,
        struct.pack("<HH", 0, 32)
        + _chunk(_M_GEOM_VERTEX_BUFFER_DATA, bytes(buf)),
    )
    geometry = _chunk(_M_GEOMETRY, struct.pack("<I", n) + decl_chunk + vbuf)

    index_bytes = struct.pack(f"<{len(indices)}H", *indices)
    submesh_body = (
        material_name.encode("ascii") + b"\n"
        + struct.pack("<B", 0)                 # useSharedVertices = false
        + struct.pack("<I", len(indices))       # indexCount
        + struct.pack("<B", 0)                  # indexes32bit = false
        + index_bytes
        + geometry
    )
    submesh = _chunk(_M_SUBMESH, submesh_body)

    radius = max(
        (sum((maxv[i] - minv[i]) ** 2 for i in range(3))) ** 0.5 / 2.0, 1.0
    )
    bounds = _chunk(
        _M_MESH_BOUNDS,
        struct.pack("<7f", *minv, *maxv, radius),
    )

    mesh = _chunk(_M_MESH, struct.pack("<B", 0) + submesh + bounds)
    header = struct.pack("<H", _H_HEADER) + _VERSION

    Path(path).write_bytes(header + mesh)
    return Path(path)
