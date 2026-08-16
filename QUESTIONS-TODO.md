# Design questions — Battlezone 98 Redux Map Editor (Godot)

Status: **RESOLVED 2026-08-16.** All answers recorded below. This file is kept
as the decision record; the specs in `docs/` are derived from it.

Context: these are the questions left open *after* reviewing
`PiercingXX/skippy-battlezone-map-generator` (cloned and read 2026-08-14).
See "Notes" at the bottom for what that repo already settles.

---

## Architecture (the big one)

### Q1. Reuse `bzmap` or reimplement in GDScript?
**Answer:** **(a)** — shell out to `bzmap` as a backend for
load/save/validate/package, keeping the byte-fidelity guarantees for free.

### Q2. BZP-flavored maps or base-game maps?
**Answer:** **Both.** Editor authors BZP maps (including `_S`/`_SW` variant
object sets and control points) *and* plain base-game multiplayer maps.

---

## Units and rendering

### Q3. "Every stock unit" — define stock.
**Answer:** **Both** base-game ODFs **and** BZP's asset layer, enumerated
**live** from the user's install (not a baked-in list). Combat units and
buildings included, not just props.

### Q4. Model fidelity in the viewport.
**Answer:** "I want it all if possible." → Target the best achievable:
textured legacy `.geo`/`.sdf` meshes from the user's install; investigate
Redux HD model rendering; fall back per-asset down the chain
HD → textured geo → flat-colored geo → labeled footprint proxy.

### Q5. Terrain texturing in the viewport.
**Answer:** "I want it all." → Faithful atlas splatting in the viewport
(atlas extraction from install + MAT decode), plus manual material painting
tools, plus auto-paint available. MAT bit layout verification (generator repo
open question E3) becomes part of this work — the splat shader will visually
confirm or refute the inferred layout.

---

## Policy details

### Q6. Height ceiling.
**Answer:** **Clamp at 4095** (12-bit). Full uint16 range stays off until the
generator repo's E7 is resolved.

### Q7. Editing existing maps.
**Answer:** **ALL maps** — stock, BZP, generated, anything. Untouched data
preserved verbatim via `bzmap` round-trip. (Implication: stock 1998-era
*binary* BZNs need a read path; saving converts to ASCII with a user-facing
notice.)

### Q8. Validators in the UI.
**Answer:** **Report panel** — run Tier 1/2 validators on save, results shown
in-editor.

### Q9. Packaging in-editor.
**Answer:** **Buttons** — install-to-test-mod-dir, thumbnail render, pack
assembly all invokable from the editor UI.

---

## Scope and process

### Q10. Feature reach for v1.
**Answer:** "Everything but the tunnel shit." → In: undo/redo, ramp brush,
per-map water/plant meshes. **Out entirely: tunnels and all `tunnel-testing/`
material — experimental, excluded in full, revisit only if it ever pans out.
Do not reference tunnel-testing content anywhere in this project.**

### Q11. Distribution.
**Answer (2026-08-14):** "I will use this on my linux machine and on a windows
machine." → Cross-platform Linux + Windows from day one. Install-path discovery
must handle both native Steam (Windows) and Proton (Linux) layouts. The Python
backend (Q1a) must be bundled or trivially set up on both OSes.

### Q12. Godot 4.7.
**Answer (2026-08-14):** Confirmed — Godot 4.7 is the current stable release.
Pin to 4.7 stable.

### Q13. Repo and handoff.
**Answer (2026-08-14 + 2026-08-16):** New git repo `battlezone-map-editor`
(this directory), currently **private** alongside the generator repo; both go
public together once built. Using the generator repo's full detail here is
explicitly approved. Same docs-driven pattern: `AGENTS.md` + `docs/` specs
that Skippy builds from. `bzmap` is consumed as a backend (sibling checkout /
submodule), with editor-bridge code living in THIS repo.

---

## Notes — what the generator repo already settles (do NOT re-ask)

Reviewed from `skippy-battlezone-map-generator` (private, cloned 2026-08-14;
docs measured from game v2.2.301 + BZP Workshop item 3406347034):

- **File formats**: verified specs for HG2 (zone-major 256×256 blocks, 12-byte
  header, `height_m = raw × 0.1`, 5 m grid), MAT (zone-major, 20 m tiles,
  bit layout inferred), LGT (ambient plane 0 = byte 56 + per-zone shading;
  feeds the in-game radar underlay), TRN (INI; copy stock world templates from
  `Edit/trn/`, override only Size/NormalView/World/Sky), plus
  ini/des/odf/vxt/lua conventions.
- **BZN**: plain ASCII (`binarySave = false`), full writer spec in docs/02.
  Round-trip byte-identical on all 128 BZP BZNs is the acceptance gate.
  Template-and-mutate, never synthesize. `pos` appears twice per object;
  position lives in three places (`pos` ×2 + `transform.posit`); `msn_filename`
  and `TerrainName` are vestigial — preserve verbatim, never validate.
- **Map sizes**: multiples of 1280 m — {1280, 2560, 3840, 5120}, non-square
  legal. **NOT power-of-2** (corrects the original app summary).
- **Worlds/planets**: 9 stock templates in `Edit/trn/` — achilles, elysium,
  europa, ganymede, io, mars, moon, titan, venus.
- **Environment**: Linux, game under Proton Experimental at
  `~/.steam/steam/steamapps/common/Battlezone 98 Redux`, no wine on PATH.
  Game + BZP install dirs are read-only reference data; never modify them.
- **Test loop**: `battlezone98redux.exe <map>.bzn /startedit /win` loads a map
  directly into the in-game editor (load gate only — that editor has no
  collision). Offline validators first, always; game launches are expensive.
- **Skippy**: the build agent; works from `AGENTS.md` + `docs/` specs, phase
  order from a build plan, "reality wins" rule for format claims, audited by
  the operator.
- **Ground snapping**: object Y from bilinear heightmap sample; a raise/lower
  brush must re-snap placed objects (stock objects sit within ~1 m of surface).
- **Height 0 = "undefined"**, not sea level; playable terrain sits on a nonzero
  plateau (headroom to carve down as well as up).
- **Stem limit**: map basenames ≤ 8 characters (engine limit; longer stems load
  scriptless).
- **Upstream reuse**: WorldBuilder (MIT) for HG2 zone packing / MAT
  auto-painting / atlases; bzfile and ExtraUtilities exist as escape hatches.
