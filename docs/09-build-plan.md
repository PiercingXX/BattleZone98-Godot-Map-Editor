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

1. ~~Inventory a real BZ98R install: where do ODFs, meshes, and textures
   actually live?~~ **DONE 2026-08-16** — `docs/10` Q-A. Assets are loose on
   disk; `.zfs` is only needed for stock (non-BZP) maps. Layout in `docs/05`
   §2.
2. ~~Is there an HD model format distinct from legacy `.geo`/`.sdf`, and is it
   decodable?~~ **DONE** — it is OGRE, fully specified in `docs/formats/F7`.
   All other formats are specified in `docs/formats/F1`–`F8`.
3. Carry the findings into the **generator repo's** format docs, in that repo's
   house style (VERIFIED / INFERRED, with the measurement). `docs/formats/` is
   the source; three corrections it makes to that repo are listed in `docs/10`
   (E3, E7, and the VDF record stride).
4. ~~Confirm Godot 4.7 stable is installed and exports for Linux and Windows.~~
   **DONE on Linux 2026-08-16** — Godot 4.7.1.stable is on `PATH`; the
   hello-world project in this repo imports and runs headless. Export
   templates are not installed here, so a Windows `.exe` was not produced.
   Tracked in `docs/10` Q-I.
5. Confirm `bzmap` runs on both target OSes, and note what its dependency setup
   takes on Windows. **Linux: yes**, via the sibling `.venv` (Python 3.14 +
   numpy/Pillow/scipy). Windows still operator-blocked.
6. **Verify install discovery on Windows** (`docs/05` §2a). The Linux paths are
   confirmed on the operator's machine; the Windows registry keys and the
   `libraryfolders.vdf` parse are **written and implemented**
   (`bzmap/editor/discover.py`) **but not measured on Windows**. Check them
   against a real Windows install before Phase 4 depends on them. `docs/10` Q-I.

**Acceptance:** the format findings carried into the generator repo, a
"hello world" Godot 4.7 project that exports and runs on both platforms, and
`bzmap editor probe` correctly locating the install on **both** Linux and
Windows.

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
   grid positions against the backend's own `sample_m` values. (No 5120 m map
   on the build machine? `bzmap editor new` at 5120 plus a synthetic terrain
   fill serves until one is available — the criteria are about scale, not
   provenance.)
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

Build, in order:

1. **`bzmap editor probe` — install auto-discovery** (`docs/05` §2a). Steam App
   ID `301650`; Windows registry + `%ProgramFiles(x86)%`, Linux
   `~/.steam/steam` + `~/.local/share/Steam` + Flatpak, then
   `libraryfolders.vdf` for secondary drives, then GOG, then ask. Validates a
   candidate by requiring **both** `battlezone98redux.exe` and
   `BZ_ASSETS/common/models/`. Backend, not GDScript — the path logic gets
   written once.
2. **First-run flow in the editor**: probe, show what was found, take one
   confirmation, enumerate workshop layers as a checklist with BZP
   pre-selected, then run the converter with real progress, cancellable and
   resumable.
3. The converter and cache themselves (§2, §3, §6).

**Acceptance:**
1. **Auto-discovery finds the install with no user input on a clean profile —
   on Linux and on Windows** — and a user who moves the install or has no game
   gets a clear message rather than a stack trace. A machine with both Flatpak
   and native Steam copies resolves to one install, not two.
2. `bzmap editor assets` enumerates classes from a real install, base game and
   BZP, with layer attribution.
3. The fidelity chain works: at least one class at each achievable level, and
   `proxy` fallbacks carry **correct footprint and height**, measured.
4. Unresolved classes are listed, not silently dropped.
5. Cache rebuild works, and a changed install fingerprint prompts it.
6. **Terrain atlas splatting renders a stock map recognisably.** Compare against
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
7. The player object is singular, movable, and undeletable in every variant
   (`docs/06` §8) — attempting to delete it or place a second is refused with
   the reason shown.

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

## Testing strategy

Runs through every phase, not a phase of its own:

- **Bridge tests live in the generator repo**, in its house style: golden-file
  round-trips per verb (open→save byte-identical, with and without edits;
  multi-zone; binary-source), pass-through-rule cases driven by `dirty.json`
  fixtures, and a broken-fixture test per error code in `docs/02` §5. These run
  without the editor.
- **Editor logic tests** (gdUnit4 or GUT) for the pure parts: `HeightField`
  dirty-rect bookkeeping, `UndoStack` interleaving, brush kernels applied to
  known arrays, `TerrainRaycast` against analytic slopes. These run headless
  (`godot --headless`) in CI.
- **A fake backend** — a tiny script speaking the `docs/02` contract from
  canned responses — so editor UI flows are testable on machines with neither
  the game nor the generator repo, and so contract violations fail loudly in
  editor CI rather than at the operator's desk.
- **Visual/perf evidence is captured, not asserted**: each visual acceptance
  criterion produces a screenshot plus the numbers it was checked against, per
  `AGENTS.md`. The perf gate (Phase 2 #3) is a measured number in the phase
  notes, from the debug overlay.

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
