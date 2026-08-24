extends RefCounted
## Place-tool drag-to-aim yaw / deadzone, and buildings follow terrain.


func run(t) -> void:
	_aim_math(t)
	_place_yaw(t)
	_buildings_follow(t)
	_orient_basis(t)


func _aim_math(t) -> void:
	t.eq(EditActions.PLACE_AIM_DEADZONE_PX, 20.0)
	t.ok(not EditActions.place_aim_exceeded(Vector2.ZERO, Vector2(19.9, 0.0)))
	t.ok(EditActions.place_aim_exceeded(Vector2.ZERO, Vector2(20.1, 0.0)))
	var origin := Vector3(10.0, 4.0, 10.0)
	t.near(EditActions.place_aim_yaw_deg(origin, origin + Vector3(0.0, 0.0, 8.0)), 0.0, 0.001, "north = +z")
	t.near(EditActions.place_aim_yaw_deg(origin, origin + Vector3(8.0, 0.0, 0.0)), 90.0, 0.001, "east = +x")
	t.near(EditActions.place_aim_yaw_deg(origin, origin + Vector3(0.0, 0.0, -8.0)), 180.0, 0.001, "south = -z")
	t.near(EditActions.place_aim_yaw_deg(origin, origin + Vector3(-8.0, 0.0, 0.0)), -90.0, 0.001, "west = -x")


func _place_yaw(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_variant := MapState.active_variant
	var saved_field = MapState.field
	var saved_yaw := ToolState.place_yaw_deg
	var saved_ang := ToolState.snap_angle
	var saved_sym := ToolState.symmetry
	var saved_armed: Dictionary = ToolState.armed.duplicate(true)
	MapState.has_session = true
	MapState.width_m = 160
	MapState.depth_m = 160
	MapState.active_variant = ""
	MapState.objects = {"": []}
	MapState.next_new_id = 1
	MapState.field = _flat(32, 32, 200)
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)
	ToolState.snap_angle = 0.0
	ToolState.place_yaw_deg = 45.0
	ToolState.set_armed({
		"prjid": "avapc",
		"placement_mode": "runtime",
		"template_verified": false,
		"up_convention": "upright",
	})
	UndoStack.clear()
	var logs: Array = []
	EditActions.place_at(Vector3(20.0, 5.0, 30.0), Vector3.UP, true, func(msg): logs.append(str(msg)))
	var recs: Array = MapState.objects[""]
	t.eq(recs.size(), 1)
	t.near(float(recs[0].get("yaw_deg", 0.0)), 45.0, 0.001, "place uses ToolState.place_yaw_deg")
	t.eq(str(recs[0].get("up_convention", "")), "upright")
	UndoStack.undo()

	ToolState.snap_angle = 45.0
	ToolState.place_yaw_deg = 40.0
	EditActions.place_at(Vector3(20.0, 5.0, 30.0), Vector3.UP, true, func(msg): logs.append(str(msg)))
	t.near(float((MapState.objects[""] as Array)[0].get("yaw_deg", 0.0)), 45.0, 0.001, "snap_angle applies")
	UndoStack.undo()

	ToolState.snap_angle = 0.0
	ToolState.place_yaw_deg = 12.0
	ToolState.set_armed({
		"prjid": "avtank",
		"placement_mode": "runtime",
		"up_convention": "follow",
		"category": "craft",
	})
	var n := Vector3(1.0, 1.0, 0.0).normalized()
	EditActions.place_at(Vector3(20.0, 5.0, 30.0), n, true, func(msg): logs.append(str(msg)))
	var craft: Dictionary = (MapState.objects[""] as Array)[0]
	t.near(float(craft.get("yaw_deg", 0.0)), rad_to_deg(atan2(n.x, n.z)), 0.05, "follow-normal craft keep slope yaw")
	t.eq(str(craft.get("up_convention", "")), "follow")
	UndoStack.undo()

	ToolState.place_yaw_deg = saved_yaw
	ToolState.snap_angle = saved_ang
	ToolState.set_symmetry(saved_sym)
	if saved_armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(saved_armed)
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.active_variant = saved_variant
	MapState.field = saved_field
	UndoStack.clear()


func _buildings_follow(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_variant := MapState.active_variant
	var saved_field = MapState.field
	var saved_yaw := ToolState.place_yaw_deg
	var saved_ang := ToolState.snap_angle
	var saved_armed: Dictionary = ToolState.armed.duplicate(true)
	MapState.has_session = true
	MapState.width_m = 160
	MapState.depth_m = 160
	MapState.active_variant = ""
	MapState.objects = {"": []}
	MapState.next_new_id = 1
	MapState.field = _flat(32, 32, 200)
	ToolState.snap_angle = 0.0
	ToolState.place_yaw_deg = 30.0
	ToolState.set_armed({
		"prjid": "ibpgen",
		"placement_mode": "runtime",
		"category": "building",
		"up_convention": "upright",
	})
	UndoStack.clear()
	EditActions.place_at(Vector3(20.0, 5.0, 30.0), Vector3.UP, true, func(_m): pass)
	var rec: Dictionary = (MapState.objects[""] as Array)[0]
	t.eq(str(rec.get("up_convention", "")), "follow", "buildings store follow")
	t.near(float(rec.get("yaw_deg", 0.0)), 30.0, 0.001, "buildings keep drag-aim yaw")
	t.ok(ObjectMarkers.follows_terrain(rec))
	t.eq(ObjectMarkers.classify_record(rec), ObjectMarkers.VIEW_BUILDINGS)
	UndoStack.undo()
	ToolState.place_yaw_deg = saved_yaw
	ToolState.snap_angle = saved_ang
	if saved_armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(saved_armed)
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.active_variant = saved_variant
	MapState.field = saved_field
	UndoStack.clear()


func _orient_basis(t) -> void:
	var north := ObjectMarkers.orient_basis(Vector3.UP, 0.0)
	t.near(north.z.x, 0.0, 0.001)
	t.near(north.z.z, 1.0, 0.001)
	t.near(north.y.y, 1.0, 0.001)
	var east := ObjectMarkers.orient_basis(Vector3.UP, 90.0)
	t.near(east.z.x, 1.0, 0.001)
	t.near(east.z.z, 0.0, 0.001)
	var n := Vector3(0.2, 1.0, 0.0).normalized()
	var b := ObjectMarkers.orient_basis(n, 0.0)
	t.near(b.y.x, n.x, 0.001, "follow up matches the terrain normal")
	t.near(b.y.y, n.y, 0.001)
	t.near(b.y.z, n.z, 0.001)
	t.ok(ObjectMarkers.follows_terrain({"prjid": "ibpgen", "category": "building"}))
	t.ok(not ObjectMarkers.follows_terrain({"prjid": "avapc", "category": "craft"}))


func _flat(gx: int, gz: int, fill: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(fill)
	return field
