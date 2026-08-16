# F3 — `.trn` terrain config and ASCII `.bzn` mission save

Both are text formats. Confidence: **OBSERVED** unless a line says otherwise —
this is the area where a single reference implementation, rather than two, was
available, and where that implementation is demonstrably buggy in one specific
place (§2.4). Read §2.4 before writing any position code.

---

# Part A — `.trn`

## 1. Structure

INI-shaped: `[Section]` headers and `Key=Value` lines. Keys are matched
case-insensitively by every reader seen. Values run to end of line.

Keys that matter to the editor:

| Key | Section | Meaning |
|---|---|---|
| `Width` | (top level) | Map width **in metres** — `1280 × map_width_zones` |
| `Depth` | (top level) | Map depth in metres — `1280 × map_depth_zones` |
| `MinX` | (top level) | X offset applied to every object position (§2.4) |
| `MinZ` | (top level) | Z offset applied to every object position |
| `Height` | (top level) | Height offset applied to every object position |
| `MaterialName` | `[Atlases]` | Atlas base name, e.g. `ac_detail_atlas` (F2 §4) |
| `FlatColor` | `[TextureType*]` | Per-material flat colour; the atlas-less fallback (F2 §6) |

The world is identified by the atlas name. Known values and their worlds:

```
ac_detail_atlas    Achilles
el_detail_atlas    Elysium
eu_detail_atlas    Europa
ga_detail_atlas    Ganymede
io_detail_atlas    Io
ma_detail_atlas    Mars
mn_detail_atlas    Moon
ti_detail_atlas    Titan
ti_2_detail_atlas  Titan
ti_3_detail_atlas  Titan
ve_detail_atlas    Venus
```

Match by substring, not equality — the value as written may carry a path or
extension. Titan ships three atlas names with identical tile layouts.

Which `.act` palette an indexed `.map` texture uses is specified **in the
`.trn`**, not in the texture — see F6 §4.

## 2. Rules for editing a `.trn`

- **Duplicate keys occur in real files.** Some community maps carry two `MinX`
  or `MinZ` lines. **Only the first occurrence counts.** A reader that takes the
  last value places every object wrong on those maps.
- `Height` is ambiguous as a substring — other keys contain it. The reference
  reader disambiguates by requiring the line to *start* with `height` and to
  appear within the first 10 lines. That heuristic is fragile; prefer
  section-aware parsing, and if you must guess, match at line start only.
- **Resizing terrain requires rewriting `Width` and `Depth`** in metres, in
  place, preserving everything else in the file verbatim. A `.trn` is
  hand-edited by mappers and full of settings the editor knows nothing about;
  rewrite lines, never regenerate the file.

## 3. Companion-file consistency

A map is `<name>.hg2` + `<name>.trn` + `<name>.mat` + `<name>.bzn` (+ `.lgt`,
`.des`, `.inf` and others out of scope here). Terrain dimensions appear in two
places — the `.hg2` header in zones and the `.trn` in metres — and both must
agree. `.mat` length must match the same zone count (F2 §1). Disagreement is a
refusable error, not something to paper over.

**`.lgt`:** the reference editor simply **deletes** the `.lgt` after a terrain
edit so the game regenerates lighting on next load. That is a known-working
fallback and a legitimate development shortcut, but note the cost our specs
already record: a missing or zeroed lightmap blacks out the radar underlay. Bake
if you can; delete only as an explicit, labelled fallback.

---

# Part B — ASCII `.bzn`

## 1. Text grammar

Two line shapes, and the difference matters:

```
inline:      key = value          value on the same line, after " = "
next-line:   key [1] =            value alone on the following line
             value
```

`[1]` is a count; `[n]` appears where a block repeats *n* times (see
`points [n] =` in §4). Nested fields are indented by one or two spaces; the
indentation is cosmetic in every reader seen but is reproduced by the reference
writer, so reproduce it.

Section markers `[GameObject]`, `[AiMission]`, `[AOIs]`, `[AiPaths]`,
`[AiPath]` appear alone on a line.

**Binary `.bzn` also exists and is a different format entirely.** A reader that
hits non-UTF-8 bytes has a binary save, and the correct response is to say so:
the file must be re-saved from the game with the `asciisave` launch argument.
Binary `.bzn` is out of scope for this specification set.

## 2. File structure

```
<header>
[GameObject] ...           repeated seq_count times
name = MultSTMission
sObject = <8 hex digits>
[AiMission]
[AOIs]
size [1] =
0
[AiPaths]
count [1] =
<n>
[AiPath] ...               repeated n times
```

### 2.1 Header

In order:

```
version [1] =
2016
binarySave [1] =
false
msn_filename = <basename>.bzn
seq_count [1] =
<object count>
missionSave [1] =
true
TerrainName = <basename, no extension>
size [1] =
<object count>
```

