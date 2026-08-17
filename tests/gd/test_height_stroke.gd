extends RefCounted
## Synthetic 32×32 field: stroke → undo → redo round-trips heights and snaps.


func run(t) -> void:
	var field := _flat(32, 32, 200)
	var saved_field = MapState.field
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	MapState.field = field
	MapState.objects = {
		"": [{"id": "obj-1", "x": 20.0, "y": 20.0, "z": 20.0, "pinned_y": false}],
	}

	var sculpt := SculptTool.new()
	sculpt.mode = "raise"
	sculpt.radius_m = 15.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.5
	sculpt.begin_stroke(field, 20.0, 20.0, false)
	sculpt.stamp(field, 20.0, 20.0)
	var cmd = sculpt.end_stroke(field)
	t.ok(cmd != null, "stroke produced a command")
	var after_stroke := field.heights.duplicate()
	t.ok(after_stroke[4 * 32 + 4] != 200, "center cell changed")
	var snapped_y: float = float(MapState.objects[""][0]["y"])
	t.ok(snapped_y > 20.0, "object y re-snapped up")

	UndoStack.clear()
	UndoStack.push(cmd, true)
	t.eq(field.heights, after_stroke, "already_applied leaves heights")

	UndoStack.undo()
	for i in field.heights.size():
		t.eq(field.heights[i], 200, "undo restores raw heights")
		if field.heights[i] != 200:
			break
	t.near(float(MapState.objects[""][0]["y"]), 20.0, 0.001, "undo restores object y")

	UndoStack.redo()
	t.eq(field.heights, after_stroke, "redo restores stroke")
	t.near(float(MapState.objects[""][0]["y"]), snapped_y, 0.001, "redo restores snapped y")

	UndoStack.undo()
	UndoStack.clear()
	MapState.field = saved_field
	MapState.objects = saved_objects


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field
