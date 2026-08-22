extends RefCounted
class_name ScatterStrokeCommand
## One scatter-paint stroke, undoable (C16).
##
## Painting the mask is destructive — a stamp overwrites whatever slot was
## there, and painting black erases — so the stroke is captured the same way
## every other raster stroke is: RasterChunks holds the 64x64 chunks the
## brush actually reached, and commit() emits one before/after region per
## touched chunk. Cost follows edited area, not the bounding box of the drag.

var scatter: ScatterField
## Slot painted, or -1 for the eraser. Label only — the regions carry the data.
var slot: int = -1
var label: String = ""
var regions: Array = []

var _chunks := RasterChunks.new()
var _open: bool = false


## Arm a stroke. `p_slot` < 0 erases.
static func begin(p_scatter: ScatterField, p_slot: int) -> ScatterStrokeCommand:
	var cmd := ScatterStrokeCommand.new()
	cmd.scatter = p_scatter
	cmd.slot = p_slot
	if p_scatter != null:
		var sp: ScatterSpecies = p_scatter.species_at(p_slot)
		cmd.label = sp.name if sp != null else ""
		cmd._chunks.begin(p_scatter.mask.grid_x, p_scatter.mask.grid_z)
		cmd._open = true
	return cmd


## One brush dab. Captures before it writes, so the chunk store holds the
## pre-stroke image even when the drag crosses the same cell twice.
func stamp(cx_m: float, cz_m: float, radius_m: float) -> Rect2i:
	if not _open or scatter == null:
		return Rect2i()
	var rect: Rect2i = scatter.mask.circle_rect(cx_m, cz_m, radius_m)
	if not rect.has_area():
		return rect
	_chunks.touch(
		scatter.mask.values,
		rect.position.x, rect.position.y, rect.end.x - 1, rect.end.y - 1
	)
	scatter.mask.stamp_circle(cx_m, cz_m, radius_m, slot)
	return rect


## Close the stroke. False when nothing actually changed, in which case the
## caller must NOT push it — an empty entry in the history is a lie.
func commit() -> bool:
	if not _open or scatter == null:
		return false
	_open = false
	regions = _chunks.regions(scatter.mask.values)
	_chunks.begin(0, 0)
	return not regions.is_empty()


func describe() -> String:
	if slot < 0:
		return "erase scatter"
	if label.is_empty():
		return "scatter slot %d" % slot
	return "scatter %s" % label


func cost_bytes() -> int:
	var n := 0
	for r_v in regions:
		var r: Dictionary = r_v
		var before: PackedByteArray = r["before"]
		var after: PackedByteArray = r["after"]
		n += before.size() + after.size()
	return n


func do() -> void:
	_write("after")


func undo() -> void:
	_write("before")


func _write(key: String) -> void:
	if scatter == null:
		return
	for r_v in regions:
		var r: Dictionary = r_v
		scatter.mask.write_rect(
			int(r["x"]), int(r["z"]), int(r["w"]), int(r["d"]), r[key]
		)
