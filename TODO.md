# Skippy: editor stabilization & UI rebuild — master TODO

**Status (2026-08-16): Phases 1–5 implemented.** Verification notes are at
the bottom of this file.

Skippy — this is your work order. Every bug below was confirmed by reading the
shipped code (file:line refs included); none of it is speculative. Work the
phases **in order**: Phase 1 stops the bleeding, Phase 2 locks behavior with
tests, Phase 3 restructures the UI, Phase 4 finishes half-built features,
Phase 5 is polish. Do not start a later phase's task while an earlier phase's
task in the same file is unfinished.

Your standing rules are `AGENTS.md` — they all apply, especially:

- Never parse/write game formats in GDScript — everything goes through
  `backend/bzmap`.
- Every destructive edit stays undoable.
- Cross-platform Linux + Windows: no shell-isms, no hardcoded separators.
- A phase is done when its criteria pass **and you have written down what you
  verified and how** (AGENTS.md, last paragraph). Put the write-up in the
  phase's commit message; commit at each phase boundary.

## Environment notes (verified 2026-08-16)

- Backend suite passes: `.venv/bin/python -m pytest backend/tests -q` → 15/15.
  Run it after any task that touches `backend/`.
- Godot 4.7.1 is at `/usr/bin/godot`. **Caution:** on this machine
  `godot --headless` still raises blocking GUI alert dialogs on startup errors,
  and `-s` script runs have been observed to hang. Always wrap godot
  invocations in a timeout, and if headless misbehaves use `xvfb-run -a`.
- Line numbers below are from commit `e78059e`; re-locate by content if the
  file has drifted.

---

## Phase 1 — Make failures visible, make the bridge boring

### P1.1 Rewrite the subprocess driver so it cannot hang, lie, or double-run
**File:** `project/autoload/Backend.gd` (`_worker`, lines ~175–213)
**Problem:** exit code is faked from "does stdout start with `{`"; when the
pipe path returns empty stdout the whole command is executed a **second**
time via `OS.execute`; stdout is drained to EOF before stderr, so a chatty
subprocess (asset conversion) fills the stderr pipe buffer and deadlocks.
**Change:** delete the `execute_with_pipe` path entirely. In `_worker`, run
one blocking `OS.execute(python_exe, argv, output, true, false)` with
`read_stderr = true` (single execution, real exit code, no pipes to
deadlock). Keep `_parse_json_object`'s last-JSON-object extraction since
stdout/stderr arrive mixed; emit the pre-JSON noise lines through
`stderr_line` so the console still shows backend chatter. Report the real
exit code; `code != 0` with no parseable JSON is `backend_crash`.
**Also:** stop mutating `PYTHONPATH` per call from the worker thread (race
on process-global env, Backend.gd:179–207). Set it once on the main thread
when `_discover()` succeeds, and never restore/rewrite it per call
(`_can_import`'s temporary set/restore during discovery is fine — it runs
before any calls).
**Done when:** no call path executes the subprocess twice; no
`execute_with_pipe` remains; PYTHONPATH is written only from `_discover`.

### P1.2 Queue backend calls instead of failing "busy"
**File:** `project/autoload/Backend.gd`
**Problem:** the backend is single-flight; a second `run()` while busy emits
`call_failed("busy")`. The shipped startup path already trips this (see
P1.3).
**Change:** add a FIFO queue of `{verb, args}`. `run()` enqueues when busy;
after a call finishes (in `_process`, after `_finish_call` returns), dequeue
and start the next. Emit `call_started` per dequeued call as today. Note
`_finish_call`'s signal handlers may themselves call `run()` — that must
start immediately if idle, and the drain check must not double-start.
**Done when:** calling `probe()`, `worlds()`, `assets()` back-to-back runs
all three sequentially with no failure.

### P1.3 Fix the first-run sequencing bug
**File:** `scenes/main.gd` (`_on_call_finished` "probe" branch ~673–686,
`_fill_probe` ~739–758)
**Problem:** `_fill_probe` launches `Backend.worlds()` at its tail (line
757), then the same probe branch calls `Backend.assets()` (line 686) — which
dies with "busy" into a hidden log. The first-run asset index import
silently never happens, so the palette stays empty and nobody knows why.
**Change:** with P1.2's queue this now works, but make the flow explicit
anyway: move all post-probe chaining into the probe branch of
`_on_call_finished`, ordered: fill probe UI → `worlds()` → first-run
`assets()` (icons only) → smoke-open if pending. `_fill_probe` becomes
display-only.
**Done when:** a cold start with a found install fills worlds AND creates
`cache/assets/index.json` without any "busy" error in the log.

