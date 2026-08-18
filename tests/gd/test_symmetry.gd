extends RefCounted
## Symmetry: image-point math (even/odd grids), yaw, one-undo sculpt/paint/place/ramp.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_w: int = MapState.width_m
	var saved_d: int = MapState.depth_m
	var saved_field = MapState.field
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_mats: PackedInt32Array = MapState.materials.duplicate()
	var saved_mgx: int = MapState.mat_grid_x
	var saved_mgz: int = MapState.mat_grid_z
	var saved_variant := MapState.active_variant
	var saved_sym := ToolState.symmetry
	var saved_armed: Dictionary = ToolState.armed.duplicate(true)
	var saved_new_id: int = MapState.next_new_id
	UndoStack.clear()
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)

	_math_world(t)
	_math_grid_even(t)
	_math_grid_odd(t)
	_yaw(t)
	_effective_quad(t)
	_session_keeps_mode(t)
	_sculpt_undo(t)
	_paint_undo(t)
	_place_undo(t)
	_ramp_undo(t)

	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.width_m = saved_w
	MapState.depth_m = saved_d
	MapState.field = saved_field
	MapState.objects = saved_objects
	MapState.materials = saved_mats
	MapState.mat_grid_x = saved_mgx
	MapState.mat_grid_z = saved_mgz
	MapState.active_variant = saved_variant
	MapState.next_new_id = saved_new_id
	ToolState.set_symmetry(saved_sym)
	if saved_armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(saved_armed)
	if saved_session:
		MapState.mark_saved()


func _math_world(t) -> void:
	var cx := 80.0
	var cz := 80.0
	t.eq(ToolState.image_points_xz(ToolState.SYMMETRY_OFF, 20.0, 30.0, cx, cz), [
		Vector2(20.0, 30.0),
	], "off is identity")
	_eq_pts(t, ToolState.image_points_xz(ToolState.SYMMETRY_MIRROR_X, 20.0, 30.0, cx, cz), [
		Vector2(20.0, 30.0), Vector2(140.0, 30.0),
	], "mirror x flips east-west")
	_eq_pts(t, ToolState.image_points_xz(ToolState.SYMMETRY_MIRROR_Z, 20.0, 30.0, cx, cz), [
		Vector2(20.0, 30.0), Vector2(20.0, 130.0),
	], "mirror z flips north-south")
	_eq_pts(t, ToolState.image_points_xz(ToolState.SYMMETRY_ROT180, 20.0, 30.0, cx, cz), [
		Vector2(20.0, 30.0), Vector2(140.0, 130.0),
	], "rot180 is a point reflection")
	_eq_pts(t, ToolState.image_points_xz(ToolState.SYMMETRY_QUAD, 20.0, 30.0, cx, cz), [
		Vector2(20.0, 30.0), Vector2(30.0, 140.0), Vector2(140.0, 130.0), Vector2(130.0, 20.0),
	], "quad is four 90° clockwise copies")
	t.eq(ToolState.image_points_xz(ToolState.SYMMETRY_ROT180, cx, cz, cx, cz).size(), 1, "center rot180 collapses")
	t.eq(ToolState.image_points_xz(ToolState.SYMMETRY_QUAD, cx, cz, cx, cz).size(), 1, "center quad collapses")
	t.eq(ToolState.image_points_xz(ToolState.SYMMETRY_MIRROR_X, cx, 12.0, cx, cz).size(), 1, "on the mirror-x plane")


