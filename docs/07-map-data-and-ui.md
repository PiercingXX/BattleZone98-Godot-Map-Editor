# 07 — Map data, metadata, and the application UI

Mandatory feature #3: ask what planet and what dimensions, then display, load,
edit, and save every piece of map data the game supports.

## 1. The new-map wizard

Three steps, no more:

**1. Identity**
- Terrain stem — **≤ 8 characters, validated live.** A 9-character stem loads
  with no script, silently; the engine truncates the lookup. This is the single
  most user-hostile trap in the format set, so the field enforces it with an
  explanation rather than a bare error.
- Collision check against known terrain names (base game plus loaded packs).
  Terrain names are global across loaded mods; a collision breaks both maps.
- Display name (the lobby name) and author.

**2. World and size**
- **Planet**: the nine stock worlds from `Edit/trn/` — achilles, elysium,
  europa, ganymede, io, mars, moon, titan, venus — with a preview swatch of the
  atlas and sky.
- **Dimensions**: multiples of **1280 m**. Offer the corpus set — 1280, 2560,
  3840, 5120 — with area and grid size shown, and allow non-square, which is
  legal.

  **Not power-of-2.** The original brief said power-of-2; the engine constraint
  measured from `MakeTRN` is multiples of 1280. The wizard teaches the real
  rule.

  Label 1280 m as **Medium**, not Small: this operator's calibration is that
  medium means 1280, and a 2560 m map came back as "wayyy too big". Corpus
  labels disagree; the operator's usage wins in their own tool.

- **Base elevation**: default raw 1000 (100 m), so there is room to carve down
  as well as up.

**3. Map type**
- **Base-game map** or **BZP map** (Q2). This sets `pack_context`, which
  controls the asset palette (`docs/05` §5) and which metadata sections the
  editor presents (§3).
- Which variants to create: base, `_S`, `_ST`, `_SW`. Each created variant
  starts with its required player object at map centre and, for base/`_ST`/
  `_SW`, a full 14-point spawn ring scaffold the user then moves into place
  (`docs/06` §7–8) — starting from the rules rather than warning toward them.

## 2. Opening maps

Q7: **all** maps — stock, BZP, generated, community.

- Open by file (any member of the basename group) or by browsing the installed
  packs, which is how the operator will actually reach BZP maps.
- **Binary BZNs open read-write, and saving converts them to ASCII.** Say so
  plainly at open time. A user opening a 1998 stock mission should know the
  format changes on save before they invest an hour.
- Missing optional files (no `_ST`, no `.lgt`, a stub) are warnings, not
  failures. Broken maps are exactly the ones worth opening in an editor.
- **Untouched data is preserved byte-for-byte** via residue (`docs/02` §1).
  After a save, show which files came out byte-identical — it is the visible
  proof of the guarantee, and a change appearing in a file the user did not edit
  is a bug they should be able to see immediately.

## 3. The metadata panel

Every field the game reads, grouped by the file it lands in, edited as typed
fields rather than raw text — but with an **advanced raw view** per file, since
the corpus is inconsistent and someone will need to fix something we did not
anticipate.

**Terrain (`.trn`)** — the editable subset:
`[Size]` (derived, read-only — it must match the heightmap header), `[NormalView]`
(fog, visibility, ambient, shadow luma — the time-of-day feel), `[World]`
(music track), `[Sky]` (sun, sky type/height/texture, backdrop), `[Clouds]`.

`[TextureType*]` blocks are **not editable**. They are long, world-specific, and
reference asset names that must exist; the generator repo's rule is to copy a
stock template and override only the four sections above. The panel shows them
read-only for reference.

**Multiplayer metadata (`.ini`)**: mission name, map type, custom tags, min/max
players, game type. Defaults matching the corpus (`gameType = K`,
`maxPlayers = 14`) with the corpus norms shown as hints.

**Description (`.des`)**: free text, but **generated counts must match
reality** — the corpus states geyser and scrap counts that agree with the actual
object counts, and the validator checks it. The editor fills those from the real
counts and warns rather than letting them drift.

