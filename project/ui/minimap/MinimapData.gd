extends RefCounted
class_name MinimapData
## Snapshot of everything the minimap raster is allowed to read.
##
## The raster never touches MapState. The panel fills one of these from the
## live session; a test fills another from a synthetic field. That separation
## is what makes C8 (north-up) assertable headlessly, where there is no GPU to
## run a shading pass on and no game install to supply an atlas.

## C3 fixes both spacings, so these are constants, not manifest fields.
const CELL_M := 5.0
const MAT_CELL_M := 20.0
const MAT_CELLS := 4
## Sub-samples per axis when a minimap texel spans several scatter cells.
const SCATTER_SUBS := 3

var grid_x: int = 0
var grid_z: int = 0
## Raw heightfield words. Metres are raw * HEIGHT_SCALE, exactly as
## HeightField.height_m does it — inherited out-of-range values included (C2).
var heights: PackedInt32Array = PackedInt32Array()
var materials: PackedInt32Array = PackedInt32Array()
var mat_grid_x: int = 0
var mat_grid_z: int = 0
## Optional occupancy, 0..255 per cell, row-major on its own grid. Scatter
## belongs to another panel; the minimap draws it only when handed some.
var scatter: PackedByteArray = PackedByteArray()
var scatter_grid_x: int = 0
var scatter_grid_z: int = 0


## Read the live session. `state` is duck-typed (MapState in the shell) so the
## raster keeps no autoload dependency and tests can hand in a stub.
static func from_state(state: Object, scatter_source: Object = null) -> MinimapData:
	var d := MinimapData.new()
	if state == null:
		return d
	var field := state.get("field") as HeightField
	if field != null and field.grid_x > 0 and field.grid_z > 0:
		d.grid_x = field.grid_x
		d.grid_z = field.grid_z
		d.heights = field.heights
	var mats: Variant = state.get("materials")
	if typeof(mats) == TYPE_PACKED_INT32_ARRAY:
		d.materials = mats
		d.mat_grid_x = int(state.get("mat_grid_x"))
		d.mat_grid_z = int(state.get("mat_grid_z"))
	d.attach_scatter(scatter_source)
	return d


## Optional hand-off from whoever owns scatter. Two shapes are accepted, in
## order: an explicit
## `minimap_occupancy() -> {grid_x: int, grid_z: int, cells: PackedByteArray}`,
## or any object already carrying `grid_x` / `grid_z` / `values` — which is
## the shape of a per-cell paint mask, so a ScatterMask can be handed over
## unchanged and neither side has to know about the other. A null source, an
## unrecognised source or a malformed record leaves the minimap on relief,
## which is the C15 behaviour anyway.
func attach_scatter(source: Object) -> bool:
	scatter = PackedByteArray()
	scatter_grid_x = 0
	scatter_grid_z = 0
	if source == null:
		return false
	if source.has_method("minimap_occupancy"):
		var rec: Variant = source.call("minimap_occupancy")
		if typeof(rec) != TYPE_DICTIONARY:
			return false
		return _adopt_scatter(
			int((rec as Dictionary).get("grid_x", 0)),
			int((rec as Dictionary).get("grid_z", 0)),
			(rec as Dictionary).get("cells", null)
		)
	return _adopt_scatter(
		int(source.get("grid_x")), int(source.get("grid_z")), source.get("values")
	)


func _adopt_scatter(gx: int, gz: int, cells: Variant) -> bool:
	if typeof(cells) != TYPE_PACKED_BYTE_ARRAY:
		return false
	if gx < 1 or gz < 1 or (cells as PackedByteArray).size() < gx * gz:
		return false
	scatter = cells
	scatter_grid_x = gx
	scatter_grid_z = gz
	return true


func valid() -> bool:
	return grid_x > 1 and grid_z > 1 and heights.size() >= grid_x * grid_z


func has_materials() -> bool:
	return mat_grid_x > 0 and mat_grid_z > 0 \
			and materials.size() >= mat_grid_x * mat_grid_z


func has_scatter() -> bool:
	return scatter_grid_x > 0 and scatter_grid_z > 0


func width_m() -> float:
	return float(grid_x) * CELL_M


func depth_m() -> float:
	return float(grid_z) * CELL_M


func height_raw(x: int, z: int) -> int:
	if not valid():
		return 0
	return heights[clampi(z, 0, grid_z - 1) * grid_x + clampi(x, 0, grid_x - 1)]


func height_m(x: int, z: int) -> float:
	return float(height_raw(x, z)) * HeightField.HEIGHT_SCALE


func height_at_world(x_m: float, z_m: float) -> float:
	if not valid():
		return 0.0
	var gx := x_m / CELL_M
	var gz := z_m / CELL_M
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	return lerpf(
		lerpf(height_m(x0, z0), height_m(x0 + 1, z0), tx),
		lerpf(height_m(x0, z0 + 1), height_m(x0 + 1, z0 + 1), tx),
		tz
	)


## Base material of the tile a CELL falls in. MapState.materials already holds
## decoded editor tile words, so this reads the mat_a nibble through BzMat's
## own mask rather than inventing a second definition of the layout (C18).
func material_base(x: int, z: int) -> int:
	if not has_materials():
		return 0
	var tx := clampi(x / MAT_CELLS, 0, mat_grid_x - 1)
	var tz := clampi(z / MAT_CELLS, 0, mat_grid_z - 1)
	return (materials[tz * mat_grid_x + tx] >> 12) & BzMat.MATERIAL_MASK


func scatter_at(x: int, z: int) -> int:
	if not has_scatter():
		return 0
	var sx := clampi(x * scatter_grid_x / maxi(grid_x, 1), 0, scatter_grid_x - 1)
	var sz := clampi(z * scatter_grid_z / maxi(grid_z, 1), 0, scatter_grid_z - 1)
	return scatter[sz * scatter_grid_x + sx]


## Fraction of a `span`×`span` cell block that carries scatter, 0..1. A paint
## mask is one byte per cell, so a minimap texel covering many cells has to
## report coverage rather than whichever cell it happened to land on — a lone
## sample makes a half-covered region flicker between empty and full. Fixed at
## SCATTER_SUBS² samples so the cost stays proportional to texels, not cells.
func scatter_coverage(x: int, z: int, span: int) -> float:
	if not has_scatter():
		return 0.0
	if span <= 1:
		return 1.0 if scatter_at(x, z) != 0 else 0.0
	var hits := 0
	for j in SCATTER_SUBS:
		var cz := z + int(float(span) * (float(j) + 0.5) / float(SCATTER_SUBS))
		for i in SCATTER_SUBS:
			var cx := x + int(float(span) * (float(i) + 0.5) / float(SCATTER_SUBS))
			if scatter_at(cx, cz) != 0:
				hits += 1
	return float(hits) / float(SCATTER_SUBS * SCATTER_SUBS)


## World metres → normalised panel space. C8: y = 0 is NORTH (+z), so a larger
## world z always yields a smaller y. Every screen mapping in this panel goes
## through here.
func world_to_norm(x_m: float, z_m: float) -> Vector2:
	var w := width_m()
	var d := depth_m()
	return Vector2(
		0.0 if w <= 0.0 else x_m / w,
		0.0 if d <= 0.0 else 1.0 - z_m / d
	)


func norm_to_world(n: Vector2) -> Vector2:
	return Vector2(n.x * width_m(), (1.0 - n.y) * depth_m())
