# 00 — Project brief

## What we are building

A **standalone desktop application** — Godot 4.7, exported for Linux and
Windows — that lets a human visually author complete, playable maps for
*Battlezone 98 Redux*: sculpt the terrain in a 3D viewport, place objects by
pointing at the ground, edit every piece of map metadata the game reads, and
save a file set the game loads without errors.

It is the visual front end to the `bzmap` toolchain. `bzmap` already knows how
to read and write every file in a Battlezone map with byte fidelity; what it
lacks is a pair of eyes and a mouse. This is that.

## Why this is worth doing

The only map editor for BZ98R is the one inside the game, reached with
`/startedit`. It has no collision, no undo, a 1998 UI, and it only runs on
Windows through the game itself. Everything else the community uses is
command-line: `MakeTRN.exe`, WorldBuilder, and now `bzmap`. Nobody has a tool
where you can *see the map you are making while you make it*.

The generator repo proved the hard part is not the file formats — those are
solved and tested. The hard part is map *quality*, and quality is a judgment
call that a human makes with their eyes. This editor closes that loop.

## Deliverables

### D1 — The editor application
A Godot 4.7 project exporting to a single Linux binary and a single Windows
executable, with the Python backend bundled or discovered (`docs/02` §7).

### D2 — The `bzmap editor` bridge
A new subcommand group in the generator repo's `bzmap` CLI (`docs/02`) that
serves the editor: probe, assets, worlds, new, open, save, validate, render,
package. This is work in *that* repo, specified from *this* one.

### D3 — Documentation for a public release
README, build instructions, and a user-facing guide to the workflow. The repo
goes public; it should be usable by someone who is not the operator.

## The four mandatory features

Stated in the operator's original brief, and the acceptance spine of the build
plan:

1. **Free 3D navigation** — WASD to move, Q/E for down/up, mouse-look.
   (`docs/03`)
2. **Viewport heightmap sculpting** — brushes projected onto the terrain,
   resizable, with at minimum raise/lower, flatten, and smooth. (`docs/04`)
3. **Full terrain and map data handling** — ask for planet and dimensions on
   new-map; load, display, edit, and save every piece of map data the game
   supports. (`docs/02`, `docs/07`)
4. **A unit palette panel** — every stock unit, placed by raycast onto the
   terrain, aligned to the terrain normal while dragging. (`docs/05`, `docs/06`)

## Scope, as decided (`QUESTIONS-TODO.md`)

**In scope:**
- Both BZP-convention maps and plain base-game maps (Q2).
- Live enumeration of units from the user's own install — base game **and**
  BZP asset layers, combat units and buildings, not just props (Q3).
- The best viewport fidelity achievable: real meshes and real terrain atlas
  splatting, with a defined degradation chain when an asset can't be loaded
  (Q4, Q5).
- Manual material painting **and** auto-paint (Q5).
- Opening and editing **all** maps — stock, BZP, generated, community — with
  verbatim preservation of everything the editor did not touch (Q7).
- Validation report panel on save (Q8).
- Packaging buttons: install to test mod dir, render thumbnail, assemble pack
  (Q9).
- Undo/redo, a ramp brush, and per-map water and plant meshes (Q10).

**Out of scope:**
- **Tunnels and everything in the generator repo's `tunnel-testing/`.**
  Excluded in full, by explicit instruction. Not deferred-with-hooks; absent.
- Writing new units, weapons, ODFs, or textures. The editor places existing
  assets; it is not an asset authoring tool.
- Campaign / single-player mission scripting, AI paths beyond what `bzmap`
  already round-trips, and netcode.
- Reimplementing the game's file formats in GDScript (Q1 — the backend does
  this).
- Binary BZN *writing*. Reading stock binary BZNs is in scope (Q7 requires it);
  saving converts to ASCII, with the conversion surfaced to the user.

## Definition of done

The project is done when all of the following hold:

1. A map created from scratch in the editor — new-map wizard, sculpted terrain,
   placed objects, filled metadata — saves and then **loads in BZ98R and plays**,
   with a clean `BZLogger.txt`.
2. A **stock or BZP map opens, is modified in one place, and saves such that
   every file the edit did not touch is byte-identical to the original.** This
   is the round-trip guarantee made visible; it is the strongest single test of
   the whole architecture.
3. All four mandatory features work on a **5120 m map** at interactive frame
   rates (`docs/03` §6 defines the target).
4. Undo/redo is correct across sculpting and object edits, including
   interleaved sequences.
5. The validation panel reports the same findings the `bzmap` CLI validators do
   — no editor-side reimplementation, no divergence.
6. Linux and Windows exports both run and both find a real game install.
7. A person who is not the operator can clone the public repo, follow the
   README, and build it.

## What "success" is not

- Not a Godot *editor plugin*. Exported Godot games contain no editor tooling;
  every gizmo, brush, and panel here is application code we write. This is a
  standalone app.
- Not a map *generator*. `bzmap` generates; this edits. Where generation is
  useful (auto-paint materials, bake a lightmap, scatter a plant field) the
  editor calls the generator rather than growing its own.
- Not a replacement for in-game testing. The editor shortens the loop; the
  operator's rule stands — **nothing is verified until it is played.**
