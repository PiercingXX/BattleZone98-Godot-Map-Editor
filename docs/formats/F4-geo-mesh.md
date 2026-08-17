# F4 — `.geo` classic mesh

Little-endian. Confidence: **VERIFIED** throughout — two independent
implementations from different code lineages agree on every offset, and their
declared record sizes agree with the field arithmetic.

A `.geo` holds one mesh: a shared vertex/normal pool plus a list of n-gon faces.
Faces are the unit that carries material information, not vertices.

## 1. Header — 36 bytes

```
offset  size  type      field
0x00    4     char[4]   magic, ASCII ".GEO"
0x04    4     int32     checksum        (never validated by any reader seen)
0x08    16    char[16]  name            null-padded
0x18    4     int32     vertex_count
0x1C    4     int32     face_count
0x20    4     int32     flags           32-bit "GEOFlags" field
```

Fixed-length strings are null-padded and read up to the first null. Decode as
ASCII, tolerating and discarding non-ASCII bytes — Red Odyssey content contains
them and a strict decoder crashes on those files.

`flags` is a 32-bit field, exposed by editing tools as user-settable, with no
known per-bit semantics. Preserve it verbatim.

## 2. Vertex data

Immediately after the header, two arrays of `vertex_count` entries each, in this
order:

```
positions[vertex_count]   3 × float32   (x, y, z)
normals[vertex_count]     3 × float32   (x, y, z)
```

Total `24 × vertex_count` bytes. Positions and normals are **parallel arrays
indexed independently by face nodes** (§3) — a face node names a position index
and a normal index separately, and they are not required to be equal.

Coordinate frame: model space, **x = right, y = up, z = front** (F8 §1).

## 3. Face records

`face_count` records follow. Each is a **55-byte fixed part** followed by a
variable-length wireframe of `vertex_count_of_this_face` 16-byte nodes.

Fixed part:

```
offset  size  type      field
0x00    4     int32     index               face's own index
0x04    4     int32     node_count          vertices in this face's wireframe
0x08    1     uint8     colour_r
0x09    1     uint8     colour_g
0x0A    1     uint8     colour_b
0x0B    12    3×float   plane_normal        (x, y, z)
0x17    4     float32   plane_distance
0x1B    4     float32   poly_area
0x1F    1     uint8     shade_type          default 4
0x20    1     uint8     texture_type        default 1
0x21    1     uint8     xluscent_type       default 0, translucency
0x22    13    char[13]  texture_name        the `.map` texture name, no extension
0x2F    4     int32     parent_face_index
0x33    4     uint32    tree_branch
                        ─────
                        55 bytes
```

Then `node_count` wireframe nodes, 16 bytes each:

```
offset  size  type      field
0x00    4     int32     position_index      index into positions[]
0x04    4     int32     normal_index        index into normals[]
0x08    4     float32   u
0x0C    4     float32   v
```

Total face size = `55 + 16 × node_count`. Records are packed with **no
alignment padding** — 55 is odd on purpose. A reader that lets its language
align the struct will desync after the first face.

`poly_area` is a float. (One reference lineage reads that offset as an int32 and
labels it "unknown"; the other reads it as a float and names it. Same offset,
same width; the float reading is the meaningful one.)

## 4. Faces are n-gons — triangulate as a fan

`node_count` is not fixed at 3. Triangulate by fanning from the first node:

```
for i in 1 .. node_count-2:
    triangle (node[0], node[i], node[i+1])
```

This assumes faces are convex and planar, which the `plane_normal` /
`plane_distance` fields imply and which holds in observed content.

Duplicate and degenerate faces exist in real files. A face that cannot be
constructed (repeated vertices, zero area) should be skipped, and skipping it
**must not shift the material assignment of subsequent faces** — index materials
by the face records you actually emitted, not by the source face ordinal.

## 5. UV convention — V is flipped

**The stored `v` is inverted relative to the conventional bottom-left origin.**
Use `v_corrected = 1.0 − v_file`. This is **VERIFIED**; both lineages apply the
same flip, and textures come out upside down without it.

UVs live on **face nodes**, not on vertices. Because the same vertex index can
appear in multiple faces with different UVs, a converter targeting a
vertex-indexed format (glTF, OGRE) must **split vertices per unique
(position, normal, uv) tuple**. Collapsing UVs onto shared vertices — as one
reference lineage does, keeping only the last UV seen per vertex — produces
visibly wrong texturing on any mesh where faces disagree, and is a known defect
to avoid rather than reproduce.

## 6. Per-face flat colour is a real render mode

Each face carries an RGB triple. The engine renders these flat colours when a
texture does not resolve. That makes the `geo_flat` rung of the viewport fidelity
chain **engine-faithful, not a fallback we invented** — a `.geo` with unresolved
textures still looks approximately correct rather than untextured grey.

Practical rule for the converter: group faces into materials keyed by
`texture_name`; when `texture_name` is empty or the `.map` cannot be found,
key by the RGB triple instead and emit an unlit/flat material of that colour.

`texture_name` names a `.map` file **without a path** — resolve it by searching
the model's own directory first, then the wider asset search path,
case-insensitively (F6 §5).

## 7. Acceptance tests

1. **Byte-identical round trip** on every corpus `.geo`, no edits — including
   the unvalidated `checksum` and `flags`.
2. **Stride arithmetic.** After parsing, the consumed byte count must equal
   `36 + 24×vertex_count + Σ(55 + 16×node_count)`, and must equal the file
   length. Any drift means a face record was mis-sized.
3. **N-gon coverage.** Confirm the corpus contains faces with `node_count > 3`
   and that they triangulate to `node_count − 2` triangles.
4. **UV orientation.** Convert a textured model and compare against the same
   model in game. Upside-down texturing means the §5 flip was missed or applied
   twice.
5. **Vertex splitting.** Convert a model whose faces share a position index with
   differing UVs, and confirm the output has more vertices than the source
   `vertex_count` and correct texturing at the seam.
6. **Non-ASCII tolerance.** Red Odyssey content parses without raising on string
   decode.