func _math_grid_even(t) -> void:
	# 4×4 cells. Mirror of 0 is 3; no center cell.
	var gx := 4
	var gz := 4
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_MIRROR_X, 0, 1, gx, gz), [
		Vector2i(0, 1), Vector2i(3, 1),
	])
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_MIRROR_Z, 1, 0, gx, gz), [
		Vector2i(1, 0), Vector2i(1, 3),
	])
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_ROT180, 0, 0, gx, gz), [
		Vector2i(0, 0), Vector2i(3, 3),
	])
	_eq_cells(t, ToolState.image_points_cell(ToolState.SYMMETRY_QUAD, 0, 0, gx, gz), [
		Vector2i(0, 0), Vector2i(0, 3), Vector2i(3, 3), Vector2i(3, 0),
	], "even-grid quad corners")
	_eq_cells(t, ToolState.image_points_cell(ToolState.SYMMETRY_QUAD, 1, 1, gx, gz), [
		Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1),
	], "even-grid quad around the seam")
	# World centers of those cells must match the discrete map.
	var cell := HeightField.CELL_M
	var cx := float(gx) * cell * 0.5
	var cz := float(gz) * cell * 0.5
	var wx := (0.0 + 0.5) * cell
	var wz := (1.0 + 0.5) * cell
	var world := ToolState.image_points_xz(ToolState.SYMMETRY_MIRROR_X, wx, wz, cx, cz)
	t.near(world[1].x, (3.0 + 0.5) * cell, 0.001, "even-grid world matches cell mirror")
	t.near(world[1].y, wz, 0.001)


func _math_grid_odd(t) -> void:
	# 5×5 cells. Center cell is (2,2).
	var gx := 5
	var gz := 5
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_MIRROR_X, 0, 1, gx, gz), [
		Vector2i(0, 1), Vector2i(4, 1),
	])
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_MIRROR_X, 2, 1, gx, gz).size(), 1, "odd-grid center column")
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_ROT180, 2, 2, gx, gz), [Vector2i(2, 2)])
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_QUAD, 2, 2, gx, gz), [Vector2i(2, 2)], "odd-grid center")
	_eq_cells(t, ToolState.image_points_cell(ToolState.SYMMETRY_QUAD, 0, 1, gx, gz), [
		Vector2i(0, 1), Vector2i(1, 4), Vector2i(4, 3), Vector2i(3, 0),
	], "odd-grid quad")
	t.eq(ToolState.image_points_cell(ToolState.SYMMETRY_QUAD, 0, 0, 5, 4).size(), 1, "quad refuses a non-square grid")


func _yaw(t) -> void:
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_MIRROR_X, 45.0, 0), 45.0)
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_MIRROR_X, 45.0, 1), -45.0, 0.001, "mirror x negates yaw")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_MIRROR_X, 90.0, 1), -90.0, 0.001, "east becomes west")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_MIRROR_Z, 45.0, 1), 135.0, 0.001, "mirror z is 180-yaw")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_MIRROR_Z, 0.0, 1), 180.0, 0.001, "north becomes south")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_ROT180, 45.0, 1), -135.0, 0.001, "rot180 adds 180")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_QUAD, 10.0, 1), 100.0, 0.001, "quad +90")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_QUAD, 10.0, 2), -170.0, 0.001, "quad +180")
	t.near(ToolState.transform_yaw_deg(ToolState.SYMMETRY_QUAD, 10.0, 3), -80.0, 0.001, "quad +270")
	var poses := ToolState.image_poses(ToolState.SYMMETRY_QUAD, 20.0, 30.0, 15.0, 80.0, 80.0)
	t.eq(poses.size(), 4)
	t.near(float(poses[1].get("yaw_deg", 0.0)), 105.0, 0.001)


func _effective_quad(t) -> void:
	MapState.width_m = 2560
	MapState.depth_m = 1280
	MapState.field = HeightField.new()
	ToolState.set_symmetry(ToolState.SYMMETRY_QUAD)
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_QUAD, "stored mode stays quad")
	t.eq(ToolState.effective_symmetry(), ToolState.SYMMETRY_OFF, "quad is off on a rectangle")
	t.ok(not ToolState.can_use_quad())
	MapState.width_m = 1280
	MapState.depth_m = 1280
	t.eq(ToolState.effective_symmetry(), ToolState.SYMMETRY_QUAD)
	t.ok(ToolState.can_use_quad())
	ToolState.set_symmetry("nope")
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_OFF, "unknown mode normalizes to off")


func _session_keeps_mode(t) -> void:
	ToolState.set_symmetry(ToolState.SYMMETRY_ROT180)
	var n := 0
	var cb := func() -> void: n += 1
	ToolState.symmetry_changed.connect(cb)
	MapState.session_changed.emit()
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_ROT180, "map session does not clear symmetry")
	t.eq(n, 0, "session_changed does not emit symmetry_changed")
	ToolState.symmetry_changed.disconnect(cb)
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)