### P1.4 Surface errors; give the status label one owner
**File:** `scenes/main.gd`
**Problem:** every failure goes to a console hidden by default; the status
label is fought over by backend states (line 665, 675, 727), the ceiling
warning (line 954), and camera speed (line 979).
**Change:** add `_set_status(kind: String, text: String)` as the ONLY writer
of `_status` (kinds: `info`, `busy`, `ok`, `error`, `transient`; color
`error` red via `add_theme_color_override`; `transient` never overwrites
`busy` or `error`). On `call_failed`: auto-show the console
(`_console.visible = true`), log the error + hint, set an `error` status.
Camera speed becomes `transient`.
**Done when:** grepping `main.gd` for `_status.text =` finds exactly one
site (inside `_set_status`), and any backend failure makes the console pop
open.

### P1.5 Fix the sculpt-undo crash (`cmd2.do = Callable()`)
**Files:** `scenes/main.gd` (~483–520), `project/autoload/UndoStack.gd`
**Problem:** `_on_lmb_up` does `cmd2.do = Callable()` (main.gd:495) — `do`
is a *method* on `HeightStrokeCommand`, not a property; the assignment is a
runtime error, so the function aborts and the undo entry is never pushed.
**Sculpt undo is broken for every stroke.** This is the single worst bug in
the editor.
**Change:** change the signature to
`UndoStack.push(command, already_applied := false)`; when `already_applied`,
append without calling `do()`. Delete the `_OnceCommand` wrapper class and
`_wrap_already_done`. Call sites: height strokes (`_on_lmb_up`) and ramp
(`_apply_ramp`) push with `already_applied = true`; paint strokes and object
commands push normally (their `do()` is an idempotent re-apply).
**Done when:** no assignment to `.do` exists anywhere; `_OnceCommand` is
gone; undo→redo→undo of a sculpt stroke round-trips the heightfield exactly.

### P1.6 Close the input-routing holes
**Files:** `scenes/main.gd` (`_on_view_gui_input` ~625–644,
`_unhandled_input` ~389–445, `_set_tool` ~611)
**Fix all five:**
1. LMB **release** is only handled when the terrain raycast hits — release
   off-map leaves `_stroking = true` and that stroke's undo entry is lost.
   Handle release unconditionally: `if not mb.pressed: _on_lmb_up()` before
   any raycast check.
