# F7 — Redux HD models: OGRE `.mesh`, `.skeleton`, `.material`

**This document answers `docs/10` Q-B.** Battlezone 98 Redux's HD runtime model
format is **OGRE**: binary `.mesh`, binary `.skeleton`, text `.material`
scripts, and `.dds` textures. It is fully decodable, and the `hd` rung of
`docs/05`'s fidelity chain is therefore reachable rather than aspirational.

Confidence: **VERIFIED** for the chunk layouts — these are the documented OGRE
serializer formats and a complete pure-Python reader/writer implementing them
round-trips real Redux content. **OBSERVED** for the Redux-specific conventions
in §5.

Endianness is declared per file (§2), effectively always little.

## 1. Why this is easier than it looks

OGRE is an open-source engine with a published mesh format. Everything in §§2–4
is public knowledge in the OGRE project, not reverse-engineered from
Battlezone. The Redux-specific parts — which material base classes exist, how
textures are named — are §5, and they are small.

Redux ships mesh serializer version **`[MeshSerializer_v1.100]`**, with
`v1.8` and `v1.41` also accepted by readers. Skeletons are
**`[Serializer_v1.80]`**, with `v1.10` also accepted.

## 2. Chunk framing (both `.mesh` and `.skeleton`)

```
offset  size  type      field
0x00    2     uint16    chunk id
0x02    4     uint32    chunk size
```

**Chunk size includes the 6-byte header.** Chunks nest; a parent's size covers
all of its children.

### File header

The first two bytes are the header chunk id `0x1000`, and **they double as the
endianness marker**: bytes `00 10` mean little-endian, `10 00` mean big-endian.
The header chunk has **no size field** — it is followed immediately by a
newline-terminated version string, e.g. `[MeshSerializer_v1.100]\n`.

Strings in OGRE chunks are **newline-terminated**, not length-prefixed and not
null-terminated. A string's contribution to a chunk size is
`len(string) + 1`.

**Parsing style.** Because chunk order within a parent is not fixed, the working
approach is: read a chunk header, dispatch on the id, and if the id is not one
you expect here, **rewind 6 bytes** and return to the caller. Every reference
reader is built this way. Validate on exit that bytes consumed equal the
declared size.

## 3. `.mesh` chunk ids

```
0x1000  HEADER

0x3000  MESH
0x4000    SUBMESH
0x4010      SUBMESH_OPERATION
0x4100      SUBMESH_BONE_ASSIGNMENT
0x4200      SUBMESH_TEXTURE_ALIAS          (deprecated in OGRE)
0x5000    GEOMETRY
0x5100      GEOMETRY_VERTEX_DECLARATION
0x5110        GEOMETRY_VERTEX_ELEMENT
0x5200      GEOMETRY_VERTEX_BUFFER
0x5210        GEOMETRY_VERTEX_BUFFER_DATA
0x6000    MESH_SKELETON_LINK
0x7000    MESH_BONE_ASSIGNMENT
0x8000    MESH_LOD_LEVEL
0x8100      MESH_LOD_USAGE
0x8110      MESH_LOD_MANUAL
0x8120      MESH_LOD_GENERATED
0x9000    MESH_BOUNDS
0xA000    SUBMESH_NAME_TABLE
0xA100      SUBMESH_NAME_TABLE_ELEMENT
0xB000    EDGE_LISTS
0xB100      EDGE_LIST_LOD
0xB110        EDGE_GROUP
0xC000    POSES
0xC100      POSE
0xC111        POSE_VERTEX
0xD000    ANIMATIONS
0xD100      ANIMATION
0xD105        ANIMATION_BASEINFO
0xD110        ANIMATION_TRACK
0xD111          ANIMATION_MORPH_KEYFRAME
0xD112          ANIMATION_POSE_KEYFRAME
0xD113          ANIMATION_POSE_REF
0xE000    EXTREMES
```

