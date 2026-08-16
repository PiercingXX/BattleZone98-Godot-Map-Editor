# 03 — Viewport, terrain rendering, and camera

Mandatory feature #1 lives here, and so does the performance budget the rest of
the editor spends.

## 1. Coordinate frame

The editor works in **game world coordinates, one Godot unit = one metre**, so
that every number in a panel is a number the operator can compare against the
generator repo's docs and against in-game measurements without conversion.

```
+x  east      grid x, column index
+z  north     grid z, row index — renders at the TOP of overview images
+y  up        height, metres = raw * 0.1
```

Cell size is 5 m. Grid dimensions are `width_m / 5` by `depth_m / 5`. Heights
run raw 0–4095, i.e. 0–409.5 m.

**Raw 0 means "undefined", not sea level.** Play surfaces sit on a nonzero
plateau (stock modal values are raw 988, 1371, 153). New maps start at raw 1000
(100 m) so there is headroom to carve downward. The editor renders raw-0 cells
distinctly (see §5) so the user can see out-of-play regions rather than
mistaking them for a canyon floor.

## 2. Terrain rendering: GPU displacement, not mesh rebuilds

A 5120 m map is a 1024×1024 grid — a million vertices. Rebuilding an `ArrayMesh`
per brush stroke at that size is a non-starter, and it is the obvious wrong turn
to design against.

**The approach:**

- The heightmap lives in a `Texture2D`, **`Image.FORMAT_RF`** (32-bit float),
  uploaded once. Not `FORMAT_RH`: half floats have an 11-bit mantissa, so raw
  values above 2048 quantize to steps of 2 (0.2 m) — a silent precision loss
  exactly in the height range where plateaus live. At 1024², RF is a 4 MB
  texture; the precision is worth it.
- Terrain is drawn as a grid of **chunk meshes** — flat, pre-subdivided planes,
  128×128 cells each — displaced in the **vertex shader** by sampling the height
  texture.
- A brush stroke updates the height array and re-uploads **only the dirty
  rect** of the texture (`Image.blit_rect` into the texture region), not the
  whole map.
- Normals are computed in the fragment shader from height-texture neighbours.
  No CPU normal recalculation, ever.

Chunk meshes are identical geometry at different transforms, so they share one
mesh resource; only the transform and a UV offset differ. Distant chunks swap to
lower-subdivision variants (`MultiMesh` or plain LOD levels) — three levels is
enough at these dimensions.

**Consequence to internalise:** the CPU-side height array and the GPU texture
must never drift. All height writes go through `HeightField.gd`, which owns both
and marks dirty rects. Nothing else writes heights.

## 3. Terrain shader

One shader (`shaders/terrain.gdshader`) does four jobs:

1. **Vertex displacement** from the height texture.
2. **Normal reconstruction** from height neighbours (central differences over
   the 5 m spacing).
3. **Material splatting** from the material texture — see `docs/05` §4 for the
   atlas side, and note that a 20 m material tile covers 4×4 height cells.
4. **Overlays**, all uniform-driven and toggleable:
   - the **brush projection** (§ `docs/04` §5) — a ring and falloff gradient
     painted onto the surface, which is what "visually projected onto the
     terrain" means in the brief;
   - a slope tint (the in-game editor's convention is blue = flat, white =
     steep; the community reads maps that way, so match it);
   - a contour/grid overlay at a user-set interval;
   - undefined-cell (raw 0) hatching;
   - the waterline preview plane (`docs/07` §5).

Overlays are shader uniforms rather than separate geometry so they cost nothing
to toggle and cannot desynchronise from the terrain.

## 4. Raycasting: analytic, not physics

Object placement and brush positioning both need "where does the cursor hit the
ground". **Do not use Godot physics for this.** A collision shape for a
1024×1024 heightfield is expensive to build and must be rebuilt on every sculpt.

Instead, `TerrainRaycast.gd` marches the ray over the height grid (a 2D DDA
across cells) and intersects the two triangles of each cell it crosses,
returning the first hit. This reads directly from the height array, is exact,
costs nothing to keep in sync, and is unaffected by sculpting.

It must also expose:
- `height_at(x_m, z_m) -> float` — **bilinear** interpolation, matching the
  backend's `sample_m`. Nearest-cell sampling floats objects above the terrain
  and sinks plant billboards; the generator repo hit both.
- `normal_at(x_m, z_m) -> Vector3` — for terrain-normal alignment (`docs/06`).

## 5. Visual legibility requirements

The operator's single most repeated map-quality complaint is **terrain
monotony**, and the fix is being able to *see* relief while sculpting. The
viewport must therefore make shape readable, not just present:

- Directional lighting with a user-adjustable sun angle, defaulting to a low
  north light (matches how the `.lgt` bake shades, so what you see approximates
  the in-game radar).
- Ambient occlusion or a cheap curvature term, so knolls and gullies read
  without moving the camera.
- The slope tint overlay above, on a hotkey.
- Undefined (raw 0) cells visibly hatched.

## 6. Camera

Free-fly, as specified:

| Input | Action |
|---|---|
| `W` `A` `S` `D` | forward / left / back / right, in the camera's facing plane |
| `Q` / `E` | down / up, world-vertical |
| Right mouse drag | look |
| `Shift` | fast (×4) |
| `Ctrl` | slow (×0.25) |
| Mouse wheel | adjust base speed (persisted) |
| `F` | frame the selection, or the map if nothing is selected |
| `Space` | snap to a top-down overview at map centre |

Requirements:
- Base speed is **metres per second** and shown in the status bar. A 5120 m map
  takes an unreasonable time to cross at a speed tuned for a 1280 m one, so
  default speed scales with map dimension and with height above terrain.
- The camera never falls through terrain; an optional "walk the surface" mode
  clamps `y` to `height_at() + eye_height`.
- Far plane and fog must not hide the map at overview altitude — check this at
  5120 m specifically.

## 7. Performance target

**The bar: 60 fps at 5120×5120 while painting a 200 m radius brush**, on the
operator's hardware. That is the largest legal map and a large brush, so
everything smaller is covered.

Concretely this means:
- No per-frame allocation in the brush or raycast paths.
- Dirty-rect texture uploads only; measure the uploaded region and assert it is
  proportional to brush area, not map area.
- Chunk culling by frustum, plus LOD.

Instrument early: a debug overlay showing frame time, uploaded bytes per
stroke, and chunk count. A performance regression that ships is very hard to
find later, and this is the feature most likely to hide one.
