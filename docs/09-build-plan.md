# 09 — Build plan

Phases are ordered so that **the riskiest unknowns are answered first** and so
that every phase ends with something runnable. Each has acceptance criteria that
are checkable, not "it looks right" (`AGENTS.md`, definition of done).

Skippy builds in this order. Do not start a phase whose predecessor's criteria
have not passed.

---

## Phase 0 — Ground truth

**Nothing here is editor code.** It is the discovery that stops later phases
from being built on guesses.

1. Inventory a real BZ98R install: where do ODFs, meshes, and textures actually
   live — loose, or packed in `.zfs`? What model formats are present? Is there
   an HD model format distinct from legacy `.geo`/`.sdf`, and is it decodable?
2. Record the findings in the **generator repo's** format docs, in that repo's
   house style (VERIFIED / INFERRED, with the measurement).
3. Confirm Godot 4.7 stable is installed and exports for Linux and Windows.
4. Confirm `bzmap` runs on both target OSes, and note what its dependency setup
   takes on Windows.

**Acceptance:** a written asset-storage finding in the generator repo, and a
"hello world" Godot 4.7 project that exports and runs on both platforms.

**If the game is not installed on the build machine**, this phase blocks on the
operator. Say so, and start Phase 1 against synthetic data — the bridge does not
need real assets to be built and tested.

---

## Phase 1 — The bridge

Build `bzmap editor` (in the generator repo) and `Backend.gd` (here), against
the contract in `docs/02`.

Verbs, in order: `probe`, `worlds`, `new`, `open`, `save`, `validate`. Leave
`assets`, `render`, and `package` for later phases.

**Acceptance:**
1. `bzmap editor open` on a stock BZP map, then `save` with **no edits**,
   produces a file set **byte-identical to the original** — every file. This is
   the round-trip guarantee crossing the session boundary, and it is the single
   most important test in the project.
2. Same test on a **multi-zone map** (2560 m or larger). Single-zone maps cannot
   catch zone-layout bugs; the generator repo shipped a MAT bug that stayed
   invisible until the first multi-zone map reached the game.
3. Same test on a **binary** BZN, where the expectation is instead: the ASCII
   output re-opens and validates cleanly, and the conversion is reported.
4. `new` produces a session that `save` turns into a file set passing
   `bzmap editor validate` with zero errors.
5. A backend crash mid-call leaves the editor running with the session intact.

No viewport yet. Test through a headless harness or a debug panel.

---

## Phase 2 — Terrain in the viewport

`docs/03`. Render the heightmap, fly around it.

**Acceptance:**
1. A stock 5120 m map loads and renders correctly — spot-check heights at known
   grid positions against the backend's own `sample_m` values.
2. Camera controls per `docs/03` §6, with speed scaling that makes a 5120 m map
   crossable.
3. **60 fps at 5120 m** with the camera moving (`docs/03` §7).
4. Analytic raycast returns hits agreeing with bilinear `height_at()` to within
   a centimetre, verified across slopes and cell boundaries.
5. Debug overlay reporting frame time, chunk count, and uploaded bytes.

---

## Phase 3 — Sculpting

`docs/04`, plus undo from the first commit.

**Acceptance:**
1. Raise/lower, flatten, smooth, and ramp all work, projected onto the terrain,
   resizable in metres.
2. Clamping holds at raw 1 and raw 4095, surfaced in the UI rather than silent.
3. **Undo/redo is correct across interleaved sculpt and object operations** —
   test a 20-operation mixed sequence undone and redone completely.
4. Brush cost is proportional to brush area, not map area: uploaded bytes per
   stroke measured and asserted.
5. **A sculpted map saves, and the saved `.hg2` re-opens with identical
   heights.** Round-trip through the real format, not just in memory.
6. The ramp tool's live slope readout matches the slope measured in the saved
   map.

---

## Phase 4 — Assets

`docs/05`. Needs Phase 0's findings.

**Acceptance:**
1. `bzmap editor assets` enumerates classes from a real install, base game and
   BZP, with layer attribution.
2. The fidelity chain works: at least one class at each achievable level, and
   `proxy` fallbacks carry **correct footprint and height**, measured.
3. Unresolved classes are listed, not silently dropped.
4. Cache rebuild works, and a changed install fingerprint prompts it.
5. **Terrain atlas splatting renders a stock map recognisably.** Compare against
   the same map in game and record whether the inferred MAT bit layout holds —
   this is the E3 experiment (`docs/05` §4). Either outcome is a result; write
   it into the generator repo.

---

## Phase 5 — Object placement

`docs/06`.

**Acceptance:**
1. Palette lists every enumerated class, filtered by pack context, searchable.
2. Raycast placement with terrain-normal alignment on the ghost.
3. Objects re-snap when terrain beneath them changes, and the re-snap undoes
   with the sculpt.
4. Selection, gizmos, multi-select, copy/paste, delete — all undoable.
5. **Placement mode is honoured on save**: verified classes emit BZN blocks
   cloned from templates; unverified classes emit runtime spawns in the
   `MAP.lua`. Verify by reading the saved files.
6. Variant rules are enforced or warned: no economy in the base variant, full
   spawn ring in base/`_ST`/`_SW`, side-grouped `_SW` spawns.

---

## Phase 6 — Map data, metadata, and packaging UI

`docs/07`, `docs/08`.

**Acceptance:**
1. New-map wizard: stem length enforced, dimensions constrained to multiples of
   1280, nine worlds offered, pack context set.
2. Every metadata field in `docs/07` §3 editable, with raw views available.
3. `.des` counts derive from real object counts.
4. Validation panel shows backend findings, and clicking one flies the camera
   to it.
5. Packaging buttons work: render, install to test mod, assemble pack.
6. Water and plant authoring produces meshes that the debug render shows in the
   right place — verify *placement*, not counts.

---

## Phase 7 — Ship

**Acceptance:**
1. **The end-to-end test**: a map authored entirely in the editor loads in
   BZ98R and plays, with a clean `BZLogger.txt`. (`docs/00` DoD #1.)
2. **The preservation test**: a stock map opened, edited in one place, saved —
   every untouched file byte-identical. (DoD #2.)
3. Linux and Windows exports both run and both find a real install.
4. Backend bundling resolved for Windows, or the setup documented clearly
   enough that a non-operator can follow it (`docs/02` §7).
5. README, build instructions, and a user guide written for someone who is not
   the operator.
6. Hotkey reference complete and rebinding persists.

---

## Ordering notes

- **Phase 1 before anything visual.** If the round-trip does not survive the
  session boundary, every later phase is building on sand. It is also the
  cheapest phase to test.
- **Phase 2 and 3 before assets.** Sculpting is the feature most likely to have
  a performance problem, and performance problems found late are architectural.
- **Phase 4 can slip without blocking 5.** Placement works against proxy boxes;
  fidelity is an improvement to it, not a prerequisite. If asset formats turn
  out to be a research project, ship placement on proxies and keep going.
- **Do not defer undo.** It is inside Phase 3, not after it.
