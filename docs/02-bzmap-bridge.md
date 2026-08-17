# 02 — The `bzmap` bridge contract

> **Status (2026-08-17):** the Python subprocess backend this document was
> written against has been ported to GDScript in full — see
> [`docs/03-gdscript-port.md`](03-gdscript-port.md). The **session model (§1),
> verb payload shapes (§3–4), error shapes (§5), and the crash-safety gate
> (§6) remain the canonical contract**, now between the UI and the in-process
> format layer under `project/backend/`. The invocation mechanics (§2) and
> backend location/shipping (§7–8) are historical: verbs are direct GDScript
> calls dispatched by `project/autoload/Backend.gd` on a worker thread, and
> nothing needs locating or shipping.

This is the interface between the two halves of the project. Both sides are
built against this document. Change it deliberately and in one commit.

**Where the work lives:** the verbs are `project/backend/editor/Bz*.gd`; the
driver (`Backend.gd`) dispatches them. Neither side reaches past this
contract. The editor checkout is standalone.

---

## 1. The session directory

All exchange happens through a **session directory** the editor owns:

```
<user_data>/sessions/<uuid>/
  manifest.json        # what this map is; written by backend, read by both
  terrain.r16          # heights, raw little-endian uint16, ROW-MAJOR
  materials.u16        # material grid, raw little-endian uint16, ROW-MAJOR
  objects.json         # placed objects, all variants (schema in §4a)
  features.json        # water/plant feature parameters (schema in §4b)
  masks/               # region masks for features, raw u8 grids, ROW-MAJOR
  meta.json            # editable metadata fields
  dirty.json           # what the editor changed since open (see "pass-through")
  residue/             # opaque backend-owned data — the editor NEVER touches this
  report.json          # last validation result
```

### Row-major is the law of this interface

`bzmap` converts to and from the game's zone-major layouts on both sides. The
editor sees a plain row-major array, indexed `[z * grid_x + x]`, origin at
`(0, 0)`, `+x` east and `+z` north. **The editor must never contain zone
logic.** Three separate game files are zone-major and the generator repo's
history shows that layout bugs stay invisible on single-zone (1280 m) maps and
only surface when the first multi-zone map reaches the game — exactly the class
of bug this boundary exists to prevent.

### North-up

`+z` is north and renders at the **top** of every map image. The game's minimap
uses our per-map `.png`, and the generator repo shipped mirrored renders once
before catching it. The editor's overview panel follows the same convention.

### `residue/` is opaque

Everything the editor does not expose — unparsed `.trn` sections, per-object
fields outside the editable set, AI paths, `.vxt` contents, the mission record,
the original binary form of a stock BZN — lives here in whatever form the
backend finds convenient. The editor treats it as a black box it copies around
but never reads or writes. This is what makes DoD #2 (byte-identical on
untouched data) achievable.

The backend also keeps **verbatim copies of every source file** in residue,
because of the pass-through rule below.

### The pass-through rule

**A source file whose inputs the editor did not change is emitted from the
verbatim copy, byte for byte — never re-encoded.** Re-encoding "unchanged" data
is where byte-fidelity quietly dies, so the rule is structural, driven by
`dirty.json`:

```json
{
  "terrain": false,
  "materials": false,
  "objects": {"": [], "_S": ["obj-0042", "new-0001"], "_SW": []},
  "features": false,
  "meta": ["ini.missionName"]
}
```

The editor maintains this file (it is the undo stack's summary of what has ever
been touched this session); the backend consumes it on `save`:

- `terrain` false → the original `.hg2` is copied out verbatim, `terrain.r16`
  ignored. True → re-encode from `terrain.r16`, preserving the header's
  `unknownA` from residue — **and the per-cell flag bits**: the height word is
  `[flags:3][height:13]` (mask `0x1FFF`), verified in `docs/formats/F1` §3,
  which also fixes `terrain.r16` as plain row-major, masked, height-only
  (`F1` §6). The backend must carry the flag
  bits of every cell in residue and OR them back on re-encode; zeroing them is
  a silent edit of data the user never touched. Whether `terrain.r16` carries
  full 16-bit words or masked 13-bit heights is the backend's call — but the
  editor must be handed **height-only** values, or brush math on a
  flag-carrying cell corrupts it.