The object count appears twice, as `seq_count` and as `size`. Both must match
the number of `[GameObject]` blocks.

### 2.2 The common `[GameObject]` block

Fields, in the order the reference writer emits them:

| Field | Shape | Notes |
|---|---|---|
| `PrjID [1] =` | next-line | the object's ODF name |
| `seqno [1] =` | next-line | 1-based sequence number |
| `pos [1] =` | next-line block | nested `x`, `y`, `z` |
| `team [1] =` | next-line | |
| `label = ` | inline | may be empty |
| `isUser [1] =` | next-line | |
| `obj_addr = ` | inline | 8 uppercase hex digits |
| `transform [1] =` | next-line block | 12 values, see below |
| *class-dependent extras* | | §2.3 — **order matters** |
| `illumination [1] =` | next-line | `1` |
| `pos [1] =` | next-line block | **second copy** of the same position |
| `euler =` | inline, empty | opens the physics block |
| `mass`, `mass_inv`, `v_mag`, `v_mag_inv`, `I`, `k_i` | next-line, indented | scalars |
| `v`, `omega`, `Accel` | next-line blocks, indented | each `x`/`y`/`z`, all zero at rest |
| `seqNo [1] =` | next-line | **second copy** of the sequence number, different capitalisation |
| `name = ` | inline | |
| `isCritical`, `isObjective`, `isSelected` | next-line | `false` |
| `isVisible [1] =` | next-line | `2` |
| `seen [1] =` | next-line | `1` |
| `healthRatio`, `curHealth`, `maxHealth` | next-line | |
| `ammoRatio`, `curAmmo`, `maxAmmo` | next-line | |
| `priority [1] =` | next-line | `0` |
| `what = `, `where = ` | inline | 8 hex digits |
| `who [1] =` | next-line | |
| `param [1] =` | next-line | may be empty |
| `aiProcess [1] =` | next-line | |
| `isCargo [1] =` | next-line | `false` |
| `independence [1] =` | next-line | `1` |
| `curPilot [1] =` | next-line | |
| `perceivedTeam [1] =` | next-line | |

`transform [1] =` carries twelve nested scalars in this order:

```
right_x  right_y  right_z
up_x     up_y     up_z
front_x  front_y  front_z
posit_x  posit_y  posit_z
```

That is a right/up/front basis plus a position — the same convention as model
transforms (F5 §4, F8 §1).

**Position is stored three times per object:** the first `pos` block, the
`transform`'s `posit_*`, and the second `pos` block. All three must agree.
Writing an object that changed position in only one of them is one of the ways
to produce a file that loads and then misbehaves.

`obj_addr` is the sequence number in hex, zero-padded to 8 uppercase digits,
**0-based** while `seqno` is 1-based. The mission footer's `sObject` is
`last_object_index + 2` in the same encoding.

### 2.3 Class-dependent extra fields

Different `[GameObject]` classes carry different extra blocks, inserted between
`transform` and `illumination`. This is the crux of `AGENTS.md` rule 5 and the
generator repo's four crash-to-lobby bugs: **the field set is class-dependent,
and assembling one by hand is how you crash the game to lobby.** Clone a
verified same-class block from the corpus and edit its values. Do not invent.

What the reference tooling emits, as corroboration of *which* classes carry
extras — not as a licence to synthesise them:

| Class | Extra fields, in order |
|---|---|
| tug, recycler | `undefptr = 00000000` |
| turrettank (incl. howitzer) | four `undeffloat` values, `undefraw = 02000000`, another `undeffloat`, `undefbool` |
| silo | `undefptr = 00000000` |
| constructor | `dropMat [1] =` (a full 12-value transform block), `dropClass [1] =`, `lastRecycled [1] =` |
| producer (recycler, constructor, factory, armory) | recycler only: a leading `undefptr`; then `timeDeploy`, `timeUndeploy`, `undefptr`, `state`, `delayTimer`, `nextRepair`, `buildClass`, `buildDoneTime` |
| scavenger | `scrapHeld [1] =` |
| apc | `soldierCount [1] =`, `state = 00000000` |
| anything that is **not** a building | `abandoned [1] =`, `cloakState = `, `cloakTransBeginTime [1] =`, `cloakTransEndTime [1] =` |

**`undefptr` is not optional.** The reference tooling carries an explicit note
that tug, recycler and silo objects **crash the game** if their `undefptr` is
absent. Independent confirmation of the corpus-cloning law.

**Class detection from the ODF name.** The reference tooling classifies by
string-matching the ODF handle, which is a heuristic and is recorded here only
so you recognise it if you see its output — *not* as a recommended method. The
editor should classify from the ODF's `[GameObjectClass] classLabel` instead
(F8 §4), which is authoritative.