func _sculpt_undo(t) -> void:
	var field := _flat(32, 32, 200)
	MapState.field = field
	MapState.width_m = 160
	MapState.depth_m = 160
	MapState.objects = {"": []}
	MapState.has_session = true
	ToolState.set_symmetry(ToolState.SYMMETRY_MIRROR_X)
	var sculpt := SculptTool.new()
	sculpt.mode = "raise"
	sculpt.radius_m = 12.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.2
	sculpt.begin_stroke(field, 20.0, 80.0, false)
	var cmd = sculpt.end_stroke(field)
	t.ok(cmd != null, "symmetric stroke produced a command")
	var ix0 := int(floor(20.0 / HeightField.CELL_M))
	var ix1 := int(floor(140.0 / HeightField.CELL_M))
	var iz := int(floor(80.0 / HeightField.CELL_M))
	t.ok(field.heights[iz * 32 + ix0] != 200, "primary cell raised")
	t.ok(field.heights[iz * 32 + ix1] != 200, "mirror-x cell raised")
	t.eq(field.heights[iz * 32 + ix0], field.heights[iz * 32 + ix1], "mirror pair matches")
	UndoStack.clear()
	UndoStack.push(cmd, true)
	t.ok(UndoStack.can_undo())
	t.ok(not UndoStack.can_redo())
	UndoStack.undo()
	t.eq(field.heights[iz * 32 + ix0], 200, "undo restores primary")
	t.eq(field.heights[iz * 32 + ix1], 200, "undo restores mirror")
	t.ok(not UndoStack.can_undo(), "one undo step covers both points")
	UndoStack.redo()
	t.ok(field.heights[iz * 32 + ix0] != 200)
	t.eq(field.heights[iz * 32 + ix0], field.heights[iz * 32 + ix1])
	UndoStack.undo()
	UndoStack.clear()
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)


func _paint_undo(t) -> void:
	MapState.mat_grid_x = 8
	MapState.mat_grid_z = 8
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(64)
	MapState.materials.fill(0)
	MapState.width_m = 160
	MapState.depth_m = 160
	MapState.has_session = true
	ToolState.set_symmetry(ToolState.SYMMETRY_ROT180)
	var sculpt := SculptTool.new()
	sculpt.paint_material = 5
	sculpt.radius_m = 8.0
	sculpt.falloff = 0.0
	sculpt.begin_stroke(MapState.field, 30.0, 30.0, true)
	var cmd = sculpt.end_paint()
	t.ok(cmd != null, "paint stroke produced a command")
	t.eq(MapState.material_at(30.0, 30.0), 5, "primary tile painted")
	t.eq(MapState.material_at(130.0, 130.0), 5, "rot180 tile painted")
	UndoStack.clear()
	UndoStack.push(cmd)
	UndoStack.undo()
	t.eq(MapState.material_at(30.0, 30.0), 0, "undo restores primary tile")
	t.eq(MapState.material_at(130.0, 130.0), 0, "undo restores rot180 tile")
	t.ok(not UndoStack.can_undo(), "paint symmetry is one undo step")
	UndoStack.clear()
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)


