# TODO — handoff

Written for whoever picks this up next, on a machine that has a **real GPU** and
a **Battlezone 98 Redux install**. The box this branch was built on had neither,
which is the single biggest limitation on everything below.

Branch: `borrow-from-field`. **Nothing has been pushed. Do not push without
asking the repo owner.**

---

## Read this first — what could not be verified here

The build machine had:

- **No working Vulkan.** `VK_KHR_surface` was missing, so Godot fell back to the
  OpenGL 3 compatibility renderer. The project ships `forward_plus`.
- **No BZ98 install.** So no real `.trn`, `.bzn`, `.hg2`, atlas, ODF or mesh data
  was ever loaded.
- **No corpus fixtures.** `tests/gd/fixtures/bzn/*.bzn` are gitignored under
  `AGENTS.md` rule 3, so five test files skip.

Everything marked ⚠️ below is reasoned, tested headlessly, or checked against
synthetic data — but never seen working against the real thing.

---

## Verified on a real box — 2026-08-22

A second machine now has everything the build box lacked: **Godot 4.7.2 stable**,
an **AMD RX 7900 XTX** on **Vulkan 1.4.354** (so genuinely Forward+, not the
compatibility fallback), and a **Battlezone 98 Redux install**. What follows was
run there. Items still marked ⚠️ below this section were *not* covered.

The suite reproduces the predicted baseline exactly: **126 passed, 0 failed,
5 skipped, 3 with script errors.**

**Terrain under Forward+ — the highest risk — holds up.** The clipmap renders a
complete, crack-free surface at 100 / 400 / 1200 / 2500 / 5000 m above the
surface, and through a full eight-step 360° yaw sweep at 250 m, which is when the
rings re-snap. The fragment `discard` behaves the same under a Forward+ depth
prepass as it did on the compatibility backend. No holes, no cracks, no popping
between rings.

**2D orthographic map mode renders north-up**, checked two independent ways: the
camera's own mapping (`unproject_position` puts +z above centre and +x right of
it) and the pixels that actually land in the frame — raise a plateau at the NW
quarter and it appears top-left (centroid 0.28, 0.26), raise one at the SE
quarter and it appears bottom-right (0.72, 0.73). Those centroids match what the
ortho framing predicts analytically (2560 m map in a 2765 m frame → 0.268 /
0.732). The mirrored render has not come back.

**Real map data renders.** Pointed at the install, all nine stock worlds resolve
with PNG atlases that exist on disk. A stock 2560 m Ganymede map draws with real
atlas materials, a 128×128 `.mat` grid and visible autotile transitions — rock
cliff faces, sand valley floor, no white blowout.

**C6 byte-identical round-trip, on real maps — the one that mattered.** Every
map in the install with a complete `.trn` + `.hg2` set was opened and saved with
no edits: **40 maps, 553 game files, zero byte differences.** The only file
written that the source lacks is `features.json`, the session sidecar, which is
expected. Then on a stock map, through the real `MapState.persist()` +
`Backend.save_map` path:

- open → sculpt → save, versus open → sculpt → undo → redo → save:
  **byte-identical, every file.**
- open → save, versus open → sculpt → undo → save: every shared file
  byte-identical (the `.hg2` included, so undo restores the heights exactly) —
  but the file *sets* differ by one. See `.lgt` under "Known issues".

Re-run after the fixes below landed: still **40 maps, 553 files, zero byte
differences**, and open → sculpt → undo → save now matches open → save across
the whole directory on both a 2x2-zone and a 4x3-zone non-square map.

Defects surfaced doing this are recorded under "Fixed on 2026-08-22".

---

## First five minutes on the new box

```bash
# 1. Point at a real Godot 4.7 stable
export GODOT=/path/to/Godot_v4.7-stable_linux.x86_64

# 2. Full suite. Expected everywhere, install or no install:
#    132 passed, 0 failed, 0 skipped, 0 with script errors.
#    Nothing is conditional on having the game any more — the .bzn fixtures
#    are synthetic and committed. CI runs with GODOT_TEST_STRICT=1.
scripts/test-editor.sh

# 3. Launch it
godot --path .
```

