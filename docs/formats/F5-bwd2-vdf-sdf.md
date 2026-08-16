# F5 — `.vdf` / `.sdf` BWD2 model containers

Little-endian. A `.vdf` (vehicle) or `.sdf` (structure) is a chunk container
that describes a model's **node hierarchy** — which `.geo` meshes make up the
object, how they are placed and parented, what each node *is*, and how it
animates. It contains no geometry itself; nodes name `.geo` files (F4).

Confidence: **VERIFIED** unless noted — two implementations from independent
lineages agree on the layouts, and their declared chunk sizes agree with the
field arithmetic. Where the two disagree, both readings are recorded (§6, §7.2).

## 1. Chunk framing

```
offset  size  type      field
0x00    4     char[4]   chunk name, null-padded
0x04    4     int32     chunk size
```

**The size includes the 8-byte header.** To skip a chunk, seek to
`chunk_start + chunk_size`. An empty chunk has size 8.

Chunk names seen: `BWD2`, `REV\0`, `VDFC`, `SDFC`, `VGEO`, `SGEO`, `ANIM`,
`VCHK`, `COLP`, `SPCS`, `EXIT`.

## 2. File preamble

Both formats start identically:

```
BWD2   size 8    (marker only, no payload)
REV\0  size 12   payload: uint32 revision
```

`REV` is written with a trailing null inside its 4-byte name field — match on
the first three characters, or on the 4 bytes `REV\0`, not on `"REV"` decoded
loosely.

Revision values: **VDF = 7, SDF = 8**.

Redux **ignores** the revision entirely. Battlezone 1.5 hard-errors with
`Bad BWD revision for file %s` on a mismatch. So: read it, preserve it, do not
gate on it, and do not "helpfully" bump it.

## 3. Chunk order

**VDF:**

```
BWD2, REV, VDFC, EXIT, VGEO, [ANIM], [VCHK], EXIT, EXIT, [COLP], EXIT, [SPCS], EXIT
```

**SDF:**

```
BWD2, REV, SDFC, SGEO, [ANIM], EXIT, EXIT, EXIT
```

Bracketed chunks are optional. Note the asymmetry: VDF has an `EXIT` between
`VDFC` and `VGEO`; SDF does **not** have one between `SDFC` and `SGEO`.

`EXIT` chunks are separators with no payload, and **the number of consecutive
ones is not fixed** — a reference reader tolerates runs of up to three in
several positions with an explicit note that the acceptable count is unknown.
Parse by dispatching on chunk name in a loop and skipping any `EXIT`, rather
than by asserting a fixed sequence. Preserve the original count on rewrite.

`VCHK` appears in no stock VDF and its contents are unknown. Skip it by size and
preserve it verbatim.

## 4. `VDFC` — vehicle data chunk (size 68)

```
offset  size  type      field
0x08    16    char[16]  name
0x18    4     uint32    entity_class
0x1C    4     uint32    vehicle_size
0x20    20    5×float   lod_distances       LOD1..LOD5 switch distances
0x34    4     float32   mass                observed default 1750.0
0x38    4     float32   collision_multiplier
0x3C    4     float32   drag_coefficient    observed default 0.0008
0x40    4     uint32    hardpoint_count     unused
```

`entity_class`, `vehicle_size`, `lod_distances` and `hardpoint_count` are
annotated "unused?" in the reference; nothing observed depends on them.
Preserve verbatim.

## 5. `SDFC` — structure data chunk (size 78)

```
offset  size  type      field
0x08    16    char[16]  name
0x18    4     uint32    structure_class
0x1C    20    5×float   lod_distances
0x30    4     uint32    ddr                 "defensive" in one lineage; type unclear
0x34    13    char[13]  death_animation     explosion effect name
0x41    13    char[13]  death_audio         explosion sound name
```

## 6. `VGEO` / `SGEO` — the node table

```
offset  size  type      field
0x08    4     uint32    object_count
0x0C    …               node records
```

Records follow in **nested slot order** — LOD outermost, then representation,
then object index:

```
for lod in 0 .. LOD_COUNT-1:
    for rep in 0 .. REP_COUNT-1:
        for index in 0 .. object_count-1:
            one record
```

| | LOD_COUNT | REP_COUNT | slots per object index | record size |
|---|---|---|---|---|
| VDF (`VGEO`) | 7 | 4 | **28** | **100 bytes** |
| SDF (`SGEO`) | 3 | 2 | **6** | **120 bytes** |

