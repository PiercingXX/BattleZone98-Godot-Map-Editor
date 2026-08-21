# F2 — `.mat` terrain material tilemap

The `.mat` file assigns one atlas tile, with an orientation, to every 20 m
terrain tile. Confidence: **VERIFIED** unless a line says otherwise.

## 1. File layout

There is **no header**. The file is a bare array of 2-byte tile words and
nothing else.

```
tiles_per_zone_edge = 64
tiles_per_zone      = 4096
tile_count          = map_width * map_depth * 4096
file_size           = 2 * tile_count
```

`map_width` and `map_depth` come from the companion `.hg2` (F1 §1). A `.mat`
whose size does not match the `.hg2`'s zone count belongs to a different map;
this is the standard failure when a user resizes terrain without regenerating
materials, and it must be an explicit, refused operation rather than a partial
read. (The reference editor guards this with a deliberately obnoxious
four-click confirmation. The guard is right; the four clicks are optional.)

**Resolution:** a zone is 1280 m across and 64 tiles across, so **one tile is
20 m square**. Terrain height samples are 5 m apart (F1 §2), so each material
tile spans a 4×4 block of height cells. The two grids are not the same grid and
must not be indexed with the same arithmetic.

## 2. Tile word

Two bytes, **big-endian nibble order as written** — i.e. treat the pair as
`byte0, byte1` and split each into high and low nibbles:

```
byte0 high nibble  bits 4..7 of byte0   orientation  (rotation + diagonal flag)
byte0 low  nibble  bits 0..3 of byte0   variant
byte1 high nibble  bits 4..7 of byte1   base material
byte1 low  nibble  bits 0..3 of byte1   transition material
```

This is **VERIFIED** — an independent read path and write path in the reference
tooling agree, and the write path packs it explicitly as two bytes in this
order.

It also **corrects the generator repo's inferred layout** (open question E3),
which had it as `[matA:4][matB:4][variant:4][0:4]` with a nibble assumed to be
always zero. There is no always-zero nibble. The nibble that looked like padding
is orientation data, and the field order is orientation/variant first, materials
second.

### Field semantics

- **base** and **transition** are material indices into the world's material
  list, 0..15.
- **base == transition** → the tile is a **solid**: one material, no edge.
- **base != transition** → the tile is a **transition** tile, either a **cap**
  (a straight edge between the two materials) or a **diagonal** (a corner).
  Which one is decided by the orientation nibble, below.
- **variant** selects among alternate art for the same material combination,
  indexed `0 → 'A'`, `1 → 'B'`, … `10 → 'K'`. Variants beyond what the atlas
  actually ships do occur in real files; fall back to variant `A` and then to
  the first tile in the table rather than failing.

### Orientation nibble

```
value 0..7    the tile is a solid or a cap
value 8..15   the tile is a diagonal (corner)
```

So: transition tiles with orientation < 8 are caps; transition tiles with
orientation ≥ 8 are diagonals. A solid tile still carries a rotation in
0..7 — see §5.

Within each group, the low three bits select one of four 90° rotations and the
high bit of the group selects a mirror. Observed mapping, expressed as the
transform applied to the tile's atlas rectangle:

| solid / cap | diagonal | transform |
|---|---|---|
| 7 | 14 (`e`) | identity |
| 6 | 13 (`d`) | rotate +90° |
| 5 | 12 (`c`) | rotate 180° |
| 4 | 15 (`f`) | rotate −90° |
| 1 | 9  | mirror across the V axis |
| 0 | 8  | rotate +90°, then mirror V |
| 3 | 11 (`b`) | rotate 180° then mirror V *(equivalently mirror U)* |
| 2 | 10 (`a`) | rotate −90°, then mirror V |

**Shipped diagonal art faces left.** Every stock `*D*` atlas tile is drawn
with the corner on the left of the image (west, −X, when sampled with identity
UVs). Orientation 14 is that identity; 13 / 12 / 15 are +90° / 180° / −90°.
The editor must rotate that left-facing tile onto the four corners — it must
not assume a unique D tile per facing in the atlas.

**OBSERVED, and frame-relative.** The *set* of eight orientations and the
pairing of codes into mirrored/unmirrored halves is solid. The absolute sense
of "+90°" for **caps** is the thing to calibrate against a stock map in the
viewport (§8, test 3). Diagonals are pinned by the left-facing atlas art.