The reference reader implements `MESH`, `GEOMETRY`, `SUBMESH`,
`MESH_SKELETON_LINK`, `MESH_BONE_ASSIGNMENT`, `MESH_BOUNDS`,
`SUBMESH_NAME_TABLE` and partially `EDGE_LISTS`; it raises on `MESH_LOD_LEVEL`,
`POSES`, `ANIMATIONS` and `EXTREMES` as not-yet-needed. **For the editor's
purposes — display a model in a viewport — that same subset is sufficient**,
and unhandled chunks can be skipped by size.

### `MESH` (0x3000) payload

```
bool    skeletally_animated
```

then child chunks.

### `GEOMETRY` (0x5000) payload

```
uint32  vertex_count
```

then `GEOMETRY_VERTEX_DECLARATION` and one or more `GEOMETRY_VERTEX_BUFFER`.

### `GEOMETRY_VERTEX_ELEMENT` (0x5110) payload — 5 × uint16

```
source     which vertex buffer (bind index) this element lives in
type       VertexElementType, §4
semantic   VertexElementSemantic, §4
offset     byte offset within that buffer's vertex
index      semantic index (e.g. UV set number)
```

Chunk size is therefore always `6 + 10 = 16`.

### `GEOMETRY_VERTEX_BUFFER` (0x5200) payload

```
uint16  bind_index
uint16  vertex_size    bytes per vertex in this buffer
```

then one `GEOMETRY_VERTEX_BUFFER_DATA` (0x5210) whose payload is
`vertex_size × vertex_count` raw bytes.

`vertex_size` must equal the sum of element sizes declared for that bind index.
Warn on mismatch; trust the declared `vertex_size` for stride.

### `SUBMESH` (0x4000) payload

```
string  material_name
bool    use_shared_vertices
uint32  index_count
bool    indices_32_bit
raw     index buffer — index_count × (4 if indices_32_bit else 2) bytes
```

then, **only if `use_shared_vertices` is false**, a nested `GEOMETRY` chunk with
this submesh's own vertices; then optional `SUBMESH_OPERATION`,
`SUBMESH_BONE_ASSIGNMENT` and `SUBMESH_TEXTURE_ALIAS` chunks.

### `SUBMESH_OPERATION` (0x4010)

`uint16 operation_type`. Values 1–6 are POINT_LIST, LINE_LIST, LINE_STRIP,
TRIANGLE_LIST, TRIANGLE_STRIP, TRIANGLE_FAN; 7–0x26 are patch control-point
counts; bit 6 (`0x40`) set means the adjacency variant. Redux content is
TRIANGLE_LIST (4). Chunk size is `6 + 2 = 8`.

### Bone assignment chunks (0x4100, 0x7000)

```
uint32   vertex_index
uint16   bone_index
float32  weight
```

Chunk size `6 + 10 = 16`. `MESH_BONE_ASSIGNMENT` targets shared vertex data;
`SUBMESH_BONE_ASSIGNMENT` targets that submesh's own vertices.

### `MESH_SKELETON_LINK` (0x6000)

`string skeleton_name` — the companion `.skeleton` file.

### `MESH_BOUNDS` (0x9000)

Seven float32: `min_x, min_y, min_z, max_x, max_y, max_z, bound_radius`.
Chunk size `6 + 28 = 34`.

### `SUBMESH_NAME_TABLE` (0xA000)

Children `SUBMESH_NAME_TABLE_ELEMENT` (0xA100), each `uint16 index` followed by
`string name`. This is how submeshes get human-readable names.

## 4. Vertex element enumerations

**VertexElementSemantic:**

```
0x01 POSITION            0x06 COLOUR2
0x02 BLEND_WEIGHTS       0x07 TEXTURE_COORDINATES
0x03 BLEND_INDICES       0x08 BINORMAL
0x04 NORMAL              0x09 TANGENT
0x05 COLOUR
```

**VertexElementType** — value, and byte size:

```
0x00 FLOAT1   4     0x0C DOUBLE1   8     0x14 INT1     4     0x1C BYTE4        4
0x01 FLOAT2   8     0x0D DOUBLE2  16     0x15 INT2     8     0x1D BYTE4_NORM   4
0x02 FLOAT3  12     0x0E DOUBLE3  24     0x16 INT3    12     0x1E UBYTE4_NORM  4
0x03 FLOAT4  16     0x0F DOUBLE4  32     0x17 INT4    16     0x1F SHORT2_NORM  4
0x04 COLOUR   4     0x10 USHORT1   2     0x18 UINT1    4     0x20 SHORT4_NORM  8
0x05 SHORT1   2     0x11 USHORT2   4     0x19 UINT2    8     0x21 USHORT2_NORM 4
0x06 SHORT2   4     0x12 USHORT3   6     0x1A UINT3   12     0x22 USHORT4_NORM 8
0x07 SHORT3   6     0x13 USHORT4   8     0x1B UINT4   16
0x08 SHORT4   8     0x09 UBYTE4    4
0x0A COLOUR_ARGB 4  0x0B COLOUR_ABGR 4
```

`COLOUR`, `COLOUR_ARGB` and `COLOUR_ABGR` are deprecated in OGRE in favour of
`UBYTE4_NORM`; `SHORT1`, `SHORT3`, `USHORT1` and `USHORT3` are deprecated
outright for alignment reasons. Redux content uses the FLOAT types plus a colour
type; the full table is here so an unexpected type does not stop a parse.

**Observed Redux vertex content: position, normal, colour, UV** — which maps
directly onto glTF with no reinterpretation. That is what makes the `hd` rung
cheap once the chunk reader exists.

## 5. `.skeleton` chunk ids

```
0x1000  SKELETON_HEADER
0x1010  SKELETON_BLENDMODE
0x2000  SKELETON_BONE
0x3000  SKELETON_BONE_PARENT
0x4000  SKELETON_ANIMATION
0x4010    SKELETON_ANIMATION_BASEINFO
0x4100    SKELETON_ANIMATION_TRACK
0x4110      SKELETON_ANIMATION_TRACK_KEYFRAME
0x5000  SKELETON_ANIMATION_LINK
```

`SKELETON_BLENDMODE`: `uint16` — 0 = weighted average, 1 = weighted cumulative.
Written only for `v1.80`.

**`SKELETON_BONE` (0x2000)** payload:

```
string     name
uint16     handle
vector3    position
quaternion orientation
vector3    scale        — PRESENT ONLY IF the chunk is larger than the
                          no-scale size
```

Two traps here, both **VERIFIED**:

- **The bone's name is excluded from the declared chunk size.** The chunk size
  field counts header + handle + position + orientation (+ scale), and *not* the
  name string. This is a genuine quirk of the format, not a bug in a reader.
  Any size-validation pass must exclude the name's bytes or every bone will
  appear malformed.
- **Scale is optional and detected by size.** A bone with unit scale omits the
  vector entirely. Detect by comparing the declared chunk size against
  `6 + 2 + 12 + 16 = 36`; larger means a scale follows. Writers omit scale when
  it is exactly `(1, 1, 1)`.

**`SKELETON_BONE_PARENT` (0x3000)**: `uint16 bone_handle`, `uint16
parent_handle`. Chunk size `6 + 4 = 10`. Only non-root bones get one.

**`SKELETON_ANIMATION` (0x4000)**: `string name`, `float32 duration`, then an
optional `SKELETON_ANIMATION_BASEINFO` (`string base_animation_name`,
`float32 base_keyframe_time`), then `SKELETON_ANIMATION_TRACK` children.
Unlike bone names, the animation name **is** included in this chunk's size.

**`SKELETON_ANIMATION_TRACK` (0x4100)**: `uint16 target_bone_handle`, then
keyframe children.

