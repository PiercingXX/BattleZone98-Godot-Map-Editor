# BattleZone 98 Godot Map Editor

A standalone **Godot 4.7** map editor for *Battlezone 98 Redux* — sculpt
terrain in a 3D viewport, place units by pointing at the ground, edit every
piece of map data the game reads, and save a file set the game loads.

Exports to Linux and Windows.

---

## How it works

Pure GDScript, one process, zero runtime dependencies:

- **The editor** — viewport, camera, brushes, gizmos, panels, undo. It works
  on a row-major heightmap, a material grid, and a list of objects.
- **The format layer** (`project/backend/`) — every game file format
  (`.hg2`, `.mat`, `.trn`, `.bzn`, OGRE meshes, …) parsed and written in
  GDScript. Ported from the Python `bzmap` toolchain originally developed as
  [`battlezone98-map-generator`](https://github.com/PiercingXX/battlezone98-map-generator).

The format layer's contract: **opening a stock map, changing one thing, and
saving leaves every untouched file byte-for-byte identical.** Untouched source
data passes through verbatim; byte-identical round-trips are enforced by the
test suite, not promised by convention.

The internal boundary between the two halves is
[`docs/02-bzmap-bridge.md`](docs/02-bzmap-bridge.md) (session model).

## Features

- Free-fly 3D navigation — `WASD` to move, `Q`/`E` for down/up, mouse-look
- Geometry-clipmap terrain: constant triangle count at any map size, with
  height read from a texture so an edit never rebuilds a mesh
- Terrain sculpting with brushes projected onto the surface: raise/lower,
  flatten, smooth, ramp, noise, erode — all resizable in metres, all undoable
- Brush tips and stroke dynamics: image-mask tips, rotation, spacing, and
  pressure-driven size and opacity
- Sculpting and painting limited by slope and height band, with feathering
- Procedural terrain generation — noise, landforms, remap curves, thermal and
  droplet erosion — applied as a single undoable edit
- Material painting, manual and rule-based, with cap and corner autotiling.
  Solids, caps, corners and their variants are all picked from one grid of the
  tiles the world's own atlas ships
- Painted scatter with a live viewport preview: a mask plus a seed, resolved
  into instances at save time rather than stored
- A searchable palette of every unit and building in your own installation,
  placed by raycast and aligned to the terrain normal, with rendered 3D
  thumbnails
- Full map data editing: terrain config, multiplayer metadata, descriptions,
  BZP settings, and the `_S` / `_ST` / `_SW` object variants
- Water and vegetation authoring as generated meshes
- Sun and fog: a clock slider bound to the `.trn` `Time=` value, shadowed
  terrain, and the map's fog distances previewed in the viewport
- Minimap panel, command palette, and rebindable keys
- Validation report with click-to-fly-there findings
- Packaging: thumbnail rendering, install to a test mod, pack assembly

## Docs

| Doc | What it covers |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Operating rules for this repo. |
| [`docs/02-bzmap-bridge.md`](docs/02-bzmap-bridge.md) | The session model and verb contract between the UI and the format layer. |
| [`docs/formats/`](docs/formats/README.md) | Clean-room functional specs for every game file format (`F1`–`F8`). |

## Run it

```bash
godot --path .
```

That's it — no Python, no venv, no dependency install on any platform.

Tests (headless GDScript suite):

```bash
scripts/test.sh
```

Then **Probe** (finds your Steam install) → **Open map…** and pick a `.trn` /
`.bzn` / `.hg2` from BZP or a generated set.

- Fly: `WASD` `Q`/`E`, right mouse look, `F` frame, `Space` top-down, `H` slope, `V` walk-the-surface
- Tools: `1`–`8` or the toolbar (`9` select, `0` noise). `[` / `]` brush radius. `Ctrl+Z` undo.
- LMB sculpts or places. Palette search is on the left. `F1` is the hotkey list.
- First run imports an asset index (labelled proxies). Import assets again
  after a game or BZP update.

- **Godot 4.7 stable**
- **A Battlezone 98 Redux installation** to open real maps. The editor itself
  ships no game content.

Windows release builds: see [`scripts/windows-bundle.md`](scripts/windows-bundle.md).
The exported Godot `.exe` is the whole application.

## Credit

- **[`bzmap`](https://github.com/PiercingXX/battlezone98-map-generator)** —
  the Python format toolchain this editor's GDScript format layer was ported
  from; every format spec and round-trip guarantee originates there.
- **[GrizzlyOne95](https://github.com/GrizzlyOne95)** —
  [WorldBuilder](https://github.com/GrizzlyOne95/Battlezone98Redux_WorldBuilder)
  (MIT) for heightmap zone packing, material auto-painting, and atlas tooling,
  plus `bzfile` and `ExtraUtilities`.
- **Business Lawyer & DivisionByZero** — BZMapIO, the Blender heightmap map
  editor whose working HG2/MAT/BZN implementation settled the zone interleave,
  the 13-bit height field, and the MAT tile word.
- **BattlezoneScrapField, GrizzlyOne95, Commando950 & Kindrad** —
  [Battlezone98Redux_BlenderAIO](https://github.com/BattlezoneScrapField/Battlezone98Redux_BlenderAIO)
  (GPL-3.0), which identified the Redux OGRE model pipeline and pinned down the
  classic GEO/VDF/SDF layouts.
- The BZP pack and its maintainer, whose corpus is the ground truth behind
  nearly every format fact these specs rely on.
