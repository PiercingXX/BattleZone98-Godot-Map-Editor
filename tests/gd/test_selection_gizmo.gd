extends RefCounted
## Snap math, selection pivot, gizmo drag deltas, labels, outline hull.


func run(t) -> void:
	var snap := _snapshot()
	_snap_math(t)
	_pivot_and_transform(t)
	_gizmo_drag(t)
	_nudge_rotate_place(t)
	_labels_and_outline(t)
	await _ui_and_help(t)
	_persist(t)
	_restore(snap)


func _snap_math(t) -> void:
	t.near(SelectionGizmo.snap_scalar(21.0, 0.0), 21.0, 0.001, "grid off is identity")
	t.near(SelectionGizmo.snap_scalar(21.0, 1.0), 21.0, 0.001)
	t.near(SelectionGizmo.snap_scalar(21.0, 5.0), 20.0, 0.001)
	t.near(SelectionGizmo.snap_scalar(23.0, 5.0), 25.0, 0.001)
	t.near(SelectionGizmo.snap_scalar(14.0, 10.0), 10.0, 0.001)
	t.near(SelectionGizmo.snap_scalar(16.0, 10.0), 20.0, 0.001)
	t.near(SelectionGizmo.snap_scalar(9.0, 20.0), 0.0, 0.001)
	t.near(SelectionGizmo.snap_scalar(11.0, 20.0), 20.0, 0.001)
	var xz := SelectionGizmo.snap_xz(21.0, 33.0, 5.0)
	t.near(xz.x, 20.0, 0.001)
	t.near(xz.y, 35.0, 0.001)
	t.near(SelectionGizmo.snap_angle_deg(22.0, 0.0), 22.0, 0.001, "angle off")
	t.near(SelectionGizmo.snap_angle_deg(22.0, 15.0), 15.0, 0.001)
	t.near(SelectionGizmo.snap_angle_deg(38.0, 45.0), 45.0, 0.001)
	t.near(SelectionGizmo.snap_angle_deg(40.0, 90.0), 0.0, 0.001)
	t.near(SelectionGizmo.snap_angle_deg(175.0, 15.0), 180.0, 0.001)
	t.eq(SelectionGizmo.coerce_snap_grid(7), 5.0)
	t.eq(SelectionGizmo.coerce_snap_grid("10 m"), 10.0)
	t.eq(SelectionGizmo.coerce_snap_grid("off"), 0.0)
	t.eq(SelectionGizmo.coerce_snap_grid(null), 0.0)
	t.eq(SelectionGizmo.coerce_snap_angle("45°"), 45.0)
	t.eq(SelectionGizmo.coerce_snap_angle(12), 15.0)
	t.eq(SelectionGizmo.coerce_snap_angle("nope"), 0.0)
	t.eq(Settings.coerce_snap_grid(20), 20.0)
	t.eq(Settings.coerce_snap_angle(90), 90.0)


func _pivot_and_transform(t) -> void:
	var p := SelectionGizmo.selection_pivot([
		{"x": 10.0, "y": 2.0, "z": 20.0},
		{"x": 30.0, "y": 6.0, "z": 40.0},
	])
	t.near(p.x, 20.0, 0.001, "pivot x average")
	t.near(p.y, 4.0, 0.001, "pivot y average")
	t.near(p.z, 30.0, 0.001, "pivot z average")
	t.eq(SelectionGizmo.selection_pivot([]), Vector3.ZERO)
	var rot := SelectionGizmo.rotate_point_xz(10.0, 0.0, 0.0, 0.0, 90.0)
	t.near(rot.x, 0.0, 0.001, "90° around origin x")
	t.near(rot.y, -10.0, 0.001, "90° around origin z")
	var pose := SelectionGizmo.transformed_xz_yaw(10.0, 0.0, 0.0, 0.0, 0.0, 90.0, Vector3.ZERO)
	t.near(float(pose["x"]), 0.0, 0.001)
	t.near(float(pose["z"]), -10.0, 0.001)
	t.near(float(pose["yaw_deg"]), 90.0, 0.001)
	var moved := SelectionGizmo.transformed_xz_yaw(10.0, 4.0, 15.0, 5.0, -2.0, 0.0, Vector3.ZERO)
	t.near(float(moved["x"]), 15.0, 0.001)
	t.near(float(moved["z"]), 2.0, 0.001)
	t.near(float(moved["yaw_deg"]), 15.0, 0.001)
	t.eq(SelectionGizmo.label_text_for({"prjid": "avapc"}), "avapc")
	t.eq(SelectionGizmo.label_text_for({"prjid": "avapc", "label": "avapc"}), "avapc")
	t.eq(SelectionGizmo.label_text_for({"prjid": "avapc", "label": "Alpha"}), "avapc  Alpha")
	var ids := SelectionGizmo.pick_nearest_label_ids([
		{"id": "far", "dist": 500.0},
		{"id": "a", "dist": 40.0},
		{"id": "b", "dist": 10.0},
		{"id": "c", "dist": 80.0},
		{"id": "", "dist": 1.0},
	], 400.0, 2)
	t.eq(ids, ["b", "a"] as Array[String], "nearest first, cap 2, drop out-of-range")


