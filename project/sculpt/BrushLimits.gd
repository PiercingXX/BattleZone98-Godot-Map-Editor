extends RefCounted
class_name BrushLimits
## Slope and height bands that gate what a brush is allowed to touch.
##
## "Only rock above 30 degrees", "only buildable ground", "only the shoreline":
## the mapmaker states the terrain condition once and every brush obeys it,
## instead of tracing the boundary by hand and re-tracing it after every edit.
##
## The factor multiplies brush weight, so a gated cell is not written at all
## rather than written and clamped — C2 stands: an untouched cell keeps its
## inherited word, out-of-range or not.

## Gradient probe distance. One cell: shorter than this and the bilinear
## samples land in the same triangle and the gradient reads as zero.
const PROBE_M := HeightField.CELL_M


## Local slope against up, in degrees, from three bilinear height samples.
static func slope_deg(field: HeightField, x_m: float, z_m: float) -> float:
	if field == null or field.grid_x < 2 or field.grid_z < 2:
		return 0.0
	var h0 := field.height_at(x_m, z_m)
	var hx := field.height_at(x_m + PROBE_M, z_m)
	var hz := field.height_at(x_m, z_m + PROBE_M)
	var dx := (hx - h0) / PROBE_M
	var dz := (hz - h0) / PROBE_M
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


## Cell-grid form of the same three-sample gradient. At a cell centre the
## bilinear form spends four array reads and three lerps landing on a value
## the grid already holds, and the gate runs on every cell of every dab.
static func slope_deg_cell(field: HeightField, x: int, z: int) -> float:
	if field == null or field.grid_x < 2 or field.grid_z < 2:
		return 0.0
	var gx := field.grid_x
	var h0 := float(field.heights[z * gx + x])
	var hx := float(field.heights[z * gx + mini(x + 1, gx - 1)])
	var hz := float(field.heights[mini(z + 1, field.grid_z - 1) * gx + x])
	var k := HeightField.HEIGHT_SCALE / PROBE_M
	var dx := (hx - h0) * k
	var dz := (hz - h0) * k
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


## 1 inside [lo, hi], 0 beyond a `feather`-wide smoothstep on either side.
## An inverted band (lo > hi) is treated as empty, not as everything.
static func band(v: float, lo: float, hi: float, feather: float) -> float:
	if lo > hi:
		return 0.0
	if v >= lo and v <= hi:
		return 1.0
	var f := maxf(feather, 0.0)
	if f <= 0.0:
		return 0.0
	if v < lo:
		return smoothstep(lo - f, lo, v)
	return 1.0 - smoothstep(hi, hi + f, v)
