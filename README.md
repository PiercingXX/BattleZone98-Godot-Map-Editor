# BattleZone 98 Godot Map Editor

A standalone **Godot 4.7** map editor for *Battlezone 98 Redux* — sculpt
terrain in a 3D viewport, place units by pointing at the ground, edit every
piece of map data the game reads, and save a file set the game loads.

Exports to Linux and Windows.

> **Status: usable editor.** Probe an install, open or create a map, sculpt,
> paint, place units (proxies), validate, and save. The `bzmap` backend is
> bundled in `backend/`. No sibling repo required. Meshes beyond labelled
> proxies and a Windows-bundled Python are still outstanding.

---

## How it works

Two halves, one contract:

- **This repo** — the Godot application **and** the bundled `bzmap` backend
  under `backend/`. Viewport, camera, brushes, gizmos, panels, undo. The
  GDScript side holds a heightmap, a material grid, and a list of objects, and
  it never learns what a `.hg2` is.
- **`backend/bzmap`** — the Python toolchain that owns every file format,
  invoked as a subprocess at workflow boundaries (open, save, validate,
  package). Originally developed as
  [`battlezone98-map-generator`](https://github.com/PiercingXX/battlezone98-map-generator);
  this editor vendors the package so it runs from a single checkout.

`bzmap` round-trips all 128 corpus mission files and all 36 corpus heightmaps
byte-identically. The editor inherits that guarantee by never going around it,
which is why **opening a stock map, changing one thing, and saving leaves every
untouched file byte-for-byte identical.**

The interface between the two is [`docs/02-bzmap-bridge.md`](docs/02-bzmap-bridge.md).

## Features

- Free-fly 3D navigation — `WASD` to move, `Q`/`E` for down/up, mouse-look
- Terrain sculpting with brushes projected onto the surface: raise/lower,
  flatten, smooth, ramp, noise — all resizable in metres, all undoable
- Material painting, manual and rule-based
- A searchable palette of every unit and building in your own installation,
  placed by raycast and aligned to the terrain normal
- Full map data editing: terrain config, multiplayer metadata, descriptions,
  BZP settings, and the `_S` / `_ST` / `_SW` object variants
- Water and vegetation authoring as generated meshes
- Validation report with click-to-fly-there findings
- Packaging: thumbnail rendering, install to a test mod, pack assembly

## Docs

| Doc | What it covers |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Operating rules for Skippy. |
| [`docs/02-bzmap-bridge.md`](docs/02-bzmap-bridge.md) | The editor ↔ `bzmap` contract. |
| [`docs/formats/`](docs/formats/README.md) | Clean-room functional specs for every game file format (`F1`–`F8`). |

## Run it

```bash
python3 -m venv .venv
.venv/bin/pip install -e backend
godot --path .
```

Tests (backend pytest + editor GDScript suite):

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
- **Python 3.11+** (for the bundled backend)
- **A Battlezone 98 Redux installation** to open real maps. The editor itself
  ships no game content.

Windows release builds: see [`scripts/windows-bundle.md`](scripts/windows-bundle.md).
The Godot `.exe` and a `backend/` folder (embeddable CPython + `bzmap`) ship
side by side.

## Credit

- **[`bzmap`](https://github.com/PiercingXX/battlezone98-map-generator)** —
  the format toolchain this editor vendors under `backend/`; every format spec
  and round-trip guarantee comes from there.
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