Then: **Probe** (finds your Steam install) → **Open map…** → pick a `.trn` /
`.bzn` / `.hg2`.

---

## Smoke-test checklist, in priority order

Ordered by "most likely to be broken, and worst if it is".

### 1. ⚠️ Terrain rendering under Forward+/Vulkan — HIGHEST RISK
The terrain is now a **geometry clipmap** (`project/terrain/TerrainClipmap.gd`),
replacing 64 fixed full-density chunks. The fragment shader gained a `discard`
outside the map bounds, and that is the one construct whose behaviour could
differ under a Forward+ depth prepass versus the compatibility backend it was
tested on.

Check:
- [x] Terrain renders at all, with no holes or cracks, at 100 m / 400 m /
      1200 m / 2500 m / 5000 m camera height — verified 2026-08-22
- [x] No cracks while flying — especially rotating in place, which is when the
      clipmap rings re-snap — verified over a 360° sweep, 2026-08-22
- [x] 2D orthographic map mode (the `Space` / compass-hub toggle) renders
      correctly and **north-up** (+z at the top). A mirrored render shipped once
      before and must not recur — see `docs/02-bzmap-bridge.md:49-53`.
      Verified 2026-08-22, camera mapping and pixels both
- [x] Walk-the-surface mode (`V`) — exercised 2026-08-22, and it is broken for
      mouse navigation. See "Known issues"
- [ ] Distant terrain is **expected** to be coarser: 10–160 m quads instead of
      5 m. Shading detail survives, silhouettes do not. That is the LOD trade,
      not a bug. Judge whether it is acceptable for this game.

### 2. ⚠️ Real map data through the new render path
Never drawn against real content:
- [x] Atlas / tile-LUT rendering — do materials look right? Yes, on a stock
      Ganymede map; all nine worlds resolve a PNG atlas
- [ ] `.mat` overlay, feature mask, selection mask
- [ ] Brush ring / cursor decal
- [ ] Slope overlay, grid overlay

### 3. ⚠️ Byte-identical round-trip on real maps — THE ONE THAT MATTERS
The whole project rests on this and it could only be proven here on the `.hg2`
terrain path using a shipped template. **The object-side (`.bzn`) path is
unproven.**
- [x] Open a stock map, change nothing, save. Every file byte-identical.
      **40 maps / 553 files / 0 differences**, 2026-08-22
- [x] Open, sculpt, undo, save. Byte-identical to the untouched save. Was off
      by a dropped `.lgt` until the stale-dirty-flag fix; now identical across
      the whole directory, checked on a 2x2- and a 4x3-zone map
- [x] Open, sculpt, undo, redo, save. Byte-identical to save-without-undo.
- [x] Same for a multi-zone map, and for a non-square map if you have one.
      The 40-map sweep covered 1×1, 2×2, 3×3 and 4×4 zones plus two non-square
      maps (1×3 and 4×3 zones) — all byte-identical. Note an untouched save
      copies the `.mat` from residue, so this does *not* exercise the shape
      inference; that was checked separately, see "Known issues"

### 4. Live sculpting end to end
Never exercised interactively.
- [ ] Sculpt feels responsive on a 5120 m map — this is a stated correctness
      requirement (`AGENTS.md` rule 6), not polish
- [ ] Undo/redo across long strokes
- [ ] Objects re-snap to terrain height inside the edited region, and that
      re-snap undoes correctly

---

## New in this branch — what needs eyes on real hardware

Ten features landed. All are unit-tested headlessly; **none has been seen on a
screen or run against real game data.** Ordered by how likely a smoke test is to
find something.

### Scatter preview — misses its frame budget ⚠️
`project/scatter/`. Plants are finally visible in the viewport (they were a green
mask tint before). But a **cold chunk costs 40–75 ms against the ~1000 µs
budget** — 3–15× over. The queue caps damage at one chunk per frame and the cache
means you pay it once per chunk per session, but `AGENTS.md` rule 6 calls this
correctness.

