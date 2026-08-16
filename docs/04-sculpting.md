# 04 — Sculpting and painting

Mandatory feature #2. The brief's minimum is raise/lower, flatten, and smooth;
the agreed scope (Q10) adds a ramp brush, and the operator's map-quality notes
argue strongly for a noise/ridge brush too.

## 1. The brush model

Every brush shares one description:

```
shape      : circle | square
radius_m   : float        # 5 .. 400, in metres, shown in the UI in metres
falloff    : float 0..1   # 0 = hard edge, 1 = fully smooth cosine
strength   : float 0..1
spacing_m  : float        # minimum cursor travel between stamps
```

**Radius is in metres, not cells.** The operator's briefs are literal — "a
couple hundred metre wide moat" means 200 m measured — so the tool must speak
the same units the intent is expressed in. Show the metric diameter next to the
cursor while dragging.

Hotkeys: `[` / `]` adjust radius, `Shift`+`[` / `]` adjust strength, and holding
a modifier while dragging adjusts radius interactively (Blender-style) without
leaving the surface.

## 2. Stroke mechanics

A stroke is: press → sample cursor→terrain hits at `spacing_m` intervals →
stamp the brush kernel at each → release.

Each stamp:
1. Computes the affected cell rect from centre and radius.
2. Applies the operator over that rect, clamping to `[1, 4095]` (§3).
3. Extends the stroke's dirty rect.

On release, one dirty-rect texture upload and one undo entry for the whole
stroke (§4). During the stroke, upload the incremental dirty rect each frame so
the user sees it live.

**One stroke = one undo step.** Not one stamp.

## 3. Clamping and the raw-0 rule

- Hard clamp to **raw 4095** (Q6). Sculpting cannot exceed it, and the UI shows
  the ceiling being hit rather than silently flattening against it — the
  generator repo's rule is *don't silently clip*.
- Hard floor at **raw 1**, not 0, because **raw 0 means "undefined region"** to
  the engine, not "sea level". A brush must never manufacture undefined cells.
- Marking cells undefined is a separate, explicit tool (`Set Undefined`), with
  its own confirmation, because it changes what the region *means* rather than
  its height.
- Relief caps around 390 m in practice. A user asking for a trench deeper than
  the playfield allows must be told the number, not quietly clipped.

## 4. Undo/redo

Mandatory (Q10), and built in from the first sculpting commit — retrofitting it
is worse than building it.

`UndoStack.gd` holds command objects with `undo()` / `redo()`:

- **`HeightStrokeCommand`** — stores the dirty rect plus before/after height
  slices for exactly that rect. A 200 m brush on a 5 m grid touches ~80×80
  cells; two `int32` slices is ~50 KB. Cheap.
- **`MaterialStrokeCommand`** — same shape, over the 20 m material grid.
- **`ObjectCommand`** — add / delete / move / rotate / retype / re-team, with
  the before and after object state.
- **`MetaCommand`** — a metadata field edit.

Rules:
- Memory budget: cap the stack at a configurable total (default 512 MB) and
  drop the oldest entries, telling the user in the status bar when it happens.
- Interleaved sequences must be correct: sculpt → place object → sculpt → undo
  ×3 restores all three in order. Test this explicitly; it is where naive
  implementations break.
- **Objects re-snap to terrain when the ground under them moves** (`docs/06`
  §4). That re-snap is part of the height command's undo record, or undoing a
  sculpt leaves objects floating.

## 5. Brush projection onto the terrain

The brief asks for brushes "visually projected onto the terrain". Implemented as
shader uniforms, not geometry (`docs/03` §3): the terrain shader receives brush
centre, radius, falloff, and mode, and paints a ring plus a falloff gradient
onto the surface, following the ground exactly because it is evaluated
per-fragment on the displaced surface.

The projection must remain visible and correctly shaped on steep slopes and
across chunk boundaries — those are the two places a decal approach looks wrong.

## 6. The brushes

### Raise / Lower
Adds `±strength * kernel` to each cell. Hold `Ctrl` to invert. The workhorse.

### Flatten
Levels toward a target height. Two modes, both needed:
- **Sampled** — target is the height under the cursor at stroke start (the
  common case: flatten a base pad).
- **Fixed** — target is a height the user typed. Needed for making a plateau
  match a known elevation.

### Smooth
Box or gaussian blur of the height field within the kernel, weighted by
strength. The most-used brush after raise/lower; it is what turns procedural
noise into terrain that reads as landscape.

### Ramp
Explicitly requested, and the fix for the highest-frequency terrain defect in
the generator repo: base pads flattened to a hard step above the corridor floor,
leaving a ~71° cliff that disconnects the base from the map. The connectivity
validator rejects exactly this.

Interaction: click a start point, drag to an end point, and the tool grades a
corridor of the brush's width between the two, interpolating height along the
axis with a falloff across it. Show the **resulting slope in degrees** live
while dragging, with the traversable threshold (30°) marked — the user should
be able to see they are about to build something units cannot climb.

### Noise / Ridge
Not in the brief's minimum, but the operator's most repeated map-quality
complaint is monotony: every map needs *directional ridge grain, knolls to hide
behind, gullies to hide in*. A brush that stamps fractal or ridged noise, with a
direction control for grain, is how you author that by hand instead of hoping.

Parameters: scale, octaves, direction, and additive-vs-replace.

### Set Undefined
Sets raw 0 over the kernel, with confirmation. Separate because it is a
semantic change (§3).

## 7. Material painting

Q5: manual painting **and** auto-paint.

- **Manual** — the same brush model over the 20 m material grid. The palette
  comes from the world's `[TextureType0..N]` blocks (`docs/02` §3 `worlds`),
  shown with real atlas swatches where the atlas resolved and flat colours where
  it did not.
- **Auto-paint** — a button that calls the backend's existing rule-based
  painter (slope and elevation driven, the same logic `MakeTRN` and
  WorldBuilder use) over the whole map or the current selection. This is the
  normal path; manual painting is for fixing what the rules get wrong.
- Auto-paint is one undo step over the whole affected rect.

Note the resolution mismatch: one material tile is 4×4 height cells. Show the
material grid as an overlay while the paint tool is active so the user can see
what they are actually addressing.

## 8. What sculpting must *not* do

- Must not touch the lightmap. `.lgt` is baked by the backend on save; there is
  no interactive lighting to maintain.
- Must not write heights outside `HeightField.gd` (`docs/03` §2).
- Must not run through the backend. Sculpting is pure in-editor; the backend
  sees the result at save time only.