**`SKELETON_ANIMATION_TRACK_KEYFRAME` (0x4110)**:

```
float32     time
quaternion  rotation
vector3     translation
vector3     scale        — optional, same size-detection rule as bones
```

No-scale size is `6 + 4 + 16 + 12 = 38`.

**`SKELETON_ANIMATION_LINK` (0x5000)**: `string skeleton_name`,
`float32 scale`.

### Coordinate convention in OGRE chunks

OGRE vectors in these files are read as **left/up/front with the left component
negated** to reach the right/up/front model frame used everywhere else
(F8 §1), and quaternions are stored **`(x, y, z, w)` with x negated** — note
this is the *opposite* component order from BWD2 `ANIM` quaternions (F5 §9),
which are `(w, x, y, z)`. Getting these two mixed up is an easy and
hard-to-diagnose error; keep the two readers' conversions separate and named.

## 6. `.material` — Redux's material script convention

Text, OGRE material script syntax. The Redux convention observed in ported
content:

```
import * from "BZBase.material"

material <MaterialName> : <BaseMaterial>
{
    set_texture_alias DiffuseMap   <texture>_D.dds
    set_texture_alias NormalMap    flat_N.dds
    set_texture_alias SpecularMap  black.dds
    set_texture_alias EmissiveMap  black.dds

    set $diffuse   "1 1 1"
    set $ambient   "1 1 1"
    set $specular  ".7 .7 .7"
    set $shininess "127"
    set $glow      "1 1 1"
}
```

- Every material derives from a base defined in **`BZBase.material`**, which
  ships with the game. Observed base names: **`BZBase`** for exterior geometry
  and **`BZBaseCockpit`** for cockpit geometry.
- Four texture aliases: **`DiffuseMap`, `NormalMap`, `SpecularMap`,
  `EmissiveMap`**. Defaults for the three non-diffuse maps are the shipped
  neutral textures `flat_N.dds`, `black.dds`, `black.dds`.
- **Texture naming: `<basename>_D.dds`** for the diffuse map, with `_N`, `_S`
  and `_E` following the same pattern for normal, specular and emissive. This is
  the naming rule to use when hunting a texture for an HD model.
- Five scalar/vector parameters: `$diffuse`, `$ambient`, `$specular`,
  `$shininess`, `$glow`.

For the editor this is a **read** concern: given a submesh's `material_name`
(§3), find the material script, resolve `DiffuseMap` to a `.dds`, load it. The
editor never writes `.material`.

## 7. Asset discovery

To inventory a Redux install for the editor's asset index (`docs/05` §2,
`docs/10` Q-A), the extension set that matters is:

```
.odf .geo .vdf .sdf .map .act .mesh .skeleton .material .dds
```

Classic and HD assets coexist; a class may have both a `.sdf`/`.geo` chain and
an OGRE `.mesh`, which is exactly what makes `docs/05`'s fidelity chain a chain
rather than a choice.

## 8. Acceptance tests

1. **Byte-identical round trip** on a sample of Redux `.mesh` and `.skeleton`
   files, no edits.
2. **Chunk-size closure** on every chunk — with the bone-name exclusion of §5
   correctly applied, and unhandled chunks skipped by size rather than by
   guesswork.
3. **Vertex stride.** Declared `vertex_size` equals the sum of element sizes for
   that bind index, for every buffer in the corpus.
4. **Optional scale detection.** Parse a skeleton containing both scaled and
   unscaled bones and confirm both come back correctly; a reader that always
   expects scale desyncs on the first unscaled bone.
5. **Visual.** Convert one HD craft to `.glb`, load it in the viewport, and
   compare against the same craft in game — silhouette, orientation, and
   texturing. This is what promotes the `hd` rung from "format identified" to
   "working".
6. **Quaternion convention.** Play a skeletal animation and confirm limbs rotate
   about the correct axes — the §5 caveat's failure mode.