Diagnosed cause: per-instance `TerrainRaycast.normal_at` at ~40 µs a call. The fix
is a cached per-cell slope field; it was not written because it duplicates
`TerrainRaycast`'s maths and wants a considered home. **This is the highest-value
performance follow-up in the branch.** Note the numbers carry ±2× uncertainty —
they were measured with nine sibling agents loading the box. Re-measure first.

### Procedural generation — blocks for 12.5 s at 5120 m
`project/generate/`. Four presets (mesa / crater / highlands / canyon), thermal +
droplet erosion, seeded and cross-process deterministic. Buildable-area figures
land where an RTS wants them (mesa 76%, canyon 67%), scored against the project's
own `BzCheckBalance` / `BzCheckConnectivity` thresholds.

`generate()` is synchronous. A full-res apply on the largest map takes ~12.5 s, so
the dialog **must** show a busy state or it reads as a hang.

One residual cross-platform risk, quantified rather than hand-waved:
`FastNoiseLite`'s C++ float arithmetic is the only unpinned element. Worst case a
few hundred cells in a million differ by one raw unit between Linux and Windows.
This does **not** affect C6 — a generated field is written once and read back
verbatim — it would only show if two users generated "the same seed" on different
OSes and diffed. `FbmNoise` is the single swap point if it ever matters.

### Autotile scoring — draws different art in one case ⚠️
`project/terrain/MaterialAutotile.gd`. Best-score matching degrades gracefully
where the old exact-match table left holes. Deterministic per-cell seeded
variants.

**Documented behaviour change:** a cell whose N and S neighbours differ while E
and W agree used to always take the north cap; it now picks between the tied caps
by seed. Deterministic, but it *will* look different in the viewport. Judge
whether the new art is acceptable before trusting it on a real map.

`absorb_missing` is off by default. On, a thin atlas lends its cap to types it
ships nothing for — the "no holes" payoff — but it draws a boundary the tileset
never intended.

### Splines — feathered rim is not idempotent
`project/spline/`. Curve-to-ribbon plus flatten-along-curve, covering roads,
ramps, rivers and walls. Curved ramps climb evenly: 0.1 m worst deviation against
an independent oracle, versus 2.6 m for the naive approach.

A falloff blend toward a target is inherently non-idempotent at its edges, so
**re-carving the same road nudges the rim again**. Judged correct rather than a
defect, but it is exactly the kind of thing that reads as a bug later. The `hard`
profile is idempotent.

No in-viewport curve editing — the API is there, the gizmos are not.

### Brushes — six generated tips, four new modes
`project/sculpt/`. Mask tips (`disc`, `soft`, `ring`, `square`, `chisel`,
`grain`), stroke spacing, pen pressure, random rotation, slope/height-limited
painting, real `FastNoiseLite` noise replacing two hardcoded sine waves, plus
`erode`, `dilate`, `setheight`, `setangle`. Brush settings now persist.

Unverified: **pen pressure end to end** (no tablet here), and every visual aspect
— tip shapes, rotated stamps, limit bands, the brush ring.

Two known gaps: terrain *selection* strokes still use the analytic circle/square,
not mask tips; and the brush ring preview in the shader does not know about tips
or rotation.

### Minimap — deliberately CPU-shaded
`project/ui/minimap/`. Relief / slope / material / scatter overlays, camera
position **and heading**, click-to-fly, findings markers.

Shading is CPU, not a shader, on purpose: headless Godot runs the dummy driver, so
a shader pass cannot be pixel-asserted, and a mirrored render is the one defect
this panel has a documented history of. North-up is verified by rendering a raised
block at each of the four corners in turn and asserting the bright quadrant — then
mutation-checked by inverting the mapping and confirming 20 assertions fail.

Unverified: the *look* at dock size. Colour balance, contrast, whether the camera
arrow reads against relief.