func _gizmo_drag(t) -> void:
	var pivot := Vector3(10.0, 5.0, 20.0)
	var dx := SelectionGizmo.move_delta(
		SelectionGizmo.HANDLE_X, pivot, Vector3(10, 5, 20), Vector3(16, 5, 28), 0.0
	)
	t.near(dx.x, 6.0, 0.001, "X handle ignores Z")
	t.near(dx.z, 0.0, 0.001)
	var dz := SelectionGizmo.move_delta(
		SelectionGizmo.HANDLE_Z, pivot, Vector3(10, 5, 20), Vector3(16, 5, 28), 0.0
	)
	t.near(dz.x, 0.0, 0.001, "Z handle ignores X")
	t.near(dz.z, 8.0, 0.001)
	var free := SelectionGizmo.move_delta(
		SelectionGizmo.HANDLE_XZ, pivot, Vector3(10, 5, 20), Vector3(16, 5, 28), 0.0
	)
	t.near(free.x, 6.0, 0.001)
	t.near(free.z, 8.0, 0.001)
	var snapped := SelectionGizmo.move_delta(
		SelectionGizmo.HANDLE_XZ, Vector3(2, 0, 2), Vector3(2, 0, 2), Vector3(4, 0, 5), 5.0
	)
	t.near(snapped.x, 3.0, 0.001, "dest snaps to 5, delta from 2 is 3")
	t.near(snapped.z, 3.0, 0.001)
	t.eq(
		SelectionGizmo.move_delta(SelectionGizmo.HANDLE_YAW, pivot, pivot, pivot + Vector3(1, 0, 0), 0.0),
		Vector3.ZERO,
	)
	var yaw := SelectionGizmo.yaw_delta_deg(
		Vector3.ZERO, Vector3(10, 0, 0), Vector3(0, 0, -10), 0.0
	)
	t.near(yaw, 90.0, 0.001, "quarter-turn yaw")
	var yaw_s := SelectionGizmo.yaw_delta_deg(
		Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, -2), 15.0
	)
	t.near(yaw_s, 15.0, 0.001, "angle snap on drag")
	var miss := SelectionGizmo.ray_ground(Vector3(0, 10, 0), Vector3(1, 0, 0), 0.0)
	t.ok(not miss.is_finite(), "parallel ray misses ground")
	var hit := SelectionGizmo.ray_ground(Vector3(0, 10, 0), Vector3(0, -1, 0), 4.0)
	t.near(hit.y, 4.0, 0.001)

	var g := SelectionGizmo.new()
	t.tree.root.add_child(g)
	g.sync_at(Vector3(0.0, 10.0, 0.0), null, "")
	var c: Dictionary = g.pick(Vector3(0.0, 40.0, 0.0), Vector3(0.0, -1.0, 0.0))
	t.eq(str(c.get("handle", "")), SelectionGizmo.HANDLE_XZ, "center handle from above")
	var hx: Dictionary = g.pick(Vector3(10.0, 40.0, 0.0), Vector3(0.0, -1.0, 0.0))
	t.eq(str(hx.get("handle", "")), SelectionGizmo.HANDLE_X, "X arrow from above")
	var hz: Dictionary = g.pick(Vector3(0.0, 40.0, 10.0), Vector3(0.0, -1.0, 0.0))
	t.eq(str(hz.get("handle", "")), SelectionGizmo.HANDLE_Z, "Z arrow from above")
	var hy: Dictionary = g.pick(Vector3(9.9, 40.0, 9.9), Vector3(0.0, -1.0, 0.0))
	t.eq(str(hy.get("handle", "")), SelectionGizmo.HANDLE_YAW, "yaw ring diagonal")
	g.hide_gizmo()
	var hidden: Dictionary = g.pick(Vector3(0.0, 40.0, 0.0), Vector3(0.0, -1.0, 0.0))
	t.eq(str(hidden.get("handle", "")), SelectionGizmo.HANDLE_NONE, "hidden gizmo does not pick")
	g.queue_free()