**BZP settings (`.odf`)**, only when `pack_context` is BZP: control points
(placeable in the viewport, not typed as coordinates) and the scrap impact zone
section. Note the section is named `[SBPMapSettings]` — legacy naming that BZP's
Lua reads literally; it must not be "corrected".

**Observer list (`.vxt`)**: read-only, copied verbatim. There is no reason to
vary it.

**Script (`.lua`)**: read-only view of the boilerplate, plus the generated
runtime-spawn block for `placement_mode: "runtime"` objects (`docs/06` §6). If
a user wants custom scripting they edit the file; the editor does not try to be
a Lua IDE, but it must not clobber a hand-edited script — treat an unrecognised
script as residue and preserve it.

## 4. The overview panel

A north-up top-down render of the map — the same one the backend generates for
the thumbnail and minimap (`bzmap editor render`), plus overlays for objects,
spawns, and validation findings.

- Click to fly the camera there.
- This is also the thumbnail preview, so what the user sees is what ships.
- **North-up: +z at the top.** The generator repo shipped mirrored renders once
  and it was invisible on symmetric maps.

## 5. Water and plants

Q10 includes per-map meshes. These are **generated meshes, not painted
textures** — the operator's verdict on texture-painted water was that it "looks
nothing like Oasis", and they were right.

The editor's job is to author the *parameters* and preview the result; the
backend generates the mesh (`bzmap/generate/meshgen.py` already does this):

- **Water**: set a waterline height, previewed live as a translucent plane in
  the viewport, and optionally a region mask painted with the brush system so
  water is confined to a trench or basin instead of pooling in every gully.
  Water must read as a *system* — a stream has to end somewhere, and standing
  water needs a shore. The preview is what lets the user see that before it
  ships.
- **Plants**: a scatter region, density, and seed, previewed as billboards.

Constraints the backend owns and the editor must not fight:
- One static carrier object per mesh at the world origin, team 0, PrjID equal to
  the mesh stem (≤ 8 chars), added to every variant.
- The carrier's transform is the **corpus basis, byte-for-byte**, with
  mesh-local vertices transposed. No mathematically-derived basis reproduces it,
  and the sequence that pinned this down cost several play-tests. The editor
  does not expose the carrier's rotation.

Water and plant carriers therefore appear in the object list as **managed
objects**: visible, selectable for inspection, not freely transformable.

## 6. Application shell

```
┌────────────────────────────────────────────────────────────┐
│ menu · toolbar: [tool] [brush] [variant] [validate] [save]  │
├──────────┬──────────────────────────────────┬──────────────┤
│ Palette  │                                  │ Inspector    │
│ (objects)│          3D viewport             │ (selection)  │
│          │                                  ├──────────────┤
│          │                                  │ Metadata     │
├──────────┤                                  ├──────────────┤
│ Brushes  │                                  │ Overview     │
├──────────┴──────────────────────────────────┴──────────────┤
│ Validation findings  ·  Console  ·  status bar             │
└────────────────────────────────────────────────────────────┘
```

- Panels are dockable and their layout persists.
- The **status bar** always shows: cursor world position, terrain height under
  the cursor, camera speed, active variant, and unsaved-changes state.
- The **console** shows backend stderr verbatim (`docs/01`, error posture).
- **Autosave the session directory** on a timer. A crash must never cost more
  than a few minutes of sculpting, and the session directory makes recovery
  natural — reopen it and continue.

## 7. Keyboard

Publish a single hotkey reference and keep it visible in a help overlay (`F1`).
Defaults follow the brief and common 3D-editor convention: `WASD`+`QE` fly,
`RMB` look, `[`/`]` brush size, `Ctrl+Z`/`Ctrl+Shift+Z` undo/redo, `Ctrl+S`
save, `F` frame, `Esc` disarm, `1`–`6` select brush, `Tab` toggle palette.

Make them rebindable and persisted. Long sculpting sessions are muscle memory.