### 3D asset thumbnails — never rendered
`project/thumbnails/`. Batched N×N offscreen rendering with its own `World3D`,
recursive visual AABB framing, cache keyed on path+mtime+size.

**Nothing here has put a pixel on a GPU.** The framing maths and the batch slicing
are verified against synthetic meshes and mutation-checked, but the readback
sequence, transparency, and lighting are all unproven. Specific unknowns:

- Does the readback produce an image at all? If icons come back blank this is the
  first suspect. `is_blank()` refuses to cache them, so the failure mode is "no
  thumbnails" rather than a cache full of blanks.
- Does `transparent_bg` + MSAA 4× actually yield alpha, or opaque black?
- **Which way do BZ meshes face?** The default yaw may show units three-quarter
  *rear* rather than front. Bump `ThumbnailCache.REV` after changing it.
- Frame cost on a full install — glTF load, not render, is the likely offender.

### Command palette and plugin registry — ⚠️ read the trust model
`project/commands_registry/`, `project/ui/command_palette/`. 21 starter commands,
fuzzy search, two-root scan.

**`user://commands` is not sandboxed.** A `.gd` dropped there is `load()`ed and
instantiated in-process at startup with the editor's full authority: filesystem
access including the game install, `OS.execute`, network, and the ability to
silently override a built-in command id. The registry's checks are *shape* checks
— they stop a broken plugin breaking startup, not a hostile one doing harm. Treat
that folder like a folder of executables.

This is the normal trade for drop-in extensibility, but it should be a decision
you have made, not a surprise. Consider whether it wants an opt-in setting.

### Autotile — a SECOND output change, beyond the tie-break
`MaterialAutotile.context()` defaults `variants: true`, so caps and diagonals now
roll among the atlas variants for a pair, where the old path always emitted
variant 0. Seeded per cell, so stable across undo/redo/reopen and C6-safe — but
**visibly different on any world shipping more than one variant per transition.**
This was not in the original design brief; it surfaced during integration. Look at
it on a real map before trusting it.

### New brush keybindings are E / Shift+E / T / Shift+T
Not H as originally planned — `slope_overlay` already owns plain `H` in the godot
scheme, and `test_keymap` asserts zero clashes per scheme.

### Minimap collapse state does not survive a restart
The panel's collapse button works for the session but is not persisted;
`Settings.collapse_*` needs a `collapse_minimap` key. Roughly 4 lines in
`project/autoload/Settings.gd` plus 4 in `scenes/main.gd`.

### `features.json` is not a fixed point across reload
Pre-existing, found during integration. `density: 260` and `seed: 0` come back
from `JSON.parse_string` as floats and re-serialise as `260.0` / `0.0`. This is
session-sidecar data, never game bytes, so **C6 is intact** — but it is a latent
papercut that will bite the next person writing a round-trip test.

### Schema UI, self-documenting tools, theme, rebindable keys
`project/ui/schema/`, `project/ui/DarkTheme.gd`, `project/editor/KeymapRegistry.gd`.

The doc model and the property schema are **one declaration**, so per-parameter
help cannot drift from the editors. No tool has registered a `ToolDoc` yet — the
registry is empty until they declare, which is the remaining half of that
contract. `HelpWindow` still holds its 3,000-char string literal.

47 shipped keymap actions moved into an open registry with user rebinding and
conflict detection. **Mouse/modifier verbs are still hard-coded** — Alt-as-subtract,
Alt-as-erase, Alt-as-eyedropper, Alt-as-orbit are branches inside tool and camera
code, not registry actions, so they are neither rebindable nor conflict-checked.

---

## Fixed on 2026-08-22

Everything in this section was found by the verification pass above and has
been fixed, with tests. Kept as a record of what changed and why.

### Walk-the-surface mode did not clamp mouse navigation
`Settings.walk_mode` promises the eye stays 4 m above the ground, but the clamp
sat inside `FlyCamera._process`, in the branch that only runs when a WASD/QE key
is held — and that branch returns early on any frame with no key down, which is
every frame you navigate with the mouse. `_dolly`, `_truck`, `_pan_ground` and
`_orbit` all moved the camera straight past it.