Named LOD slots (VDF): `0 = primary`, `1 = cockpit`, `2 = lowpoly`; 3–6 unused.
`REP 0` is primary; 1–3 unused. SDF: `LOD 0` primary, 1–2 unused; `REP 0`
primary, 1 unused. Every unused slot is present in the file as a full record
with the name `NULL` — **the table is dense, not sparse.** Total record count is
always `LOD_COUNT × REP_COUNT × object_count`.

### Record layout — common part (100 bytes, both formats)

```
offset  size  type      field
0x00    8     char[8]   name              "NULL" for an empty slot
0x08    48    12×float  transform         right/up/front basis + position (F8 §1)
0x38    8     char[8]   parent_name       "World" or "NULL" for a root node
0x40    12    3×float   centre_position   bounding-sphere centre
0x4C    4     float32   radius            bounding-sphere radius
0x50    12    3×float   half_size         bounding-box half extents
0x5C    4     uint32    class_id          §8
0x60    4     uint32    object_flags
                        ─────
                        100 bytes
```

### SGEO-only tail (20 further bytes, SDF only)

```
0x64    4     uint32    ddr               purpose unknown
0x68    12    3×float   target            for a spinner node: angular velocity ÷ 2π
0x74    4     float32   time              purpose unknown
                        ─────
                        120 bytes total
```

### The 100-vs-120 trap, resolved

Earlier notes in this project described VDF records as "100-byte stride with a
20-byte overlapping tail". That framing came from one reference lineage, which
reads a `ddr`/`target`/`time` tail on every VDF record and then seeks **backward
20 bytes**, so those fields alias the start of the following record.

**The correct statement: the VDF record is 100 bytes and has no
`ddr`/`target`/`time` fields.** This is VERIFIED two ways — the second,
independent lineage reads a flat 100 bytes with no seek-back, and the first
lineage's *own* chunk-size computation is `8 + 4 + 100 × 28 × object_count`,
which only closes if the stride is 100.

Two things follow:

- **A 120-byte-stride VDF reader desyncs**, as previously recorded. Still true.
- The first lineage's write path patches optional trailing values into the first
  20 bytes of the *next* record. Do not reproduce that. It is a compatibility
  hack for something undocumented, and on a normal file it corrupts a node's
  name and transform.

A VDF `VGEO` chunk may carry **up to 20 bytes after the final record**; the
declared chunk size accounts for them. Purpose unknown — **OBSERVED**. Trust the
chunk size, preserve any trailing bytes verbatim, and do not synthesise them.

### Node semantics

- `name` is the **`.geo` filename without extension**, resolved case-insensitively
  in the model's own directory first (this matters on Linux; stock content is
  inconsistently cased).
- A node is a **root** if `parent_name` is `World`, `NULL`, or names a node that
  does not exist in the table. All three occur.
- **LOD parent fallback:** a node in a lower LOD band whose parent is not found
  can have its parent resolved by substituting `'1'` at character index 3 of the
  parent name — the LOD-band digit embedded in the naming convention. This is
  **OBSERVED** in both lineages as a heuristic for cross-LOD parenting; use it
  as a fallback only, after an exact lookup fails.
- **Names are not unique.** The same node name appears across LOD bands, and
  both lineages note that name→node lookup is ambiguous when duplicated. Resolve
  parents **within the same (lod, rep) band first**, and only then fall back.
- **Scale is baked into the basis vectors.** To recover it, take the length of
  each of the three basis columns; normalise the columns to get pure rotation.
  A node with non-unit basis columns is scaled, and dropping that scale is a
  round-trip data loss the reference explicitly had to fix once.

## 7. Optional chunks

### 7.1 `SPCS` (size 20)

Three uint32 values. Purpose unknown. One lineage writes the chunk name as
`SCPS` rather than `SPCS` — **transposed letters, and they are not the same
chunk name on disk.** Match what the file actually contains; preserve it.

### 7.2 `COLP` — collision planes (size 56)

Twelve float32 values, VDF only. These are physics collision bounds, **not**
ordnance collision.

The two lineages name them differently, and the difference is not cosmetic:

| slot | lineage A naming | lineage B naming |
|---|---|---|
| 0 | front | Y max outer |
| 1 | front_middle | Y max inner |
| 2 | back_middle | Y min inner |
| 3 | back | Y min outer |
| 4 | right | X max outer |
| 5 | right_middle | X max inner |
| 6 | left_middle | X min inner |
| 7 | left | X min outer |
| 8 | top | Z max outer |
| 9 | top_middle | Z max inner |
| 10 | bottom_middle | Z min inner |
| 11 | bottom | Z min outer |

Both agree on the **shape**: three groups of four, each group being
`outer_max, inner_max, inner_min, outer_min` along one axis — i.e. a nested
outer/inner box pair. They disagree on **which axis comes first**: lineage A
reads the first group as front/back (depth), lineage B as Y (height).

**UNRESOLVED — flagged, not guessed.** Resolve it empirically: read a `.vdf`
whose object has an obviously non-cubic silhouette (something much taller than
it is wide, or much longer than it is tall), draw both boxes, and see which
matches the `half_size` in its `VGEO` record. Write the answer into the
generator repo's open questions.

A truncated or missing `COLP` occurs in real files; treat it as an empty
collision box rather than an error.

## 8. Geometry node class IDs

`class_id` in each node record. Known values:

```
0x00 NONE                 0x33 ORDNANCE
0x01 HELICOPTER           0x34 EXPLOSION
0x02 STRUCTURE1           0x35 CHUNK
0x03 POWERUP              0x36 SORT_OBJECT
0x04 PERSON               0x37 NONCOLLIDABLE
0x05 SIGN                 0x3C VEHICLE_GEOMETRY
0x06 VEHICLE              0x3D STRUCTURE_GEOMETRY
0x07 SCRAP                0x3F WEAPON_GEOMETRY
0x08 BRIDGE               0x40 ORDNANCE_GEOMETRY
0x09 FLOOR                0x41 TURRET_GEOMETRY
0x0A STRUCTURE2           0x42 ROTOR_GEOMETRY
0x0B SCROUNGE             0x43 NACELLE_GEOMETRY
0x0F SPINNER              0x44 FIN_GEOMETRY
0x26 HEADLIGHT_MASK       0x45 COCKPIT_GEOMETRY
0x28 EYEPOINT             0x46 WEAPON_HARDPOINT
0x2A COM                  0x47 CANNON_HARDPOINT
0x32 WEAPON               0x48 ROCKET_HARDPOINT
                          0x49 MORTAR_HARDPOINT
                          0x4A SPECIAL_HARDPOINT
                          0x4B FLAME_EMITTER
                          0x4C SMOKE_EMITTER
                          0x4D DUST_EMITTER
                          0x51 PARKING_LOT
```

Values in the gaps (0x0C–0x0E, 0x10–0x25, 0x27, 0x29, 0x2B–0x31, 0x38–0x3B,
0x3E, 0x4E–0x50, 0x52–0x53) exist in the engine's enumeration but are unused,
vehicle-cockpit-instrument leftovers from an earlier Activision title, or
otherwise never observed in Battlezone content. `0x22 RADAR` is noted as being
used by exactly one unit (the Czar). Do not treat an unknown class ID as an
error; carry it through.

A separate editing tool exposes a full set of 82 GEO type labels (0–81) in its
UI; the subset above is the part any reference implementation acts on.

### The non-rendering set — this one has a visible consequence

These class IDs are **gizmos, not geometry**, and must be **excluded from any
mesh a converter emits**:

```
0x26 HEADLIGHT_MASK
0x28 EYEPOINT
0x46 WEAPON_HARDPOINT
0x47 CANNON_HARDPOINT
0x48 ROCKET_HARDPOINT
0x49 MORTAR_HARDPOINT
0x4A SPECIAL_HARDPOINT
0x4B FLAME_EMITTER
0x4C SMOKE_EMITTER
0x4D DUST_EMITTER
```

Emit them and every craft in the object palette grows visible boxes where its
guns, eyepoint and exhaust should be. Keep their **transforms** — hardpoint
positions are genuinely useful metadata — but do not emit their meshes.

Hardpoints specifically (0x46–0x4A) are the five weapon mount types and are
worth surfacing as named attachment points.

## 9. `ANIM` — animation chunk

Fixed part, 72 bytes including the chunk header:

```
offset  size  type      field
0x08    16    char[16]  name
0x18    4     uint32    animation_count
0x1C    4     uint32    mesh_count
0x20    4     uint32    orientation_keyframe_count
0x24    4     uint32    scale_keyframe_count
0x28    4     uint32    position_keyframe_count
0x2C    28    7×uint32  runtime scratch: anim_ptr, mesh_ptr, orientation_ptr,
                        scale_ptr, position_ptr, obj, entity
```

The seven trailing values are **runtime pointers baked into the save** and are
meaningless on disk. Preserve verbatim; never interpret.

Five arrays follow, in this order:

**Animation records** — `animation_count × 148 bytes`:

```
0x00    4     uint32    index          how the game selects this animation
0x04    128   32×uint32 mesh_index_list  purpose unknown
0x84    4     uint32    start          first frame on the timeline
0x88    4     int32     length         signed; negative = reversed playback
0x8C    4     uint32    loop           0 = infinite, n ≥ 1 = play n times
0x90    4     float32   speed          frames per second
```

Duration in seconds is `(abs(length) − 1) / speed`.

**Animation mesh records** — `mesh_count × 132 bytes`:

```
0x00    8     char[8]   name              matches a VGEO/SGEO node name
0x08    4     uint32    flags
0x0C    48    12×float  inverse_transform
0x3C    48    12×float  frame_transform
0x6C    4     uint32    orientation_start
0x70    4     uint32    orientation_length
0x74    4     uint32    scale_start
0x78    4     uint32    scale_length
0x7C    4     uint32    position_start
0x80    4     uint32    position_length
```

The six start/length pairs are **slices into the three flat keyframe arrays
below** — a mesh's keyframes are `array[start : start + length]`. Keyframes
within a slice are **not guaranteed to be frame-ordered**; sort by frame before
use.

**Orientation keyframes** — `orientation_keyframe_count × 20 bytes`:
`uint32 frame`, then a quaternion as **4×float32 in `(w, x, y, z)` order**.

**Scale keyframes** — `scale_keyframe_count × 16 bytes`:
`uint32 frame`, then `3×float32`.

**Position keyframes** — `position_keyframe_count × 16 bytes`:
`uint32 frame`, then `3×float32`.

**Quaternion component order caveat.** One lineage reads `(w, x, y, z)`
consistently and is self-coherent; the other reassembles keyframe quaternions by
shuffling components in a way that is internally inconsistent with its own
declared layout. `(w, x, y, z)` is the reading to implement — **OBSERVED** —
and the check is visual: play an animation and see whether the part rotates
about the axis it should.

**Chunk-size self-check.** The reference validates that the bytes consumed by an
`ANIM` chunk equal its declared size, and warns when they do not. Do that too;
it catches every count/stride mistake in this section at parse time.

## 10. What is not known

- `VCHK` contents entirely.
- `SPCS` three values.
- `object_flags` per-bit meaning.
- `ddr` (both the `SDFC` scalar and the `SGEO` per-node one).
- `time` in `SGEO` records — the reference speculates it is a leftover from an
  earlier Activision title.
- `mesh_index_list` (32 uint32s) in animation records.
- The upper `flags` bits everywhere.

None of these block reading, converting or displaying a model. All of them must
be preserved byte-for-byte on rewrite.

## 11. Acceptance tests

1. **Byte-identical round trip** on every corpus `.vdf` and `.sdf`, no edits —
   including `EXIT` runs, `VCHK`, `SPCS`, and any trailing `VGEO` bytes.
2. **Chunk-size closure.** For every chunk, bytes consumed equals declared size.
   For `VGEO`: `size == 12 + 100 × 28 × object_count + trailing`, with
   `0 ≤ trailing ≤ 20`. For `SGEO`: `size == 12 + 120 × 6 × object_count`
   exactly. This is the test that catches a 120-byte VDF reader immediately.
3. **Dense slot table.** Parsed record count equals
   `LOD_COUNT × REP_COUNT × object_count`, and `NULL`-named slots are present
   rather than skipped.
4. **Gizmo exclusion.** Convert a weapon-carrying craft and confirm the output
   mesh contains no geometry at hardpoint, eyepoint, headlight-mask or emitter
   node positions — while their transforms survive as named attachment points.
5. **Scale preservation.** Round trip a model with non-unit basis columns and
   confirm the column lengths come back unchanged.
6. **Parenting.** Reconstruct the node hierarchy of a multi-LOD model and confirm
   no node is silently reparented across LOD bands by the §6 fallback when an
   exact same-band parent existed.