**Diagonal mirror remap.** When *writing* a diagonal, the reference exporter
computes `orientation = rotation_index + 8` and then remaps four of the results:

```
12 → 15,  13 → 12,  14 → 13,  15 → 14
```

i.e. the mirrored diagonal quartet is rotated by one position relative to the
mirrored cap quartet. **OBSERVED**, and the exporter's comment attributes it to
corners genuinely behaving differently under mirroring. A writer that omits this
produces corners that look wrong in game but load fine — a silent visual bug.
Verify it against a stock map before trusting either direction.

## 3. Storage order

`.mat` uses the **same zone-interleaved scheme as `.hg2`** (F1 §4), at 64 tiles
per zone edge instead of 256 height samples:

```
zone_x = tx // 64        sub_x = tx % 64
zone_z = tz // 64        sub_z = tz % 64
index  = ((zone_z * map_width + zone_x) * 64 + sub_z) * 64 + sub_x
```

**INFERRED-but-strong:** the reference importer indexes tile data per zone in
blocks of 4096 with a per-zone offset, and the exporter reorders a
left-to-right tile stream into zone blocks before writing, with an explicit
comment that the game expects "zone quadrant" ordering. Both are consistent with
the `.hg2` scheme and with nothing else. Confirm with §8 test 2.

## 4. Atlas layout and tile naming

The atlas image is named by the `.trn`'s `[Atlases] MaterialName` (F3 §1). Each
atlas is a grid of square tiles in normalized UV space: an **8×8 atlas** uses
0.125 steps, a **4×4 atlas** uses 0.25 steps. Both occur in stock content.

Tile source images follow a strict naming convention:

```
<planet:2><base:1><transition:1><type:1><variant:1>0.MAP

  planet      two-letter world prefix (AC, EL, EU, GA, IO, MA, MN, TI, VE)
  base        base material digit
  transition  transition material digit (== base for a solid)
  type        S = solid, C = cap, D = diagonal
  variant     A, B, C, … (matches the variant nibble)
  trailing 0  always present
```

Example: `AC05CB0.MAP` — Achilles, material 0 transitioning to material 5, a cap
tile, variant B.

**This gives you the lookup key directly from the tile word:** compose
`f"{base}{transition}{type}{variant_letter}"` and match it against the four
characters following the planet prefix in the atlas table. Fall back to variant
`A`, then to the table's first entry.

The `.trn`'s `[TextureTypeN] SolidA0` is the fill tile for material N. That
name is usually `{i}{i}SA0`, but not always — stock Elysium's type 4 (base
grid-iron) is `EL04SA0`, not `EL44SA0`. Resolve palette icons and solid UVs
from `SolidA0` first; do not reconstruct `{i}{i}SA0` and treat a miss as
"this material has no texture".

### Per-world atlas tables

Normalized `(u, v, w, h)` per tile, as shipped. These are **OBSERVED** — a
working tool renders stock maps correctly with them — and they are *measurements
of game assets*, useful as a cross-check on your own atlas extraction and as an
emergency fallback for UV layout. **The atlas images themselves still come from
the user's install; nothing here substitutes for that** (`AGENTS.md` rule 3).

Two recorded quirks, preserved rather than corrected: Achilles and Io tables
contain duplicate entries pointing at different atlas cells, and several
Elysium/Ganymede rows read `0.825` where the 0.125 grid would predict `0.875`.
Treat the `0.825` values as suspected typos in the source table — **INFERRED** —
and verify against the real atlas before relying on them.

**Achilles** (`ac_detail_atlas`, 8×8, w=h=0.125):

| tile | u | v |
|---|---|---|
| AC00SA0 | 0.000 | 0.000 |
| AC00SB0 | 0.000 | 0.000 |
| AC00SC0 | 0.000 | 0.000 |
| AC00SD0 | 0.500 | 0.000 |
| AC00SE0 | 0.500 | 0.000 |
| AC01CA0 | 0.625 | 0.000 |
| AC05CA0 | 0.750 | 0.000 |
| AC05CB0 | 0.875 | 0.000 |
| AC05CC0 | 0.000 | 0.125 |
| AC01DA0 | 0.125 | 0.125 |
| AC05DA0 | 0.250 | 0.125 |
| AC11SA0 | 0.375 | 0.125 |
| AC12CA0 | 0.500 | 0.125 |
| AC12DA0 | 0.625 | 0.125 |
| AC22SA0 | 0.750 | 0.125 |
| AC33SA0 | 0.875 | 0.125 |
| AC33SB0 | 0.000 | 0.250 |
| AC33SC0 | 0.125 | 0.250 |
| AC33SD0 | 0.250 | 0.250 |
| AC44SA0 | 0.375 | 0.250 |
| AC55SA0 | 0.500 | 0.250 |
| AC55SB0 | 0.625 | 0.250 |

