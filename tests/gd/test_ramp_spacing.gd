extends RefCounted
## The ramp tool marches its own dabs at one per cell, so it must not be
## gated by the user's brush spacing.
##
## Spacing defaults to 0, which is why this never showed: turn it up and the
## same drag that draws a smooth ramp with the default draws a staircase,
## because most of the march's dabs are dropped before they land.


func run(t) -> void:
	var saved_spacing: float = ToolState.brush_spacing
	var saved_ms: int = ToolState.brush_spacing_ms
	var saved_field: HeightField = MapState.field
	var saved_objects: Dictionary = MapState.objects
	var saved_session: bool = MapState.has_session
	var saved_sym: String = ToolState.symmetry

	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)
	MapState.objects = {"": []}
	MapState.has_session = true
	ToolState.set_brush_spacing(1.0, 0)

	var loose := _ramp_profile()
	ToolState.set_brush_spacing(0.0, 0)
	var tight := _ramp_profile()
	t.eq(loose, tight, "brush spacing does not change the ramp")

	# The guard has to be self-cleaning: the shell reuses one SculptTool, and
	# a stroke that left follow_tool_state off would freeze the live brush.
	var sculpt := _sculpt()
	EditActions.apply_ramp(
		sculpt, Vector3(20.0, 10.0, 20.0), Vector3(20.0, 30.0, 100.0), func(_m): pass
	)
	t.ok(sculpt.follow_tool_state, "the tool goes back to following the live brush")
	UndoStack.clear()

	ToolState.set_brush_spacing(saved_spacing, saved_ms)
	ToolState.set_symmetry(saved_sym)
	MapState.field = saved_field
	MapState.objects = saved_objects
	MapState.has_session = saved_session


func _sculpt() -> SculptTool:
	var s := SculptTool.new()
	s.radius_m = 10.0
	s.strength = 1.0
	s.falloff = 1.0
	return s


## Heights down the column the ramp runs along, after one ramp on a fresh
## flat field.
func _ramp_profile() -> PackedInt32Array:
	var field := HeightField.new()
	field.grid_x = 32
	field.grid_z = 32
	field.heights.resize(32 * 32)
	field.heights.fill(200)
	MapState.field = field
	MapState.width_m = 160
	MapState.depth_m = 160
	UndoStack.clear()
	EditActions.apply_ramp(
		_sculpt(), Vector3(20.0, 10.0, 20.0), Vector3(20.0, 30.0, 100.0), func(_m): pass
	)
	UndoStack.clear()
	var ix := int(floor(20.0 / HeightField.CELL_M))
	var out := PackedInt32Array()
	for z in 32:
		out.append(field.heights[z * 32 + ix])
	return out
