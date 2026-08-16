# 01 — Architecture

## The shape of the thing

Two processes, one contract.

```
┌──────────────────────────────────────────┐
│  Godot 4.7 application  (GDScript)       │
│                                          │
│  viewport · camera · brushes · gizmos    │
│  object palette · panels · undo stack    │
│                                          │
│  holds: heights[], materials[], objects  │
│         (plain arrays, in memory)        │
└───────────────┬──────────────────────────┘
                │  session directory
                │  (JSON + raw arrays on disk)
                │  + one-shot subprocess calls
┌───────────────▼──────────────────────────┐
│  bzmap  (Python, sibling repo)           │
│                                          │
│  every game file format, read and write  │
│  validators · packaging · mesh generation│
│  asset extraction · thumbnail renders    │
└──────────────────────────────────────────┘
```

The editor is a **view and an input handler over three arrays**: a heightmap, a
material grid, and a list of objects. It never learns what a `.hg2` is. The
backend owns all format knowledge, keeps its round-trip guarantees, and hands
the editor plain row-major data.

## Why this split

The decision (`QUESTIONS-TODO.md` Q1) was to shell out to `bzmap` rather than
port formats to GDScript. The reasoning, recorded so nobody relitigates it:

- `bzmap` round-trips 128 corpus BZNs and 36 HG2s **byte-identically**, and has
  a test suite proving it. A GDScript port starts that work over at zero and
  can only ever converge back to where Python already is.
- The formats are full of traps that were paid for in play-tests: zone-major
  ordering on three separate files, `pos` appearing three times per object, the
  mission record riding at the end of the last object block, the corpus water
  basis that no amount of correct math reproduces. Each one is a bug the port
  would reintroduce.
- Format fixes then live in one place and benefit both tools.

The cost is a Python dependency at runtime. That is handled in `docs/02` §7.

## Why coarse-grained IPC works

The obvious worry with a subprocess backend is latency. It does not apply here,
because **the backend is only touched at workflow boundaries**:

| Action | Backend call? |
|---|---|
| Move the camera, paint a brush stroke, drag an object | **No.** Pure in-editor. |
| Open a map, create a new map | Yes — once. |
| Save, validate, render a thumbnail, package | Yes — once, on an explicit click. |
| Build the asset cache | Yes — once, then cached to disk. |

The interactive loop never crosses the process boundary. A save on a 5120 m map
moves ~2 MB of heightmap through a file; that is milliseconds of I/O against a
user action that already implies a pause.

This is also why a long-lived JSON-RPC server is *not* specified. It would add
lifecycle management, a protocol, and a class of hangs, to solve a latency
problem the design does not have. One-shot calls with files are simpler, easier
to debug (every exchange is inspectable on disk afterwards), and crash-safe.

## Godot project layout

```
project.godot
scenes/
  main.tscn                   # the whole app shell
  panels/                     # dockable UI scenes
project/
  autoload/
    Backend.gd                # bzmap subprocess driver (docs/02)
    MapState.gd               # the open map: heights, materials, objects, meta
    UndoStack.gd              # command stack (docs/04 §4)
    Settings.gd               # user prefs, install paths, recent files
  terrain/
    TerrainRenderer.gd        # chunked GPU-displaced mesh (docs/03)
    TerrainRaycast.gd         # analytic ray/heightfield intersection (docs/03 §4)
    HeightField.gd            # the height array + dirty-rect bookkeeping
    MaterialField.gd          # the MAT array + painting ops
  brushes/
    Brush.gd                  # base: shape, radius, falloff, strength
    RaiseLower.gd  Flatten.gd  Smooth.gd  Ramp.gd  Noise.gd  Paint.gd
  objects/
    ObjectPalette.gd          # the browsable unit list (docs/05)
    ObjectPlacer.gd           # raycast placement + normal alignment (docs/06)
    PlacedObject.gd           # one object's editor-side state
    AssetCache.gd             # loads converted meshes/textures from cache
  ui/
    ...                       # panels, inspector, toolbars
  shaders/
    terrain.gdshader          # displacement + splat + brush projection
```

## State ownership

**`MapState` is the single source of truth for the open map.** Everything else
reads from it and mutates it only through undoable commands.

```
MapState
  stem            : String          # ≤ 8 chars (engine limit)
  width_m         : int             # multiple of 1280
  depth_m         : int
  world           : String          # mars, io, elysium, ...
  heights         : PackedInt32Array  # row-major, grid_z × grid_x, raw 0..4095
  materials       : PackedInt32Array  # row-major, (depth/20) × (width/20)
  variants        : Dictionary        # "" / "_S" / "_ST" / "_SW" -> [PlacedObject]
  meta            : Dictionary        # trn/ini/des/odf fields the editor exposes
  session_dir     : String            # where the backend exchange lives
  dirty           : bool
```

`heights` is `int32` rather than a packed 16-bit type because GDScript has no
`PackedUInt16Array`; the backend narrows to `uint16` on write and validates the
0–4095 range there. The editor clamps at the brush (`docs/04` §3) so the two
never disagree.

**Residue** — every field of the source map that the editor does not expose —
lives in the session directory and is never loaded into `MapState`. The editor
cannot corrupt what it cannot see. This is how the byte-identical-on-untouched
guarantee (`docs/00`, DoD #2) is achieved.

## The dependency direction

```
battlezone-map-editor  ──depends on──▶  skippy-battlezone-map-generator (bzmap)
```

One way, always. `bzmap` must never import from or know about the editor. The
`bzmap editor` subcommand group is a general-purpose interchange surface that
happens to have one consumer today.

The generator repo is a **sibling checkout**, not a submodule — it is private
today and public later, on its own schedule, and pinning it as a submodule
would couple the two release timelines. `Backend.gd` locates it (`docs/02` §7).

## Threading

Backend calls run **off the main thread** (`Thread` + a completion signal), with
a modal progress indicator for anything that can exceed ~100 ms: open, save,
asset cache build, validate, package. The editor must never freeze on a
subprocess.

Terrain mesh and texture updates happen on the main thread but only over the
**dirty rect** of a brush stroke, not the whole map (`docs/04` §2).

## Error handling posture

The backend returns structured errors (`docs/02` §5). The editor surfaces them
verbatim in a console panel — never swallowed, never reworded into something
friendlier that loses the detail. The operator debugs real maps with these
messages; the exact text matters.

If the backend is missing, unreachable, or the wrong version, the editor starts
anyway in a degraded state that can still navigate and inspect an already-open
session, and says clearly why saving is unavailable.