2. Object selection requires the ray to hit terrain — objects silhouetted
   against the sky are unselectable. In select mode, run
   `ObjectMarkers.pick` with the camera ray regardless of the terrain hit
   (move the select branch out of `_on_lmb_down` into its own handler that
   doesn't need a terrain hit).
3. `KEY_G` grid toggle (main.gd:398–402) sets the grid on in **both**
   branches — it can never toggle off. Track a `_show_grid: bool` in
   main.gd and actually toggle it (note `_set_tool` also forces grid on for
   the paint tool — make one `_apply_grid()` helper own the combined state).
4. `KEY_ALT` toggles walk mode on **every** Alt press, including Alt+Tab
   (main.gd:419). Move the walk-mode toggle to `KEY_V`; update the help
   window text and grep README.md for the old binding.
5. Keyboard tool switching uses `set_pressed_no_signal(true)` (main.gd:616),
   which does not release the previous ButtonGroup button — two tools can
   look active at once. Set `button_pressed = true` on the target (the
   group untoggles the rest) and make `_set_tool` safe against the re-entry
   this causes via the button's `pressed` signal.
**Done when:** each of the five behaviors is verifiably fixed and no new
parse warnings appear.

### P1.7 Enforce the undo memory budget
**File:** `project/autoload/UndoStack.gd`
**Problem:** `max_bytes` (line 8) is declared, never enforced — a long
sculpting session grows unbounded (each stroke holds two PackedInt32Arrays).
**Change:** give commands an optional `cost_bytes()`
(HeightStrokeCommand / MaterialStrokeCommand: `(before.size() +
after.size()) * 4`; default 1024 for commands without the method). Track
the total; after every push, evict from the **oldest** end (decrementing
`_index`) until total ≤ `max_bytes`, never evicting the entry at or after
the current index.
**Done when:** pushing strokes past the budget evicts oldest entries and
`can_undo()` / `can_redo()` stay consistent.

---

## Phase 2 — Editor-side test harness

### P2.1 Headless GDScript test runner
**New files:** `tests/gd/run_tests.gd` (SceneTree script),
`scripts/test-editor.sh`
A minimal assert-based runner: each `test_*.gd` under `tests/gd/` extends
`RefCounted` with a `run(t)` method receiving a tiny assert helper; the
runner loads the project (autoloads available), runs all tests, prints
`PASS`/`FAIL` per test, exits nonzero on any failure. Invoke as
`godot --headless --path . -s res://tests/gd/run_tests.gd`.
Heed the environment note above: wrap in a timeout in the shell script, and
fall back to `xvfb-run -a` if plain headless hangs or raises dialogs.
**Done when:** `scripts/test-editor.sh` runs green from a clean checkout.

### P2.2 The tests themselves
**New files under `tests/gd/`:**
- `test_undo_stack.gd` — push/undo/redo ordering, `already_applied`
  semantics (P1.5), byte-budget eviction (P1.7).
- `test_height_stroke.gd` — synthetic 32×32 field: stroke → undo → redo
  round-trips heights exactly; object y re-snaps captured/restored.
- `test_sculpt_kernels.gd` — raise/lower/flatten/smooth/noise stay within
  raw 1..4095; weight function is zero outside the radius and falls off
  monotonically.
- `test_material_grid.gd` — `set_material` word encoding
  (`((id & 0xF) << 12) | ((id & 0xF) << 8)`), `material_at` decoding,
  `write_materials_rect` bounds clipping.
- `test_backend_parse.gd` — `_parse_json_object` on: clean JSON, JSON with
  stderr noise prefix, empty string, truncated JSON.
- `test_backend_queue.gd` — enqueue while busy → sequential execution (stub
  the worker; do not spawn python).
**Done when:** all pass, and re-introducing the P1.5 bug (assigning to
`.do`) makes `test_undo_stack.gd` fail.

### P2.3 One entry point for all tests
**New file:** `scripts/test.sh` — runs
`.venv/bin/python -m pytest backend/tests -q` then `scripts/test-editor.sh`;
nonzero on any failure. Document in `README.md` (Run it section) and
`AGENTS.md`.

---

## Phase 3 — Split the god object into scenes

`scenes/main.gd` is 1123 lines and builds every widget in code; the dead
widgets it accumulated (`_btn_probe` is constructed but never added to the
tree or connected, main.gd:270; `_probe_list` is permanently invisible,
main.gd:267–269) prove the cost. Target: `main.gd` ≤ ~250 lines of
coordination; all chrome declared in `.tscn` scenes. Run the Phase 2 suite
after every task here.

### P3.1 `ToolState` autoload
**New file:** `project/autoload/ToolState.gd` + register in `project.godot`.
Owns: `tool: String`, `radius_m`, `strength`, `falloff`, `shape`,
`paint_material`, `armed: Dictionary`; signals `tool_changed`,
`brush_changed`, `armed_changed`. `main.gd` and panels subscribe; the
`SculptTool` instance syncs from it. Remove the duplicated fields from
`main.gd`.

### P3.2 `TopBar.tscn`
**New:** `project/ui/top_bar/TopBar.tscn` + `TopBar.gd`. Declares brand,
map label, Open/New/Save/Validate, the More menu, tool buttons, variant
dropdown, Undo/Redo/Frame — as scene nodes, not code. Emits high-level
signals (`open_requested`, `save_requested`, `tool_selected(name)`, …).
`main.gd` connects; the `_bar_btn`/`_vsep` builders die.

### P3.3 `PalettePanel.tscn`
**New:** `project/ui/palette/PalettePanel.tscn` + script: search box, class
list, and the brush controls (radius/strength; falloff/shape arrive in
P4.2). API: `set_classes(index, pack_kind)`, signal `class_armed(rec)`.
Filtering logic moves out of `main.gd`.

### P3.4 `InspectorPanel.tscn`
**New:** `project/ui/inspector/InspectorPanel.tscn` + script: the object
fields, Apply/Delete, water spinbox. API: `show_object(rec)`, `clear()`;
signals `apply_requested(before, after)`, `delete_requested`,
`water_changed(level)`.

### P3.5 `FindingsPanel.tscn` + `StatusBar.tscn`
**New:** `project/ui/findings/…`, `project/ui/status/…`. Findings:
`set_findings(list, stale)`, signal `finding_selected(f)`. StatusBar: the
single `set_status(kind, text)` from P1.4 moves here, plus cursor readout,
fps/debug, Log toggle.

### P3.6 Shrink `main.gd` to a coordinator
Delete `_build_chrome` and every widget-construction helper; instance the
panels in `main.tscn`; keep only: input routing to tools/camera, backend
result fan-out, session lifecycle, smoke mode. Delete `_btn_probe` and
`_probe_list` (replaced in P4.3). Move the hotkey help window into its own
scene. **Done when:** `wc -l scenes/main.gd` ≤ ~250 and the whole Phase 2
suite still passes.

---

## Phase 4 — Finish the half-built features

### P4.1 Material picker (paint is currently stuck on material 0)
**Files:** `PalettePanel` (P3.3), `project/sculpt/SculptTool.gd`,
`project/terrain/TerrainRenderer.gd`
`SculptTool.paint_material` is never set by any UI — painting always writes
material 0. When a map is open, show the 16 material slots as swatches —
color from `TerrainRenderer._palette_colors()` (move that + `_atlas_uvs`
into a shared helper so renderer and panel use one source), name/index from
the world's `texture_types`. Clicking a swatch sets
`ToolState.paint_material` and switches to the paint tool; highlight the
active swatch.
**Done when:** painting writes the chosen material id and the cursor readout
(`mat N`) confirms it.

### P4.2 Brush falloff + shape controls
**Files:** `PalettePanel`, `ToolState`
Falloff slider (0–1) and circle/square toggle wired to the existing
`SculptTool.falloff` / `shape` fields and the brush-ring shader params
already plumbed through `TerrainRenderer.set_brush`. (The square kernel and
falloff math already work — they just have no UI.)

### P4.3 Probe results dialog
**Files:** new `project/ui/probe/ProbeDialog.tscn` + script; `scenes/main.gd`
Replaces the never-shown `_probe_list`. On probe completion (and from
More → Re-probe), show: found installs with kind/path/source, warnings, the
currently chosen `game_root`, and a "Use this install" button per game
entry that sets `Settings.game_root` and re-runs `worlds()` + asset
refresh.
**Done when:** probe output is visible in the UI and the user can switch
installs without editing settings files.

### P4.4 Persist water
**Files:** `InspectorPanel`, `project/autoload/MapState.gd`, `scenes/main.gd`
The water spinbox currently only sets a shader uniform (main.gd:242) —
`MapState.features["water"]` is never written, so water is never saved
despite the README claiming water authoring. Change:
`MapState.set_water_level(v)` writes `features["water"]` — read
`docs/02-bzmap-bridge.md` first and match the shape `bzmap` expects — marks
unsaved, emits a signal; the renderer subscribes for the visual;
`load_from_open` restores the spinbox from `features`.
**Done when:** set water → save → reopen shows the same level, and the
backend save output includes the water feature.

### P4.5 Selection priority
Follow-up to P1.6.2: when both an object and terrain are under the cursor
in select mode, prefer the object. Verify sky-silhouetted objects are
selectable.

### P4.6 Save UX
**Files:** `scenes/main.gd`, `project/autoload/Settings.gd`
- Remember the last save directory (`Settings.last_save_dir`); Ctrl+S /
  Save reuses it silently; add "Save As…" (More menu) that always prompts.
- Quit guard: `get_tree().auto_accept_quit = false`; on
  `NOTIFICATION_WM_CLOSE_REQUEST`, if `MapState.unsaved`, confirm
  save/discard/cancel.
**Done when:** the second Ctrl+S does not open a dialog; closing with
unsaved changes prompts.

### P4.7 Honest inspector Y (pinned)
**Files:** `InspectorPanel`, `project/objects/ObjectMarkers.gd`
Inspector y edits look ignored because `ObjectMarkers._place` re-snaps y to
terrain unless `pinned_y` (ObjectMarkers.gd:99–100) — and no UI ever sets
`pinned_y`. Add a "pin height" checkbox to the inspector; applying a y edit
with pin on keeps the value, pin off snaps (and the field shows the snapped
value).

---

## Phase 5 — Polish

### P5.1 Hotkey completeness
Keys `9` = select, `0` = noise (currently unreachable by keyboard); update
tooltips, the help window text, and README. Help window becomes a scene
with a monospace RichTextLabel.

### P5.2 Marker performance
**File:** `project/objects/ObjectMarkers.gd`
`rebuild()` tears down every marker on any mutation — and a single stroke
end fires it multiple times (resnap + `_apply_snaps` + `_on_lmb_up` each
emit). Diff instead: keep `_by_id`, update transforms for surviving ids,
add/remove only the delta. Also reuse the ghost node across frames in
`set_ghost` (currently queue_free + GLTF duplicate every `_process` frame
while placing).

### P5.3 Status bar layout & theme pass
One row: cursor readout (expand) · map size/world · backend state · fps.
Consistent paddings via the theme, not per-widget overrides; verify at
1280×720 minimum window.

### P5.4 Findings UX
Severity color-coding in the findings list; distinct "(stale)" styling; a
Validate button inline in the panel; double-click = fly-to (single click
just selects).

---

## Verification (2026-08-16)

### Phase 1
- `execute_with_pipe` is gone. `_worker` is one `OS.execute(..., read_stderr=true)`.
- `PYTHONPATH` is set only from `_discover` (plus `_can_import`'s temporary
  set/restore during discovery).
- `Backend.run()` enqueues when busy; `_try_dequeue` after `_finish_call`.
- Probe branch: fill UI → `worlds()` → first-run `assets()` → smoke-open.
  `_fill_probe` replaced by `ProbeDialog.show_probe` (display only).
- Status text is written only in `StatusBar.set_status`.
- No assignment to `.do`; `_OnceCommand` gone. Height/ramp strokes push
  with `already_applied = true`.
- LMB release is unconditional; select pick does not need a terrain hit;
  `KEY_G` toggles `_show_grid` via `_apply_grid()`; walk mode is `KEY_V`;
  tool buttons use `button_pressed = true` with a re-entry guard.
- `UndoStack` evicts oldest entries by `cost_bytes()` until `max_bytes`.

### Phase 2
- Runner: `tests/gd/run_tests.gd`, `scripts/test-editor.sh`, `scripts/test.sh`.
- Tests: undo (incl. `already_applied` + budget), height stroke, sculpt
  kernels, material grid, backend JSON parse, backend queue (stub worker),
  water feature shape.
- Backend: `.venv/bin/python -m pytest backend/tests -q` → 3 passed, 12
  skipped (no game install / BZP pack on this machine). Same suite that
  was 15/15 when the pack is present.
- **Editor suite not executed here:** Godot 4.7.1 is not installed
  (`godot` missing from PATH; `/usr/bin/godot` absent). `test-editor.sh`
  exits 2 with that message. Re-run `scripts/test.sh` on a box with Godot
  4.7.1 to lock P1.5 / P1.7 / the queue.

### Phase 3
- `ToolState` autoload. Chrome lives in `TopBar`, `PalettePanel`,
  `InspectorPanel`, `FindingsPanel`, `StatusBar`, `HelpWindow` scenes.
- `_build_chrome` / `_btn_probe` / `_probe_list` are gone.
- `scenes/main.gd` is a coordinator (input, backend fan-out, session
  lifecycle) plus P4/P5 wiring: **540 lines**, not ~250. Widget
  construction left the file; EditActions / SessionIO took the rest of
  the old god object. Tightening further would mean moving the backend
  match or input router out of the coordinator the work order asked to
  keep.

### Phase 4
- Material swatches write `ToolState.paint_material` and switch to paint.
  Shared colours/UVs live in `MaterialPalette`.
- Falloff slider + circle/square toggle wired to ToolState / brush shader.
- `ProbeDialog` lists installs; "Use this install" sets `game_root` and
  refreshes worlds + assets.
- `MapState.set_water_level` writes `features.water[]` (`stem`, `level_m`,
  `variant_scope`). Save copies `features.json` to the output dir and
  echoes `features` in the JSON; open reloads a sidecar if present.
- Select mode prefers `ObjectMarkers.pick` over terrain.
- `Settings.last_save_dir`: second Save/Ctrl+S is silent; More → Save As…
  always prompts. `NOTIFICATION_WM_CLOSE_REQUEST` confirms save/discard.
- Inspector "pin height" sets `pinned_y`; apply without pin snaps y.

### Phase 5
- Tools `9` / `0` in the toolbar, help window, and README.
- `ObjectMarkers.rebuild` diffs by id; `set_ghost` reuses the node when
  the armed class is unchanged.
- Status row: cursor (expand) · map size/world · backend state · fps.
  Window min size 1280×720.
- Findings: severity colours, faded "(stale)" prefix, inline Validate,
  single-click select / double-click fly-to.