```
2nd char 'v'                     → vehicle-shaped block
2nd char 'b', or name starts 'ap'→ building-shaped block
chars 3-6 'scav'                 → scavenger
chars 3-6 'haul'                 → tug
chars 3-6 'turr' or 'artl'       → turrettank
chars 3-5 'apc'                  → apc
chars 3-6 'towe'                 → gun tower — a building that uses the vehicle block
chars 3-6 'silo'                 → silo subtype
chars 3-6 'recy' / 'cnst', 3-5 'muf' / 'slf' → recycler / constructor / factory / armory
presence of a `timeDeploy` field → producer
presence of a `player` field     → treated as the player object
```

Note the trap the heuristic exists to handle: a **gun tower is a building that
carries the vehicle field set**. Any classifier that keys purely off
"building vs vehicle" gets it wrong.

### 2.4 Coordinates and the TRN offsets — read this twice

An object's stored position is in BZN world coordinates. The `.trn`'s `MinX`,
`MinZ` and `Height` are offsets between that stored frame and the frame the
game's own editor displays.

**The rule to implement, applied uniformly on all three axes and in both
directions:**

```
editor/display coordinate = stored BZN coordinate − offset
stored BZN coordinate     = editor/display coordinate + offset
```

with `offset` being `MinX` for x, `Height` for y, `MinZ` for z.

**The reference implementation does not do this consistently, and you must not
copy its behaviour.** Two defects are visible in it:

1. On the X axis, its import and export paths do not invert each other — a
   round trip through the tool shifts X by twice `MinX` whenever `MinX` is
   non-zero.
2. On the Y axis it subtracts `Height` on import but never adds it back on
   export, so a round trip loses the height offset entirely.

Both are silent on maps where the offsets are zero, which is most maps, which is
why they survived. **The invariant that matters: import-then-export with no
edits must reproduce every position exactly, on a map with non-zero `MinX`,
`MinZ` and `Height`.** Make that an explicit test (§5, test 2) — it is the whole
reason this section is here.

Axis identity itself (which stored axis is width, which is depth, which is up)
is specified in F8 §1 and is not reproduced here; the reference tooling's axis
swaps are Blender-specific and carry no information about the game.

## 3. `[AiMission]` and `[AOIs]`

```
[AiMission]
[AOIs]
size [1] =
0
```

Areas of interest are effectively deprecated in favour of Lua and the reference
tooling always writes zero of them. Preserve any that exist on read; do not
generate new ones.

## 4. `[AiPaths]` and `[AiPath]`

```
[AiPaths]
count [1] =
<number of paths>
```

Then per path:

```
[AiPath]
old_ptr = 00000000
size [1] =
<character count of the label string>
label = <label>
pointCount [1] =
<point count>
points [<point count>] =
  x [1] =
  <x>
  z [1] =
  <z>
    … x/z pair repeated per point …
pathType = 00000000
```

- **Paths are two-dimensional.** Points carry `x` and `z` only; there is no `y`.
  Path height is resolved against terrain at runtime. An editor showing paths in
  3D is projecting them onto the heightfield for display, and must not write a
  height back.
- `size` is the **length in characters of the label**, not a byte count of the
  block. Easy to get wrong; the game reads it.
- `old_ptr` and `pathType` are written as zeros and nothing observed reads them.

### Respawn-point convention

A path whose label matches `<name>_<seconds>_<sequence>` is, by convention,
a respawning-object spawner rather than a navigation path — `<seconds>` being
the respawn interval. This is a **naming convention interpreted by mission
scripts**, not a format feature: nothing in the file marks such a path as
special. Surface it in the UI as a labelled path type, and preserve the exact
label text; do not normalise it.

Paths with no `label` field at all occur in real files, attached to nothing.
The reference tool skips them. Preserve them on read rather than dropping data
the author may care about, but do not surface them as editable.

## 5. Acceptance tests

1. **Byte-identical round trip** on every corpus ASCII `.bzn`, no edits. This is
   the test that catches field-order drift, indentation drift, and float
   formatting drift all at once.
2. **Non-zero TRN offsets.** Take a map with non-zero `MinX`, `MinZ` and
   `Height` — synthesise one if the corpus has none — and confirm import→export
   reproduces every object position exactly. This is the test the reference
   implementation fails; see §2.4.
3. **Triple position agreement.** After any edit that moves an object, assert all
   three stored copies (both `pos` blocks and `transform.posit_*`) match.
4. **Class extras preserved.** For each class in §2.3 present in the corpus,
   round trip and confirm the extra fields survive in order — particularly
   `undefptr` on tug, recycler and silo.
5. **Counts consistent.** `seq_count`, `size`, and the actual `[GameObject]`
   count agree; `[AiPaths] count` matches the `[AiPath]` count; each path's
   `pointCount` matches its emitted `x`/`z` pairs and its `points [n] =` count;
   each path's `size` equals its label length.
6. **Binary detection.** A binary `.bzn` produces the "re-save with asciisave"
   message and no partial parse.