Measured before: walk mode on, 120 m over the centre of a stock map, 40
mouse-wheel dolly steps toward the ground put the eye at **y = −2544 m, 2.8 km
below the surface**. After: clearance holds at exactly 4.0 m, and the camera
rides up the slope as it travels.

Fixed by lifting the clamp out of the movement branch into
`FlyCamera.enforce_walk_floor()`, called once a frame from `_process` whatever
moved the camera — which also covers terrain sculpted upward under a parked
camera. It raises only, so framing, bookmarks and `hover_point` are unaffected,
and map mode is exempt (that camera is orthographic and parked at `MAP_CAM_Y`).
`tests/gd/test_walk_mode.gd` covers each verb, both off-switches and the
degenerate-field guard.

### A sculpt dropped the `.lgt` for the rest of the session
Dropping `.lgt` on a dirty-terrain save is deliberate and correct — the
reference editor does it so the game re-bakes lighting, and shipping the residue
lightmap would light the old geometry (`BzSave.gd`, F3 §3). The trigger was
wrong. `terrain_dirty` came from `dirty.json`, falling back to comparing the
buffer against the residue heightmap, so once a sculpt set the flag it stayed
set: after a full undo, with the heights back where they started and the
re-encoded `.hg2` byte-identical, the `.lgt` was still deleted and the `.hg2`
still reported as regenerated. Saving in place destroyed the user's lightmap for
an edit they had taken back.

Fixed by making the comparison authoritative in both directions.
`_terrain_differs_from_residue` became `_compare_terrain_to_residue`, returning
DIFFERS / SAME / UNKNOWN — every failure to look is UNKNOWN, never SAME, so "I
could not check" still falls back to the flag and the original fail-open
protection is intact. A stale dirty flag with a matching buffer is now believed
to be clean.

Verified end to end on a stock map: open → sculpt → undo → save is now
byte-identical to open → save across the **whole directory**, and a real sculpt
still drops the `.lgt`. `tests/gd/test_bz_save.gd` pins both directions.

### The `.bzn` fixture recipe could not be followed
`tests/gd/fixtures/bzn/README.txt` said to regenerate with
`PYTHONPATH=backend python3` and `bzmap.formats.bzn`. There is no `backend/`
directory in this repository and no commit ever added one — the Python backend
became in-process GDScript under `project/backend/`.

Worse, the fixtures were unobtainable rather than merely un-regenerable: they
are gitignored by the blanket `*.bzn` ban, so **five test files skipped on every
fresh clone and in CI**, including the object-side save path. This document
previously said installing the game would unlock them, which was wrong twice
over — they are hand-authored synthetic files, "not corpus, not game, not BZP",
and no install supplies them.

Fixed by writing the content down as source in
`tests/gd/fixtures/bzn/make_fixtures.gd`, committing the two generated `.bzn`
files behind a targeted `.gitignore` exception (the blanket ban stays in force
everywhere else — it exists to keep real map content out of a public repo, and
these contain none), and rewriting the README.

`mutated_pos.bzn` is written from its own hand-authored text rather than by
calling `set_position`, so the assertion that `set_position` reproduces it byte
for byte can still fail. The honest caveat, now recorded in the README: the
Python fixtures were a cross-language oracle and these are not.

All five files run and pass. The suite went from 126 passed / 5 skipped /
3 script errors to 132 passed / 0 skipped / 0 script errors — 132 rather than
131 because `test_walk_mode.gd` is new.

### Non-square multi-zone `.mat` read — narrower than recorded here
This entry was out of date. The F2 §8.4 companion-HG2 size guard **is**
implemented, on the path that matters: `BzOpen` passes `heightmap.zonesX/zonesZ`
into `BzMat.read_mat` (`project/backend/editor/BzOpen.gd:124-130`), so opening an
existing map never reaches the factor-pair guess.

Confirmed against real non-square multi-zone maps in the install, 2026-08-22:

| map | size | zones | mat grid read |
|---|---|---|---|
| `test1222` | 1280×3840 m | 1×3 | 64×192 ✓ |
| `uultst25` | 5120×3840 m | 4×3 | 256×192 ✓ |

Both correct. The closest-factor-pair guess would have read `test1222`'s 12288
tiles as 96×128.

One caller did still omit the zone counts, and it was worse than latent.
`BzNew._open_map` read the `.mat` bare while building a **new** map — and the New
dialog has separate width and depth pickers, with `_flat_heightmap` itself saying
"legal sizes are 1280, 2560, 3840, 5120; non-square is allowed". So creating a
1280x3840 map baked a 64x192-tile `.mat`, read its 12288 tile words straight back
as the closest factor pair 96x128, and built the session transposed.

Fixed 2026-08-22: it passes `heightmap.zonesX/zonesZ` now, the same way `BzOpen`
does. `tests/gd/test_bz_new.gd` creates a 1x3-zone map and asserts the shape;
with the fix reverted it fails with `got=128 want=64`, which is exactly the
transposition.

### Three test files aborted silently part-way
`test_aipaths.gd`, `test_balance_overlay.gd` and `test_ui_shell.gd` each called
into UI that had since moved. A GDScript runtime error is not catchable and
raises no assertion, so the runner scored all three as passes while they had
quietly stopped testing.

The View menu became `project/ui/view/ViewPanel.tscn`, a checkbox grid, so the
first two now drive that; `main.gd`'s `_right_split` became `_right_col`, which
was the null in the third. All three run to completion.

With the count at zero, CI now sets `GODOT_TEST_STRICT=1`, and `MAX_SKIP` and
`MAX_WARN` are both ratcheted to 0.

---

## Known issues carried forward

### Terrain vanishes far outside the map footprint
`_ring_count` sizes the clipmap so "the outermost ring reaches across the whole
map from any point **on** it" (`TerrainRenderer.gd:358-366`), which for a 2560 m
map is 5 rings and a 5.2 km outermost reach. Fly further than that beyond the
edge and every ring piece fails the on-map test in `TerrainClipmap.update`
(line 158) and is hidden, so the world disappears rather than receding.

Measured at 1000 m altitude: still drawn 6 km out, entirely gone by 8 km. Inside
the design envelope this never happens, and the camera has no reason to be there
— noted because "the terrain disappeared" reads as a rendering bug when it is
actually a deliberate cull.


### Binary `.bzn` read is deliberately unsupported
`F3` takes it out of the spec set on purpose. Stock 1998-era maps must be
re-saved from the game with `asciisave`; the editor shows a copyable launch
command. **Do not invent a layout.**

### CI has never run
Both workflows are committed but nothing has been pushed, so nothing has
executed. Unproven: that `chickensoft-games/setup-godot@v2` accepts the input
names used, that Godot `4.7.0` resolves as a tag, that `godot` lands on PATH in
Git-bash on `windows-latest`, and that Git-for-Windows ships `timeout` (guarded
either way). **Nothing on Windows has been run at all** — the cygpath, `%APPDATA%`
and timeout-fallback handling in `scripts/test-editor.sh` is reasoned, not
executed. That is the largest untested surface in the repo.

---

## Licensing state

- `LICENSE` — MIT. The repo previously had none, which meant it was
  all-rights-reserved despite being public.
- `ATTRIBUTIONS.md` — verbatim licences, verified against upstream. **No
  third-party code is currently vendored**; the licences are held ready. The
  clipmap came from GPU Gems 2, which is literature and carries no obligation.
- `CLEANROOM-REQUIRED.md` — material that cannot be copied at any price (GPL,
  unlicensed, closed). Current conclusion: nothing there warrants a spec.
- `AGENTS.md` rule 8 now covers **incoming** third-party source, not just the
  historical clean-room.

If you copy third-party code, record its licence in `ATTRIBUTIONS.md` **first**.
Rule 8 says a source not recorded there is not usable yet.
