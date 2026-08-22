extends RefCounted
class_name GenMetrics
## Does a generated field make a playable Battlezone map?
##
## Pretty mountains are worthless here: an RTS map is buildable pockets joined
## by navigable slopes. These are the same thresholds the validators use, so a
## generator preset that scores well here also passes `bzmap validate`:
##   * buildable   slope <= tan 5 deg   (BzCheckBalance rule E3/B1)
##   * traversable slope <= tan 30 deg  (BzCheckConnectivity rule C1/C2)
##
## Slope is the central-difference gradient magnitude in metres per metre,
## matching BzHg2.slope, but taken over a plain row-major array so it also
## works on a reduced-resolution preview grid (which is not zone-aligned and
## therefore cannot be wrapped in a BzHg2.HeightMap).

const CELL_M := 5.0
const HEIGHT_SCALE := 0.1
const BUILDABLE_SLOPE := BzCheckBalance.BUILDABLE_SLOPE
const TRAVERSABLE_SLOPE := BzCheckConnectivity.SLOPE_30_DEG


static func slope_field(
	heights: PackedInt32Array, gx: int, gz: int, cell_m: float = CELL_M
) -> PackedFloat64Array:
	var n := gx * gz
	var out := PackedFloat64Array()
	if n <= 0 or heights.size() != n:
		return out
	out.resize(n)
	for z in gz:
		var row := z * gx
		var up := row - gx if z > 0 else row
		var down := row + gx if z < gz - 1 else row
		var span_z := (2.0 if (z > 0 and z < gz - 1) else 1.0) * cell_m
		if gz == 1:
			span_z = 1.0
		for x in gx:
			var i := row + x
			var xm := x - 1 if x > 0 else x
			var xp := x + 1 if x < gx - 1 else x
			var span_x := (2.0 if (x > 0 and x < gx - 1) else 1.0) * cell_m
			if gx == 1:
				span_x = 1.0
			var dz := 0.0
			if gz > 1:
				dz = float(heights[down + x] - heights[up + x]) * HEIGHT_SCALE / span_z
			var dx := 0.0
			if gx > 1:
				dx = float(heights[row + xp] - heights[row + xm]) * HEIGHT_SCALE / span_x
			out[i] = sqrt(dx * dx + dz * dz)
	return out


## Summary statistics for a generated field. `with_pockets` adds the largest
## connected buildable area, which is the number that decides whether anyone
## can put a base down; it costs a flood fill, so previews leave it off.
static func measure(
	heights: PackedInt32Array,
	gx: int,
	gz: int,
	cell_m: float = CELL_M,
	with_pockets: bool = false
) -> Dictionary:
	var n := gx * gz
	if n <= 0 or heights.size() != n:
		return {"cells": 0}
	var lo := 0x7FFFFFFF
	var hi := -0x7FFFFFFF
	var sum := 0
	for i in n:
		var v := heights[i]
		sum += v
		if v < lo:
			lo = v
		if v > hi:
			hi = v
	var s := slope_field(heights, gx, gz, cell_m)
	var buildable := 0
	var traversable := 0
	var slope_sum := 0.0
	var slope_max := 0.0
	for i in n:
		var v := s[i]
		slope_sum += v
		if v > slope_max:
			slope_max = v
		if v <= BUILDABLE_SLOPE:
			buildable += 1
		if v <= TRAVERSABLE_SLOPE:
			traversable += 1
	var out := {
		"cells": n,
		"min_raw": lo,
		"max_raw": hi,
		"mean_raw": float(sum) / float(n),
		"relief_m": float(hi - lo) * HEIGHT_SCALE,
		"mean_slope": slope_sum / float(n),
		"max_slope": slope_max,
		"buildable_frac": float(buildable) / float(n),
		"traversable_frac": float(traversable) / float(n),
	}
	if with_pockets:
		var pockets := largest_pocket(s, gx, gz, BUILDABLE_SLOPE)
		out["largest_buildable_cells"] = pockets
		out["largest_buildable_m2"] = float(pockets) * cell_m * cell_m
	return out


## Cells in the biggest 4-connected run of cells at or below `max_slope`.
## Iterative flood fill — a 1024x1024 grid would blow the recursion budget.
static func largest_pocket(
	slopes: PackedFloat64Array, gx: int, gz: int, max_slope: float
) -> int:
	var n := gx * gz
	if slopes.size() != n or n <= 0:
		return 0
	var seen := PackedByteArray()
	seen.resize(n)
	var best := 0
	var stack := PackedInt32Array()
	for start in n:
		if seen[start] == 1 or slopes[start] > max_slope:
			continue
		var count := 0
		stack.clear()
		stack.append(start)
		seen[start] = 1
		while stack.size() > 0:
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			count += 1
			var x := i % gx
			var z := i / gx
			if x > 0 and seen[i - 1] == 0 and slopes[i - 1] <= max_slope:
				seen[i - 1] = 1
				stack.append(i - 1)
			if x < gx - 1 and seen[i + 1] == 0 and slopes[i + 1] <= max_slope:
				seen[i + 1] = 1
				stack.append(i + 1)
			if z > 0 and seen[i - gx] == 0 and slopes[i - gx] <= max_slope:
				seen[i - gx] = 1
				stack.append(i - gx)
			if z < gz - 1 and seen[i + gx] == 0 and slopes[i + gx] <= max_slope:
				seen[i + gx] = 1
				stack.append(i + gx)
		if count > best:
			best = count
	return best
