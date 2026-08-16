# F8 — Cross-format conventions, enumerations, and acceptance vectors

The things that are true across more than one format, collected so they are
stated once. Confidence: **VERIFIED** unless noted.

## 1. Coordinate frames

### Model space

**x = right, y = up, z = front.** Right-handed. Used by `.geo` vertices, BWD2
node transforms, and BWD2 animation keyframes.

### Transform layout — 12 floats

Wherever a 12-float transform appears — BWD2 node records (F5 §6), BWD2
animation mesh transforms (F5 §9), and BZN `transform` blocks (F3 §2.2) — the
order is the same:

```
right_x  right_y  right_z      basis column 1
up_x     up_y     up_z         basis column 2
front_x  front_y  front_z      basis column 3
posit_x  posit_y  posit_z      translation
```

**Scale is baked into the basis column lengths.** Recover it as the length of
each column; normalise the columns to get pure rotation. This applies to model
node transforms; BZN object transforms are observed to be pure rotations.

The BZN `transform` block using the same right/up/front convention as model
space is not a coincidence — it is the same engine type serialised two ways, and
it means an object's world orientation and a model node's local orientation
compose without a frame change.

### Quaternion component order — differs by format, deliberately noted

| Where | Order on disk |
|---|---|
| BWD2 `ANIM` orientation keyframes (F5 §9) | `(w, x, y, z)` |
| OGRE `.mesh` / `.skeleton` (F7 §5) | `(x, y, z, w)`, with x negated on read |

These are genuinely different. Keep the two conversions in separately named
routines and never share one helper between them.

### Terrain space vs world space

Terrain samples are indexed `(x, z)` on a grid with 5 m spacing (F1 §2); object
positions are metres in BZN world coordinates, offset from the display frame by
the `.trn`'s `MinX` / `Height` / `MinZ` (F3 §2.4). These are **not** the same
frame. The uniform rule, both directions, all three axes:

```
display = stored − offset
stored  = display + offset
```

## 2. Constants

| Quantity | Value |
|---|---|
| Zone edge, metres | 1280 |
| Zone edge, height samples | 256 (`2 ** zone_bits`, `zone_bits = 8`) |
| Height sample spacing | 5 m |
| Zone edge, material tiles | 64 |
| Material tiles per zone | 4096 |
| Material tile edge | 20 m |
| Height cells per material tile | 4 × 4 |
| Height storage unit | decimetres (raw ÷ 10 = metres) |
| Height field width | 13 bits (0–8191 raw, 0–819.1 m) |
| Editor authoring height clamp | 0–409.5 m (convention, not a format limit) |
| Maximum observed map | 4 × 4 zones = 5120 m |
| Map resize granularity | 1280 m (one zone) |

Map resizing moves in whole zones. A resize must rescale **terrain, materials,
objects, and paths together**; changing terrain alone leaves every object
misplaced and every material tile orphaned.

## 3. Zone interleaving

`.hg2` and `.mat` both store their grids **zone by zone**, not row-major across
the map. The scheme is identical; only the per-zone edge length differs
(256 vs 64). Full statement and inverse in F1 §4; `.mat` specifics in F2 §3.

This is the single highest-value thing in this specification set to get right,
because **it is invisible on a 1×1 map**. Every test that touches storage order
must run on a map of at least 2×2 zones.

## 4. ODF `classLabel` → model file type

An object's ODF names its class; the class determines whether its model is a
`.vdf` (vehicle-shaped) or `.sdf` (structure-shaped) container, and the model
file's base name comes from the ODF's `baseName`.

From `[GameObjectClass]`:

```
classLabel   the class name — decides .vdf vs .sdf below
baseName     the model file's base name; defaults to the ODF's own stem
nation       nation string; defaults to the ODF stem's first character
```

Values are quote-stripped; keys are matched case-insensitively.

**Vehicle types (`.vdf`):**

```
apc, hover, howitzer, minelayer, sav, scavenger, tug, turrettank, walker,
wingman, armory, constructionrig, factory, producer, recycler, turret,
person, ammopack, camerapod, daywrecker, powerup, repairkit, dropoff,
torpedo, wpnpower
```

**Building types (`.sdf`):**

```
animbuilding, artifact, barracks, commtower, geyser, i76building,
i76building2, portal, powerplant, repairdepot, scrapfield, scrapsilo,
shieldtower, supplydepot, flare, i76sign, magnet, proximity, spawnpnt,
spraybomb, weaponmine, scrap
```

**OBSERVED.** This list comes from one working tool and is not guaranteed
exhaustive — BZP and workshop content can introduce class labels not in it. An
unrecognised `classLabel` is a "try `.vdf`, then `.sdf`, then proxy" case, not an
error, and is worth logging so the list can grow.

Note that several classes here are **not** what their name suggests for model
purposes: `turret`, `armory`, `factory`, `recycler` and `producer` are buildings
in gameplay terms but carry vehicle-shaped models, and `person` is a vehicle
type. Do not re-derive this list from intuition about what is a building.

Three classes also change model-conversion behaviour:

- `person` → flag as a person (skeletal animation, scope handling).
- `turret`, `turrettank`, `howitzer` → flag as a turret.
- everything else → neither.

## 5. `.geo` name resolution (all formats)

Model and texture names are stored **without paths and without extensions**
(F4 §3, F5 §6, F6 §5). Resolve every one of them:

1. exact match in the referencing file's own directory;
2. case-insensitive walk of that directory tree;
3. configured asset search paths.

Case-insensitivity is mandatory on Linux and non-negotiable — stock content
mixes cases freely.

## 6. String handling

| Format | String style |
|---|---|
| `.geo`, BWD2 (`.vdf`/`.sdf`) | fixed-length, null-padded; read to first null |
| OGRE `.mesh`/`.skeleton` | newline-terminated, variable length |
| `.trn`, ASCII `.bzn`, `.material` | text lines |

Decode fixed-length fields as ASCII **tolerating and discarding non-ASCII
bytes**. Red Odyssey content contains them and a strict decoder raises on those
files — a real, reported failure, not a hypothetical.

For fixed-length fields, the reference tooling decodes as `latin-1` in one
lineage and as ASCII-with-errors-ignored in the other. Either works for
round-tripping as long as the **write** path pads back to the same fixed length
with nulls. Prefer preserving raw bytes over any decode when round-trip fidelity
matters.

## 7. Preserve-verbatim register

Fields with no known semantics that must survive a round trip byte-for-byte.
Writing a "sensible" zero into any of these is silent data loss with unknown
consequences.

| Format | Field |
|---|---|
| `.hg2` | `structure_version`, `map_version`, **per-height-word flag bits (upper 3)** |
| `.mat` | — (every nibble has meaning) |
| `.trn` | every key the editor does not understand; whole-file line preservation |
| `.bzn` | `obj_addr`, `what`, `where`, `state`, `undefptr`, `undefraw`, `undeffloat`, `undefbool`, `old_ptr`, `pathType`, the whole physics block |
| `.geo` | `checksum`, `flags` |
| BWD2 | `entity_class`, `vehicle_size`, `lod_distances`, `hardpoint_count`, `object_flags`, `ddr` (both), `time`, `VCHK` payload, `SPCS` values, `ANIM`'s 7 runtime pointers, `mesh_index_list`, `EXIT` chunk counts, `VGEO` trailing bytes |
| `.map` | header `unknown` |

## 8. A verification tool worth knowing about

The game can emit a **recorded-game text dump** of live object state. Its
per-object record carries, in order:

```
header, handle, odf_file, unit_name, team_number,
posit_x, posit_y, posit_z,
right_x, right_y, right_z,
up_x, up_y, up_z,
front_x, front_y, front_z,
hull, ammo, timestamp, time_attacked,
who_shot_me, who_shot_me_team, is_deployed, footer
```

with separate record types for destroyed objects (`handle`,
`time_destroyed`), per-team info (`team_number`, `scrap`, `pilots`,
`player_target`, `time`), and player info (`player_name`, `player_team`).

**Why this matters:** it is a ground-truth readout of object positions and
orientations *in the running game*, in the same right/up/front convention as
§1. It is the cleanest available way to settle any remaining question about the
BZN coordinate frame or the `.trn` offsets — place an object in the editor, load
the map, dump, and compare numbers. Nothing else in this specification set
gives you the engine's own answer.

## 9. Cross-format acceptance checklist

Beyond the per-format tests in F1–F7, these are the checks that only fail when
two formats disagree:

1. **Companion dimension agreement.** `.hg2` zone count × 1280 equals `.trn`
   `Width`/`Depth` in metres, and `.mat` length equals `2 × 4096 × zones`.
   Enforce on load; refuse rather than guess.
2. **Object-on-terrain sanity.** Every object's BZN position, after applying the
   `.trn` offsets, falls inside the terrain extent, and its height is within a
   plausible distance of the sampled terrain height at that `(x, z)`. Objects
   far below terrain are the classic symptom of a zone-interleave bug in the
   height reader — the terrain is right in aggregate and wrong per-cell.
3. **Full map round trip.** Load `.hg2` + `.trn` + `.mat` + `.bzn`, write all
   four back with no edits, and diff. All four byte-identical.
4. **Multi-zone edit isolation.** On a 2×2-or-larger map, make one small edit of
   each kind (one height cell, one material tile, one object move) and confirm
   the diff touches only the expected bytes.
5. **Non-zero TRN offsets.** The whole pipeline round-trips a map with non-zero
   `MinX`, `MinZ` and `Height`. See F3 §2.4 — this is where the reference
   implementation is known to be wrong, so it is where a from-spec
   implementation should be *better*, not bug-compatible.
6. **In-game load.** The end of the chain: a round-tripped map loads in
   Battlezone 98 Redux and its objects are where the editor showed them. Verify
   placement, not counts; measure features rather than eyeballing them.

## 10. When a spec is wrong

These documents were written from reference implementations, not from the
engine. Where reality disagrees with them, **reality wins**.

- A **format** correction belongs in the generator repo — in `bzmap`, with a
  round-trip test that would have caught it, and a note in that repo's
  `docs/09-open-questions.md`. Then correct the relevant F-doc here.
- Never paper over a format bug with a compensating correction in editor code
  (`AGENTS.md` rule 2).
- The claims most likely to need correcting, ranked: the `.mat` orientation sign
  and diagonal mirror remap (F2 §2), the `COLP` axis order (F5 §7.2), the `.mat`
  zone interleave (F2 §3), the `0.825` atlas UVs (F2 §4), and the `classLabel`
  lists (§4). Each is marked in place; none of them blocks building.