**Elysium** (`el_detail_atlas`, 8×8, w=h=0.125):

| tile | u | v |
|---|---|---|
| EL00SA0 | 0.125 | 0.000 |
| EL00SB0 | 0.250 | 0.000 |
| EL00SC0 | 0.375 | 0.000 |
| EL01CA0 | 0.500 | 0.000 |
| EL02CA0 | 0.625 | 0.000 |
| EL04CA0 | 0.750 | 0.000 |
| EL01DA0 | 0.825 † | 0.000 |
| EL02DA0 | 0.000 | 0.125 |
| EL04DA0 | 0.125 | 0.125 |
| EL11SA0 | 0.250 | 0.125 |
| EL11SB0 | 0.375 | 0.125 |
| EL11SC0 | 0.500 | 0.125 |
| EL12CA0 | 0.625 | 0.125 |
| EL12DA0 | 0.750 | 0.125 |
| EL22SA0 | 0.825 † | 0.125 |
| EL22SB0 | 0.000 | 0.250 |
| EL22SC0 | 0.125 | 0.250 |
| EL33SA0 | 0.250 | 0.250 |
| EL04SA0 | 0.375 | 0.250 |
| EL04SB0 | 0.500 | 0.250 |

† suspected typo for 0.875.

**Europa** (`eu_detail_atlas`, 4×4, w=h=0.25):

| tile | u | v |
|---|---|---|
| EU00SA0 | 0.00 | 0.00 |
| EU00SB0 | 0.25 | 0.00 |
| EU01CA0 | 0.50 | 0.00 |
| EU04CA0 | 0.75 | 0.00 |
| EU01DA0 | 0.00 | 0.25 |
| EU04DA0 | 0.25 | 0.25 |
| EU11SA0 | 0.50 | 0.25 |
| EU12CA0 | 0.75 | 0.25 |
| EU12DA0 | 0.00 | 0.50 |
| EU22SA0 | 0.25 | 0.50 |
| EU23CA0 | 0.50 | 0.50 |
| EU23DA0 | 0.75 | 0.50 |
| EU33SA0 | 0.00 | 0.75 |
| EU44SA0 | 0.25 | 0.75 |
| EU44SB0 | 0.50 | 0.75 |
| EU44SC0 | 0.75 | 0.75 |

**Ganymede** (`ga_detail_atlas`, 8×8, w=h=0.125):

| tile | u | v |
|---|---|---|
| GA00SA0 | 0.125 | 0.000 |
| GA00SB0 | 0.250 | 0.000 |
| GA00SC0 | 0.375 | 0.000 |
| GA01CA0 | 0.500 | 0.000 |
| GA04CA0 | 0.625 | 0.000 |
| GA01DA0 | 0.750 | 0.000 |
| GA04DA0 | 0.825 † | 0.000 |
| GA11SA0 | 0.000 | 0.125 |
| GA11SB0 | 0.125 | 0.125 |
| GA12CA0 | 0.250 | 0.125 |
| GA14CA0 | 0.375 | 0.125 |
| GA12DA0 | 0.500 | 0.125 |
| GA14DA0 | 0.625 | 0.125 |
| GA22SA0 | 0.750 | 0.125 |
| GA22SB0 | 0.825 † | 0.125 |
| GA22SC0 | 0.000 | 0.250 |
| GA24CA0 | 0.125 | 0.250 |
| GA24DA0 | 0.250 | 0.250 |
| GA33SA0 | 0.375 | 0.250 |
| GA33SB0 | 0.500 | 0.250 |
| GA44SA0 | 0.625 | 0.250 |
| GA44SB0 | 0.750 | 0.250 |

† suspected typo for 0.875.

**Io** (`io_detail_atlas`, 8×8, w=h=0.125):

