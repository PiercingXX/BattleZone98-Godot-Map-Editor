# Battlezone 98 Redux Map Editor

A standalone visual map editor for *Battlezone 98 Redux* — sculpt terrain in a
3D viewport, place units by pointing at the ground, edit every piece of map data
the game reads, and save a file set the game loads.

Built with **Godot 4.7**, exporting to Linux and Windows.

> **Status: SPECIFIED, NOT YET BUILT.** This repo currently contains the design
> specs in `docs/`. Implementation is next — see
> [`docs/09-build-plan.md`](docs/09-build-plan.md).

---

## Why

The only map editor for BZ98R is the one inside the game, reached with
`/startedit`: no collision, no undo, a 1998 UI, Windows-only through the game
itself. Everything else the community uses is command-line — `MakeTRN.exe`,
WorldBuilder, and the `bzmap` toolchain.

Nobody has a tool where you can see the map you are making while you make it.
This is that tool.

## How it works

Two halves, one contract:

- **This repo** — the Godot application. Viewport, camera, brushes, gizmos,
  panels, undo. It holds a heightmap, a material grid, and a list of objects,
  and it never learns what a `.hg2` is.
- **[`bzmap`](https://github.com/PiercingXX/skippy-battlezone-map-generator)** —
  the Python toolchain that owns every file format, invoked as a subprocess at
  workflow boundaries (open, save, validate, package).

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

## Reading the specs

| Doc | What it covers |
|---|---|
| [`AGENTS.md`](AGENTS.md) | **Start here.** Operating rules for the build agent. |
| [`docs/00-project-brief.md`](docs/00-project-brief.md) | Scope, deliverables, definition of done. |
| [`docs/01-architecture.md`](docs/01-architecture.md) | The two-process split and why. |
| [`docs/02-bzmap-bridge.md`](docs/02-bzmap-bridge.md) | **The contract.** Session format, verbs, schemas. |
| [`docs/03-viewport-and-camera.md`](docs/03-viewport-and-camera.md) | Terrain rendering, raycasting, camera, performance budget. |
| [`docs/04-sculpting.md`](docs/04-sculpting.md) | Brush model, the brushes, undo/redo, material painting. |
| [`docs/05-assets.md`](docs/05-assets.md) | Live asset enumeration and the fidelity chain. |
| [`docs/06-object-placement.md`](docs/06-object-placement.md) | Palette, placement, the class-layout law, variants. |
| [`docs/07-map-data-and-ui.md`](docs/07-map-data-and-ui.md) | New-map wizard, metadata, water/plants, app shell. |
| [`docs/08-validation-and-packaging.md`](docs/08-validation-and-packaging.md) | Findings panel and the packaging buttons. |
| [`docs/09-build-plan.md`](docs/09-build-plan.md) | Phased milestones with acceptance criteria. |
| [`docs/10-open-questions.md`](docs/10-open-questions.md) | Unknowns, risks, and the experiments that resolve them. |
| [`QUESTIONS-TODO.md`](QUESTIONS-TODO.md) | The design decision record. |
| [`docs/formats/`](docs/formats/README.md) | Clean-room functional specs for every game file format (`F1`–`F8`). |

## Requirements

- **Godot 4.7 stable** (to build from source)
- **A Battlezone 98 Redux installation** — the editor reads units, terrain
  templates, and textures from your own copy. No game content ships with this
  editor.
- **The `bzmap` backend**: Python 3.11+ with `numpy`, `Pillow`, and `scipy`.
  Windows bundling is tracked in [`docs/10`](docs/10-open-questions.md) Q-D.

## Credit

- **[`bzmap`](https://github.com/PiercingXX/skippy-battlezone-map-generator)** —
  the format toolchain this is built on; every format spec and round-trip
  guarantee comes from there.
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

  Both addons were studied under a **clean-room process** and are no longer
  present in this repository; `bzmap` is written from the functional specs in
  [`docs/formats/`](docs/formats/README.md), not from their code. Losing the
  code does not mean losing the acknowledgement — the facts in those specs are
  knowable because these people did the reverse engineering first.
- The BZP pack and its maintainer, whose corpus is the ground truth behind
  nearly every format fact these specs rely on.
- Rebellion, for *Battlezone 98 Redux*. All game assets remain theirs; this tool
  reads them from your installation and redistributes nothing.