func _nudge_rotate_place(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_field = MapState.field
	var saved_tool := ToolState.tool
	var saved_grid := ToolState.snap_grid_m
	var saved_ang := ToolState.snap_angle
	var saved_armed: Dictionary = ToolState.armed.duplicate(true)
	var saved_next := MapState.next_new_id
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.field = _flat(32, 32, 200)
	MapState.objects = {
		"": [
			_rec("g-1", 21.0, 21.0, 10.0, false, 5.0),
			_rec("g-2", 40.0, 40.0, 10.0, true, 7.0),
		],
	}
	MapState.selected_ids = ["g-1", "g-2"] as Array[String]
	ToolState.set_tool("select")
	ToolState.snap_grid_m = 5.0
	ToolState.snap_angle = 15.0
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	t.near(EditActions.nudge_step_m(false), 5.0, 0.001, "nudge step is grid")
	t.near(EditActions.nudge_step_m(true), 25.0, 0.001, "shift nudge is 5× grid")
	t.near(EditActions.rotate_step_deg(false), 15.0, 0.001, "R step is snap angle")
	t.near(EditActions.rotate_step_deg(true), 90.0, 0.001, "Shift+R stays 90")

	t.ok(EditActions.try_select_transform(KEY_RIGHT, false, log))
	t.near(float(MapState.find_object("g-1").get("x", 0.0)), 25.0, 0.001, "nudge then snap")
	t.near(float(MapState.find_object("g-2").get("x", 0.0)), 45.0, 0.001)
	t.near(float(MapState.find_object("g-1").get("y", 0.0)), 20.0, 0.001, "unpinned re-snaps y")
	t.near(float(MapState.find_object("g-2").get("y", 0.0)), 7.0, 0.001, "pinned keeps y")
	UndoStack.undo()
	t.ok(not UndoStack.can_undo(), "snapped nudge is one undo")

	t.ok(EditActions.try_select_transform(KEY_R, false, log))
	t.near(float(MapState.find_object("g-1").get("yaw_deg", 0.0)), 30.0, 0.001, "10+15 snaps to 30")
	UndoStack.undo()

	var pivot := Vector3(30.0, 5.0, 30.0)
	EditActions.apply_selection_transform(5.0, 0.0, 0.0, pivot, log)
	t.near(float(MapState.find_object("g-1").get("x", 0.0)), 26.0, 0.001)
	t.near(float(MapState.find_object("g-2").get("x", 0.0)), 45.0, 0.001)
	t.ok("moved" in logs[logs.size() - 1])
	UndoStack.undo()
	t.ok(not UndoStack.can_undo(), "gizmo move is one undo")

	EditActions.apply_selection_transform(0.0, 0.0, 90.0, Vector3(21.0, 5.0, 21.0), log)
	t.near(float(MapState.find_object("g-1").get("x", 0.0)), 21.0, 0.001, "pivot object stays")
	t.near(float(MapState.find_object("g-1").get("yaw_deg", 0.0)), 100.0, 0.001)
	UndoStack.undo()

	ToolState.snap_grid_m = 5.0
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)
	ToolState.set_armed({
		"prjid": "avapc", "placement_mode": "runtime", "template_verified": false,
		"up_convention": "upright",
	})
	MapState.objects = {"": []}
	MapState.selected_ids.clear()
	MapState.next_new_id = 1
	var placed := EditActions.snap_world_xz(21.0, 33.0)
	t.near(placed.x, 20.0, 0.001)
	t.near(placed.y, 35.0, 0.001)
	EditActions.place_at(Vector3(21.0, 5.0, 33.0), Vector3.UP, true, log)
	var recs: Array = MapState.objects[""]
	t.eq(recs.size(), 1)
	t.near(float(recs[0].get("x", 0.0)), 20.0, 0.001, "place snaps x")
	t.near(float(recs[0].get("z", 0.0)), 35.0, 0.001, "place snaps z")
	UndoStack.undo()

	ToolState.snap_grid_m = saved_grid
	ToolState.snap_angle = saved_ang
	if saved_armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(saved_armed)
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")
	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.field = saved_field
	MapState.next_new_id = saved_next
	if saved_session:
		MapState.mark_saved()