| tile | u | v |
|---|---|---|
| IO00SA0 | 0.125 | 0.000 |
| IO00SA0 ‡ | 0.250 | 0.000 |
| IO00SB0 | 0.375 | 0.000 |
| IO00SC0 | 0.500 | 0.000 |
| IO01CA0 | 0.625 | 0.000 |
| IO03CA0 | 0.750 | 0.000 |
| IO01DA0 | 0.875 | 0.000 |
| IO03DA0 | 0.000 | 0.125 |
| IO11SA0 | 0.125 | 0.125 |
| IO33SA0 | 0.250 | 0.125 |
| IO33SB0 | 0.375 | 0.125 |
| IO33SA0 ‡ | 0.500 | 0.125 |
| IO33SA0 ‡ | 0.625 | 0.125 |
| IO34CA0 | 0.750 | 0.125 |
| IO34DA0 | 0.875 | 0.125 |
| IO44SA0 | 0.000 | 0.250 |
| IO45CA0 | 0.125 | 0.250 |
| IO45CB0 | 0.250 | 0.250 |
| IO45DA0 | 0.375 | 0.250 |
| IO55SA0 | 0.500 | 0.250 |
| IO55SB0 | 0.625 | 0.250 |
| IO55SC0 | 0.750 | 0.250 |

‡ duplicate name at a different atlas cell; first match wins in the reference
tool, which is the behaviour to reproduce.

**Mars** (`ma_detail_atlas`, 8×8, w=h=0.125):

| tile | u | v |
|---|---|---|
| MA00SA0 | 0.125 | 0.000 |
| MA00SB0 | 0.250 | 0.000 |
| MA00SC0 | 0.375 | 0.000 |
| MA01CA0 | 0.500 | 0.000 |
| MA04CA0 | 0.625 | 0.000 |
| MA04CB0 | 0.750 | 0.000 |
| MA01DA0 | 0.875 | 0.000 |
| MA04DA0 | 0.000 | 0.125 |
| MA11SA0 | 0.125 | 0.125 |
| MA11SA0 ‡ | 0.250 | 0.125 |
| MA11SB0 | 0.375 | 0.125 |
| MA11SC0 | 0.500 | 0.125 |
| MA13CA0 | 0.625 | 0.125 |
| MA13DA0 | 0.750 | 0.125 |
| MA22SA0 | 0.875 | 0.125 |
| MA33SA0 | 0.000 | 0.250 |
| MA44SA0 | 0.125 | 0.250 |
| MA44SB0 | 0.250 | 0.250 |
| MA44SC0 | 0.375 | 0.250 |

**Moon** (`mn_detail_atlas`, 4×4, w=h=0.25; lowercase filenames as shipped):

| tile | u | v |
|---|---|---|
| mn00sa0 | 0.00 | 0.00 |
| mn00sc0 | 0.25 | 0.00 |
| mn03ca0 | 0.50 | 0.00 |
| mn04ca0 | 0.75 | 0.00 |
| mn03da0 | 0.00 | 0.25 |
| mn04da0 | 0.25 | 0.25 |
| mn33sa0 | 0.50 | 0.25 |
| mn44sa0 | 0.75 | 0.25 |
| mn44sb0 | 0.00 | 0.50 |
| mn55sa0 | 0.25 | 0.50 |
| mn66sa0 | 0.50 | 0.50 |

**Titan** (`ti_detail_atlas`, `ti_2_detail_atlas`, `ti_3_detail_atlas` — three
atlas names, one identical table; 4×4, w=h=0.25):

| tile | u | v |
|---|---|---|
| TI00SA0 | 0.00 | 0.00 |
| TI00SB0 | 0.25 | 0.00 |
| TI01CA0 | 0.50 | 0.00 |
| TI03CA0 | 0.75 | 0.00 |
| TI01CB0 | 0.00 | 0.25 |
| TI01CC0 | 0.25 | 0.25 |
| TI01DA0 | 0.50 | 0.25 |
| TI03DA0 | 0.75 | 0.25 |
| TI03DB0 | 0.00 | 0.50 |
| TI11SA0 | 0.25 | 0.50 |
| TI11SB0 | 0.50 | 0.50 |
| TI33SA0 | 0.75 | 0.50 |
| TI33SB0 | 0.00 | 0.75 |

**Venus** (`ve_detail_atlas`, 4×4, w=h=0.25):