func _place_undo(t) -> void:
	MapState.has_session = true
	MapState.width_m = 160
	MapState.depth_m = 160
	MapState.active_variant = ""
	MapState.objects = {"": []}
	MapState.next_new_id = 1
	MapState.field = _flat(32, 32, 200)
	ToolState.set_armed({
		"prjid": "avapc",
		"placement_mode": "runtime",
		"template_verified": false,
		"up_convention": "upright",
	})
	ToolState.set_symmetry(ToolState.SYMMETRY_QUAD)
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))
	UndoStack.clear()
	EditActions.place_at(Vector3(20.0, 5.0, 30.0), Vector3.UP, true, log)
	var recs: Array = MapState.objects[""]
	t.eq(recs.size(), 4, "quad places four objects")
	t.eq(logs[logs.size() - 1], "placed 4 (quad symmetry)")
	var yaws: Array = []
	var xz: Array = []
	for rec in recs:
		yaws.append(ToolState.wrap_yaw_deg(float(rec.get("yaw_deg", 0.0))))
		xz.append(Vector2(float(rec.get("x", 0.0)), float(rec.get("z", 0.0))))
		t.eq(str(rec.get("prjid", "")), "avapc")
		t.eq(int(rec.get("team", -1)), 0)
	_eq_pts(t, xz, [
		Vector2(20.0, 30.0), Vector2(30.0, 140.0), Vector2(140.0, 130.0), Vector2(130.0, 20.0),
	], "placed at the four image points")
	t.near(float(yaws[0]), 0.0, 0.001)
	t.near(float(yaws[1]), 90.0, 0.001)
	t.near(float(yaws[2]), 180.0, 0.001)
	t.near(float(yaws[3]), -90.0, 0.001)
	t.ok(UndoStack.can_undo())
	UndoStack.undo()
	t.eq((MapState.objects[""] as Array).size(), 0, "one undo removes all four")
	t.ok(not UndoStack.can_undo())
	UndoStack.redo()
	t.eq((MapState.objects[""] as Array).size(), 4, "redo restores the set")
	UndoStack.undo()

	ToolState.set_armed({
		"prjid": "player",
		"placement_mode": "runtime",
		"up_convention": "upright",
	})
	logs.clear()
	EditActions.place_at(Vector3(20.0, 5.0, 30.0), Vector3.UP, true, log)
	t.eq((MapState.objects[""] as Array).size(), 1, "player stays singular")
	t.ok("placed player" in str(logs[logs.size() - 1]))
	UndoStack.undo()
	ToolState.clear_armed()
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)


func _ramp_undo(t) -> void:
	var field := _flat(32, 32, 200)
	MapState.field = field
	MapState.width_m = 160
	MapState.depth_m = 160
	MapState.objects = {"": []}
	MapState.has_session = true
	ToolState.set_symmetry(ToolState.SYMMETRY_MIRROR_X)
	var sculpt := SculptTool.new()
	sculpt.radius_m = 10.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.0
	var a := Vector3(20.0, 10.0, 40.0)
	var b := Vector3(20.0, 30.0, 80.0)
	var logs: Array = []
	UndoStack.clear()
	EditActions.apply_ramp(sculpt, a, b, func(msg): logs.append(str(msg)))
	t.ok(not logs.is_empty())
	t.ok("mirror x symmetry" in str(logs[logs.size() - 1]))
	var iz := int(floor(60.0 / HeightField.CELL_M))
	var ix0 := int(floor(20.0 / HeightField.CELL_M))
	var ix1 := int(floor(140.0 / HeightField.CELL_M))
	t.ok(field.heights[iz * 32 + ix0] != 200, "ramp touched the primary")
	t.ok(field.heights[iz * 32 + ix1] != 200, "ramp touched the mirror")
	t.eq(field.heights[iz * 32 + ix0], field.heights[iz * 32 + ix1], "ramp endpoints transformed together")
	t.ok(UndoStack.can_undo())
	UndoStack.undo()
	t.eq(field.heights[iz * 32 + ix0], 200)
	t.eq(field.heights[iz * 32 + ix1], 200)
	t.ok(not UndoStack.can_undo(), "ramp symmetry is one undo step")
	UndoStack.clear()
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field


func _eq_pts(t, got: Array, want: Array, msg: String) -> void:
	t.eq(got.size(), want.size(), "%s count" % msg)
	for w in want:
		var hit := false
		for g in got:
			if is_equal_approx(float((g as Vector2).x), float((w as Vector2).x)) \
					and is_equal_approx(float((g as Vector2).y), float((w as Vector2).y)):
				hit = true
				break
		t.ok(hit, "%s missing %s" % [msg, w])


func _eq_cells(t, got: Array, want: Array, msg: String) -> void:
	t.eq(got.size(), want.size(), "%s count" % msg)
	for w in want:
		t.ok(w in got, "%s missing %s" % [msg, w])