func _labels_and_outline(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_labels := Settings.view_labels
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.objects = {"": [_rec("lab-1", 8.0, 8.0, 0.0, false, 4.0)]}
	var markers := ObjectMarkers.new()
	t.tree.root.add_child(markers)
	markers.rebuild(MapState.objects, _flat(16, 16, 200))
	markers.highlight(["lab-1"])
	t.ok(_find_named(markers, ObjectMarkers.OUTLINE_NAME) != null, "selected marker has hull")
	var hull := _find_named(markers, ObjectMarkers.OUTLINE_NAME) as MeshInstance3D
	t.ok(hull != null)
	var hmat := hull.material_override as StandardMaterial3D
	t.ok(hmat != null)
	t.eq(hmat.cull_mode, BaseMaterial3D.CULL_FRONT, "inverted-hull front cull")
	t.eq(hmat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	t.ok(hull.scale.x > 1.0, "hull is slightly scaled")
	markers.set_hover("lab-1")
	t.ok(_find_named(markers, ObjectMarkers.OUTLINE_NAME) != null, "selected keeps hull while hover id matches")
	markers.highlight([])
	t.ok(_find_named(markers, ObjectMarkers.OUTLINE_NAME) == null, "deselect removes hull")
	Settings.view_labels = true
	var cam := Camera3D.new()
	cam.position = Vector3(8.0, 20.0, 8.0)
	t.tree.root.add_child(cam)
	markers.refresh_labels(cam)
	var lab := _find_named(markers, ObjectMarkers.LABEL_NAME) as Label3D
	t.ok(lab != null and lab.visible, "label shown in range")
	t.eq(lab.text, "avapc  tag")
	cam.position = Vector3(8.0, 20.0, 2000.0)
	markers.refresh_labels(cam)
	lab = _find_named(markers, ObjectMarkers.LABEL_NAME) as Label3D
	t.ok(lab == null or not lab.visible, "label hidden beyond 400 m")
	Settings.view_labels = false
	markers.refresh_labels(cam)
	lab = _find_named(markers, ObjectMarkers.LABEL_NAME) as Label3D
	t.ok(lab == null or not lab.visible, "labels toggle off")
	cam.queue_free()
	markers.reset()
	markers.queue_free()
	Settings.view_labels = saved_labels
	MapState.has_session = saved_session
	MapState.objects = saved_objects


func _ui_and_help(t) -> void:
	var saved_grid := ToolState.snap_grid_m
	var saved_ang := ToolState.snap_angle
	var saved_tool := ToolState.tool
	ToolState.snap_grid_m = 0.0
	ToolState.snap_angle = 0.0
	var pal: Node = load("res://project/ui/palette/PalettePanel.tscn").instantiate()
	t.tree.root.add_child(pal)
	await t.tree.process_frame
	ToolState.set_tool("select")
	pal.refresh_context()
	var grid: OptionButton = pal.find_child("SnapGrid", true, false)
	var ang: OptionButton = pal.find_child("SnapAngle", true, false)
	t.ok(grid != null and grid.is_visible_in_tree(), "Select panel has grid snap")
	t.ok(ang != null and ang.is_visible_in_tree(), "Select panel has angle snap")
	t.eq(grid.item_count, 5)
	t.eq(ang.item_count, 4)
	grid.select(2)
	grid.item_selected.emit(2)
	t.near(ToolState.snap_grid_m, 5.0, 0.001, "grid control writes ToolState")
	ang.select(2)
	ang.item_selected.emit(2)
	t.near(ToolState.snap_angle, 45.0, 0.001, "angle control writes ToolState")
	pal.queue_free()
	await t.tree.process_frame

	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	var text := body.text.to_lower()
	t.ok("gizmo" in text, "help documents the gizmo")
	t.ok("snap" in text, "help documents snap")
	t.ok("labels" in text, "help documents labels")
	t.ok("yaw" in text)
	help.queue_free()
	await t.tree.process_frame

	var pop := PopupMenu.new()
	t.tree.root.add_child(pop)
	Settings.attach_labels_view_item(pop)
	t.ok(pop.get_item_index(Settings.VIEW_LABELS_ID) >= 0, "View menu has Labels")
	t.eq(pop.get_item_text(pop.get_item_index(Settings.VIEW_LABELS_ID)), "Labels")
	Settings.view_labels = false
	Settings.sync_labels_view_item(pop)
	t.ok(not pop.is_item_checked(pop.get_item_index(Settings.VIEW_LABELS_ID)))
	pop.queue_free()
	await t.tree.process_frame

	ToolState.snap_grid_m = saved_grid
	ToolState.snap_angle = saved_ang
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")


func _persist(t) -> void:
	Settings.snap_grid_m = 10.0
	Settings.snap_angle = 45.0
	Settings.view_labels = true
	Settings.save()
	Settings.snap_grid_m = 0.0
	Settings.snap_angle = 0.0
	Settings.view_labels = false
	Settings._load()
	t.eq(Settings.snap_grid_m, 10.0, "snap grid persists")
	t.eq(Settings.snap_angle, 45.0, "snap angle persists")
	t.ok(Settings.view_labels, "view labels persists")


func _rec(id: String, x: float, z: float, yaw: float, pin: bool, y: float) -> Dictionary:
	return {
		"id": id, "prjid": "avapc", "label": "tag",
		"x": x, "y": y, "z": z, "yaw_deg": yaw,
		"team": 0, "pinned_y": pin, "required": false,
		"placement_mode": "clone",
	}


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field


func _find_named(root: Node, name: String) -> Node:
	if root == null:
		return null
	if root.name == name:
		return root
	for child in root.get_children():
		var found := _find_named(child, name)
		if found:
			return found
	return null


func _snapshot() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"cfg": cfg,
		"grid": ToolState.snap_grid_m,
		"angle": ToolState.snap_angle,
		"labels": Settings.view_labels,
		"sgrid": Settings.snap_grid_m,
		"sangle": Settings.snap_angle,
		"session": MapState.has_session,
		"objects": MapState.objects.duplicate(true),
		"sel": MapState.selected_ids.duplicate(),
		"variant": MapState.active_variant,
		"field": MapState.field,
		"tool": ToolState.tool,
		"armed": ToolState.armed.duplicate(true),
	}


func _restore(snap: Dictionary) -> void:
	if snap["cfg"] == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
		Settings._cfg = ConfigFile.new()
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(snap["cfg"]))
			f.close()
		Settings._load()
	ToolState.snap_grid_m = float(snap["grid"])
	ToolState.snap_angle = float(snap["angle"])
	Settings.view_labels = bool(snap["labels"])
	Settings.snap_grid_m = float(snap["sgrid"])
	Settings.snap_angle = float(snap["sangle"])
	MapState.has_session = bool(snap["session"])
	MapState.objects = snap["objects"]
	MapState.selected_ids = snap["sel"]
	MapState.active_variant = str(snap["variant"])
	MapState.field = snap["field"]
	ToolState.set_tool(str(snap["tool"]) if str(snap["tool"]) != "" else "fly")
	var armed: Dictionary = snap["armed"]
	if armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(armed)
	UndoStack.clear()