| tile | u | v |
|---|---|---|
| VE00SA0 | 0.00 | 0.00 |
| VE01CA0 | 0.25 | 0.00 |
| VE02CA0 | 0.50 | 0.00 |
| VE03CA0 | 0.75 | 0.00 |
| VE02CB0 | 0.00 | 0.25 |
| VE01DA0 | 0.25 | 0.25 |
| VE02DA0 | 0.50 | 0.25 |
| VE03DA0 | 0.75 | 0.25 |
| VE11SA0 | 0.00 | 0.50 |
| VE22SA0 | 0.25 | 0.50 |
| VE22SB0 | 0.50 | 0.50 |
| VE33SA0 | 0.75 | 0.50 |
| VE44SA0 | 0.00 | 0.75 |

## 5. Painting is autotiling — a requirement, not an option

Writing raw nibbles per tile is not a usable authoring workflow, and exposing
one would be a design failure. A painted region of material *M* over a
background *N* must be emitted as:

- **interior tiles** — solids with `base = transition = M`;
- **edge tiles** — caps with `base`/`transition` set to the pair being crossed
  and an orientation that points the transition at the painted region;
- **corner tiles** — diagonals with the same material pair and an orientation
  selected by *which two* orthogonal neighbours are painted.

The backend owns this. The editor's painter sends a material mask; `bzmap`
returns tile words. The classification a correct implementation must satisfy,
stated as requirements rather than as anyone's method:

1. Every tile fully inside the painted mask is a solid of the painted material.
2. Every tile orthogonally adjacent to the mask, along a straight run, is a cap
   whose orientation faces the mask.
3. Every tile diagonally placed at a mask corner — adjacent to the mask on
   exactly one X neighbour and exactly one Z neighbour — is a diagonal, and the
   `(±X, ±Z)` pair of painted neighbours selects one of the four corner
   orientations.
4. Inner and outer corners are distinct cases and must not collapse into each
   other; distinguishing them requires looking at the mask itself, not only at
   the shell around it.
5. Tiles on the outermost row/column of the map are a known trouble spot — the
   reference tool simply refused to paint the outer three tile rings. That is a
   limitation to *beat*, not to copy, but do check your neighbour lookups for
   out-of-range wraparound there; the reference tool's index arithmetic wrapped
   silently, which is exactly why it excluded the border.

**Rotation randomisation.** The reference exporter offers randomising the
orientation nibble of *solid* tiles (uniform over 0..7) to break up visible
tiling on large uniform areas. Harmless, purely cosmetic, and a genuinely good
idea for a painting tool. Offer it; default it off so output stays
deterministic and diffable.

## 6. Fallback when the atlas is unavailable

If the atlas image cannot be extracted from the user's install, splat with the
`[TextureType*] FlatColor` values from the `.trn` (F3 §1) instead. A
flat-coloured map that shows material *boundaries* correctly is still a usable
painting surface, and it degrades honestly.

## 7. What is not known

- The exact meaning of individual material indices per world (which digit is
  "grass", which is "sand") is world-specific and lives in the `.trn`'s
  `[TextureType*]` blocks, not in the `.mat`.
- Whether the engine validates orientation nibbles at all, or simply indexes a
  transform table. Nothing observed depends on the answer.

## 8. Acceptance tests

1. **Byte-identical round trip** on every corpus `.mat`, with no edits.
2. **Zone interleave.** On a map ≥ 2×2, set one tile at a known global
   `(tx, tz)` inside the second zone to a distinctive material pair, write,
   reload, and confirm exactly that tile changed. A flat row-major writer passes
   1×1 and scrambles everything larger.
3. **Visual agreement against the game.** Load a stock map, splat it in the
   viewport, and compare against the same map in game. This is the test that
   settles §2's orientation sign and §2's diagonal mirror remap, and it is worth
   more than any amount of reasoning about them. Record the result — agreement
   promotes those claims to VERIFIED; disagreement is a real finding for the
   generator repo's open questions.
4. **Size guard.** A `.mat` whose length is not `2 * 4096 * zones` for the
   companion `.hg2` must be refused with a message naming both sizes.
5. **Autotile round trip.** Paint a rectangle, export, re-import, and confirm the
   reconstructed mask matches the painted mask — interior solids, edge caps,
   corner diagonals all classified back to the same region.