- `objects` lists per variant the ids of touched objects → untouched blocks are
  re-emitted verbatim from residue; only listed ids are mutated or cloned.
- **Derived files regenerate only when their inputs changed**: `.lgt` and the
  thumbnails when terrain, features, or objects changed; `.des` counts when
  objects changed. Otherwise verbatim copies. A regenerated `.lgt` is baked,
  never zero-filled (a zero lightmap renders a black in-game radar).

This is what makes Phase 1's acceptance test — open then save with no edits,
every file byte-identical — true *by construction* rather than by luck.

### Inherited out-of-range data is preserved, never rejected

The editor's sculpting ceiling is raw 4095 (Q6), but **stock maps exceed it** —
`ulltst96` measures raw 7630 (generator repo open question E7; 7630 fits the
verified 13-bit height field, so E7's answer is a raw-8191 engine ceiling with
4095 being an *editor authoring* convention — see `docs/formats/F1` §3).
Opening ALL maps
(Q7) plus byte-fidelity (DoD #2) therefore forces this rule: the 4095 ceiling
applies to **editor writes only**. Values above it that arrive from a source
file pass through untouched (uint16 holds them fine), survive save, and are
reported as a manifest warning — the backend must never reject or clamp them.
Only a **newly created** map is validated against the ceiling.

---

## 2. Invocation

Every call is a one-shot subprocess:

```
python -m bzmap.cli editor <verb> [args...] --json
```

- **stdout** carries exactly one JSON object, and nothing else.
- **stderr** carries human-readable progress and diagnostics, streamed.
- **exit code** 0 on success, non-zero on failure (the JSON still parses; see
  §5).

The editor runs these on a worker thread and shows stderr live in the console
panel for long operations.

---

## 3. The verbs

### `probe`
Find and describe the environment. Called at startup and from the settings
panel.

```
bzmap editor probe --json
```
```json
{
  "ok": true,
  "bzmap_version": "0.4.1",
  "contract_version": 1,
  "python": "3.11.9",
  "installs": [
    {
      "kind": "game",
      "path": "/home/x/.steam/.../Battlezone 98 Redux",
      "version": "2.2.301",
      "platform_hint": "proton"
    },
    {
      "kind": "workshop_item",
      "path": "/home/x/.steam/.../workshop/content/301650/3406347034",
      "name": "BZP",
      "id": "3406347034"
    }
  ],
  "warnings": ["no game install found at any default path"]
}
```

**Install discovery** (implemented in `backend/bzmap/editor/discover.py`):
Steam App ID `301650`, the per-platform Steam roots, the `libraryfolders.vdf`
walk for secondary drives, GOG fallbacks, and the two-argument validation
(`battlezone98redux.exe` **and** `BZ_ASSETS/common/models/`).

Two corrections to the example above, measured 2026-08-16:

- **Workshop items live in two places**, and neither contains the other:
  `<library>/steamapps/workshop/content/301650/<id>/` (subscribed) and
  `<install>/packaged_mods/<id>/` (materialised). `probe` must report the union,
  keyed by ID, with the source of each.
- `packaged_mods/` IDs are **not all Steam workshop IDs** — internal ones such
  as `9990001` appear there — so `kind: "workshop_item"` needs a `source` field
  (`"workshop"` / `"packaged"` / `"both"`) rather than an assumed provenance.

### `worlds`
Enumerate the stock terrain templates available for the new-map wizard.

```
bzmap editor worlds --game-root <path> --json
```
```json
{
  "ok": true,
  "worlds": [
    {
      "id": "mars",
      "label": "Mars",
      "trn_template": "Edit/trn/mars.trn",
      "atlas": "mars_detail_atlas",
      "sky": "...",
      "texture_types": [
        {"index": 0, "flat_color": [140, 90, 60], "label": "..."},
        ...
      ]
    }
  ]
}
```

Nine stock worlds ship in `Edit/trn/`: achilles, elysium, europa, ganymede, io,
mars, moon, titan, venus. `texture_types` feeds the material painting palette —
the editor needs to know how many materials a world has and roughly what colour
each is, even before atlas textures are resolved.

### `assets`
Build (or refresh) the asset cache: enumerate every placeable class from the
install, and convert what can be converted into Godot-loadable form.

```
bzmap editor assets --game-root <path> [--pack <workshop-path> ...] \
                    --cache <dir> [--refresh] --json
```
```json
{
  "ok": true,
  "cache_dir": "/home/x/.local/share/bzeditor/cache/assets",
  "generated_at": "2026-08-16T12:00:00Z",
  "source_fingerprint": "sha256:...",
  "classes": [
    {
      "prjid": "eggeizr1",
      "odf": "eggeizr1.odf",
      "source": "game",
      "category": "prop",
      "label": "Geyser",
      "faction": null,
      "radius_m": 8.0,
      "footprint_m": [16.0, 16.0],
      "mesh": "meshes/eggeizr1.glb",
      "mesh_fidelity": "geo_textured",
      "icon": "icons/eggeizr1.png",
      "template_verified": true,
      "placement_mode": "bzn"
    }
  ],
  "unresolved": [
    {"prjid": "xyz", "reason": "no geometry found for geometryName 'foo'"}
  ]
}
```

Field notes:
- `source` — `"game"` or the workshop item id, so the editor can enforce the
  **assets do not cross workshop items** rule.
- `mesh_fidelity` — one of `hd`, `geo_textured`, `geo_flat`, `proxy`. Degrade
  down that chain when a rung cannot be loaded.
- `template_verified` / `placement_mode` — the crash-safety gate. See §6 below;
  this is the most consequential field in the whole contract.
- `source_fingerprint` — lets the editor detect that the install changed (a
  game patch, a BZP update) and offer a rebuild.

Cache layout is the backend's business except that meshes are **glTF `.glb`**
and icons/textures are **PNG**, both loadable by Godot at runtime without
import. The cache lives outside both repos and is never committed.

### `new`
Create a fresh map session.

```
bzmap editor new --stem <name> --world <id> --width <m> --depth <m> \
                 --base-height <raw> --session <dir> --game-root <path> --json
```

Backend responsibilities: reject a stem over 8 characters or colliding with a
known terrain name; reject dimensions that are not multiples of 1280; copy the
world's `.trn` template and override only `[Size]`/`[NormalView]`/`[World]`/
`[Sky]`; fill `terrain.r16` with `base_height` (default raw 1000 = 100 m, per
the generator repo's finding that play surfaces sit on a nonzero plateau);
auto-paint an initial `materials.u16`; write starter `meta.json`.

### `open`
Open an existing map into a session.

```
bzmap editor open <path-to-map-file-or-dir> --session <dir> --json
```

Accepts any file of the set or the containing directory; resolves the rest of
the basename group case-insensitively. Must handle:
- ASCII BZNs (the normal case),
- **binary BZNs** (stock 1998-era content) — read via WorldBuilder's
  `BinaryBZNParser`, with `"converted_from_binary": true` in the manifest so
  the editor can warn that saving writes ASCII,
- missing optional files (no `_ST` variant, no `.lgt`, a broken stub) — report
  in `warnings`, do not fail.

Response includes the manifest (§4) plus `warnings`.

### `save`
Write the session back out to a map file set.

```
bzmap editor save --session <dir> --out <dir> [--stem <name>] --json
```
```json
{
  "ok": true,
  "files": ["mymap.trn", "mymap.hg2", "mymap.mat", "mymap.lgt",
            "mymap.bzn", "mymap_S.bzn", "mymap_SW.bzn",
            "mymap.ini", "mymap.des", "mymap.odf", "mymap.vxt",
            "mymap.lua", "mymap.png", "mymap.BMP"],
  "byte_identical": ["mymap.vxt", "mymap.lua"],
  "regenerated": ["mymap.lgt", "mymap.png", "mymap.BMP"],
  "warnings": []
}
```

Backend responsibilities, all of them load-bearing:
- Apply the **pass-through rule** (§1): unchanged inputs → verbatim copies;
  changed inputs → re-encode (row-major → zone-major for `.hg2`/`.mat`/`.lgt`),
  derived files regenerated only when their inputs changed.
- Touched objects (per `dirty.json`) are mutated field-by-field; new objects are
  **cloned from verified templates** (§6); untouched blocks re-emit verbatim.
- Maintain the BZN invariants `bzmap` already enforces: `size`, `seq_count`,
  contiguous `obj_addr`, exactly one `isUser=1` player per variant, and the
  **mission record (`name = Mult*Mission`, `sObject = count+1`) at the end of
  the last object block** — objects are appended *before* it.
- `byte_identical` reports which output files match the source bytes exactly.
  The editor surfaces this; it is DoD #2's evidence. `regenerated` lists the
  derived files that were rebuilt and why.

### `validate`
Run the offline validators against the session.

```
bzmap editor validate --session <dir> [--tier 1,2] --json
```
```json
{
  "ok": false,
  "findings": [
    {
      "id": "C1",
      "severity": "error",
      "title": "geyser unreachable from base0",
      "detail": "...",
      "world_pos": [1240.0, 98.0, 2210.0],
      "object_id": "obj-0042",
      "variant": "_S"
    }
  ]
}
```

`world_pos` and `object_id` are what make this a *panel* rather than a log —
the editor flies the camera to a finding when you click it.
Backend must populate them wherever the underlying validator knows a location.

### `render`
Produce the thumbnail/minimap images and the debug overview.

```
bzmap editor render --session <dir> --out <dir> [--debug] --json
```

North-up, always. Returns paths; the editor displays them in the overview
panel.

### `package`
The buttons (Q9).

```
bzmap editor package --session <dir> --mode install --game-root <path> \
                     --test-id <id> --json
bzmap editor package --session <dir> --mode pack --out <dir> --json
```

`install` copies into a **separate** test mod directory — never into the game
or into BZP. `pack` wraps the existing `assemble`/`bzpt` machinery. Both are
thin wrappers over code that already exists in the generator repo.

---

## 4. `manifest.json`

Written by the backend on `new`/`open`, re-read by the editor, and updated by
the backend on `save`.

```json
{
  "contract_version": 1,
  "stem": "mymap",
  "source_path": "/path/to/original",
  "converted_from_binary": false,
  "world": "mars",
  "width_m": 2560,
  "depth_m": 2560,
  "grid_x": 512,
  "grid_z": 512,
  "cell_m": 5.0,
  "height_scale": 0.1,
  "height_max_raw": 4095,
  "mat_grid_x": 128,
  "mat_grid_z": 128,
  "mat_cell_m": 20.0,
  "variants": ["", "_S", "_SW"],
  "has_lightmap": true,
  "pack_context": {"kind": "bzp", "workshop_id": "3406347034"}
}
```

`pack_context` tells the editor which asset layers are legal for this map
and which metadata conventions to present:
`{"kind": "base"}` for a plain base-game map, `{"kind": "bzp", ...}` for a BZP
one.

`height_max_raw` is **4095** (Q6): the ceiling for **editor writes** — brushes
clamp to it, and newly created maps are validated against it. It is *not* a
gate on opened data; inherited values above it pass through per §1, with a
manifest warning (`"height_over_ceiling": true`) so the UI can say so. If the
generator repo's E7 resolves to a wider ceiling, this field is how it changes
without an editor release.

### 4a. `objects.json`

One record per placed object, per variant:

```json
{
  "": [ ... ],
  "_S": [
    {
      "id": "obj-0042",
      "origin": "source",
      "prjid": "eggeizr1",
      "x": 1240.5, "y": 98.0, "z": 2210.0,
      "yaw_deg": 57.4,
      "team": 0,
      "label": "eggeizr10_geyser",
      "up_convention": "upright",
      "pinned_y": false,
      "managed": false,
      "required": false
    }
  ]
}
```

- `id` is **stable for the life of the session** and is the key linking three
  things: this record, its verbatim block in residue, and its entry in
  `dirty.json`. The backend assigns ids on `open` (`origin: "source"`); the
  editor assigns fresh ids for placements (`origin: "new"`, id `new-NNNN`).
  Without this link there is no way to know which blocks may be re-emitted
  verbatim — it is the hinge of the pass-through rule.
- `managed: true` marks backend-owned objects (water/plant carriers — the
  editor may inspect but not transform them).
- `required: true` marks objects that must exist (the player object) — the
  editor refuses to delete them.

### 4b. `features.json`

Water and plant authoring parameters, consumed by the backend's mesh
generation on save:

```json
{
  "water": [
    {"stem": "mywater1", "level_m": 92.0, "mask": "masks/mywater1.u8",
     "variant_scope": "all"}
  ],
  "plants": [
    {"stem": "myplnt1", "mask": "masks/myplnt1.u8", "density": 260,
     "seed": 7}
  ]
}
```

Masks are row-major u8 grids at heightmap resolution, 0 = outside. The backend
owns everything downstream: mesh generation, the carrier objects (which appear
in `objects.json` as `managed`), and the corpus carrier basis.

---

## 5. Errors

Failure still returns parseable JSON:

```json
{
  "ok": false,
  "error": {
    "code": "stem_too_long",
    "message": "terrain stem 'xxMonke01' is 9 characters; the engine truncates script lookups above 8",
    "hint": "use a stem of 8 characters or fewer",
    "path": "/path/if/relevant"
  }
}
```

`code` is a stable machine-readable identifier the editor may branch on.
`message` is shown verbatim to the user — do not reword it in the editor.

Any non-zero exit without parseable JSON on stdout is a **backend crash**: the
editor shows the raw stderr in the console panel and marks the session
unsaved-but-intact. It must never discard the user's work because a subprocess
died.

---

## 6. `template_verified` — the crash-safety gate

**Read the generator repo's `docs/16` before implementing anything in this
section.** It records five consecutive crash-to-lobby bugs, all one root cause:
a `[GameObject]` block that was assembled, re-typed, or value-tweaked instead
of cloned verbatim from a same-class block known to load.

The law that came out of it: *the only safe template for a placed object is a
same-class block that has loaded in-game, cloned verbatim, renaming only PrjID
and label.*

So the asset index carries, per class:

- **`template_verified: true`** — the backend holds a corpus block for this
  class that is known-good. `placement_mode: "bzn"`. The editor may place it
  freely; `save` clones the verified block.
- **`template_verified: false`** — no verified block exists. The class is
  still shown in the palette and still placeable in the viewport, but
  `placement_mode` is `"runtime"`: on save, the backend emits it as a
  host-guarded `BuildObject` in the map's `MAP.lua` rather than as a BZN block.

The runtime path is not a workaround; it is what the operator arrived at
independently after the Warrens series — *"empty craft = runtime
`BuildObject(odf, 0, pos)` + `RemovePilot(h)`, host-only"* — because it also
avoids BZN-placed craft acquiring pilots at load and turning hostile.

**Pack-context caveat:** the `<stem>MAP.lua` module hook and its script plumbing
are a **BZP convention**. For a `{"kind": "base"}` map the backend needs a
base-game script template that the engine loads natively, with the same
host-guarded spawn block. Verify a base-game `<stem>.lua` actually runs before
relying on it. If runtime spawning turns out to be BZP-only, unverified classes
on base-game maps are simply unavailable, stated in the palette with the reason.

The editor's job is to **show this distinction in the palette and the
inspector**, never to override it. A user placing a howitzer should see that it
will be spawned at runtime, and why.

The known-good classes as of the generator repo's corpus work are geysers,
scrap, spawn points, the player, depots, and environment mesh carriers. Craft
layouts beyond wingman are explicitly unverified. Growing that set is a
generator-repo task, and the editor picks it up for free when the index changes.

---

## 7. Locating and shipping the backend

Discovery order for `Backend.gd`, first hit wins:

1. `--bzmap` command-line argument or the setting saved in the settings panel.
2. `BZMAP_HOME` environment variable.
3. A bundled runtime next to the executable (`./backend/`), if the export was
   built with one.
4. The in-repo `backend/` directory (the default for a source checkout).
5. `python -m bzmap` on `PATH`.

The backend must run on Linux and Windows identically. Requirements: Python
3.11+, `numpy`, `Pillow`, `scipy`. **Do not shell through a shell** — invoke the
interpreter directly with an argument array so paths with spaces (the game
install has one) work on both platforms without quoting.

For public release, the Windows export should bundle an embeddable Python plus
the dependencies under `./backend/`, so a user is not asked to set up a Python
environment to run a map editor. Until that packaging exists, discovery order 4
covers a source checkout. Do not skip the Windows bundle — it is the difference
between a tool the operator can use and a tool the community can use.

## 8. Contract versioning

`contract_version` appears in `probe` and in `manifest.json`. The editor refuses
to open a session whose contract version it does not know, and warns rather
than guesses when the backend's version is newer. Bump it on any breaking
change to the session directory or the verb responses.
