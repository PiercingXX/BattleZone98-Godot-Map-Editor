extends RefCounted
class_name EditActions
## Object / ramp / select actions used by the shell.

const ObjectCommandScript = preload("res://project/commands/ObjectCommand.gd")

const NUDGE_M := 1.0
const NUDGE_SHIFT_M := 5.0
const ROTATE_DEG := 15.0
const ROTATE_SHIFT_DEG := 90.0


static func select_click(markers: Node3D, camera: Camera3D, viewport: SubViewport, shift: bool) -> void:
	var mouse := viewport.get_mouse_position()
	var id: String = markers.pick(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if id.is_empty():
		MapState.selected_ids.clear()
	elif shift:
		if id in MapState.selected_ids:
			MapState.selected_ids.erase(id)
		else:
			MapState.selected_ids.append(id)
	else:
		MapState.selected_ids = [id] as Array[String]
	markers.highlight(MapState.selected_ids)


static func place_at(p: Vector3, normal: Vector3, keep: bool, log: Callable) -> void:
	var info: Dictionary = ToolState.armed
	var prjid := str(info.get("prjid", ""))
	if prjid.to_lower() == "player" and MapState.player_in_variant(MapState.active_variant):
		log.call("player already placed in this variant")
		return
	var rec := {
		"id": MapState.alloc_id(), "origin": "new", "prjid": prjid,
		"x": p.x, "y": p.y, "z": p.z,
		"yaw_deg": rad_to_deg(atan2(normal.x, normal.z)) if str(info.get("up_convention", "upright")) == "follow" else 0.0,
		"team": _default_team(prjid, info), "label": "%s%s" % [prjid, MapState.next_new_id],
		"up_convention": "upright", "pinned_y": false, "managed": false,
		"required": prjid.to_lower() == "player",
		"template_verified": bool(info.get("template_verified", false)),
		"placement_mode": str(info.get("placement_mode", "runtime")),
	}
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.ADD
	cmd.variant = MapState.active_variant
	cmd.object_id = rec["id"]
	cmd.after = rec
	UndoStack.push(cmd)
	if not keep:
		ToolState.clear_armed()
	log.call("placed %s at %.1f, %.1f (%s)" % [prjid, p.x, p.z, rec["placement_mode"]])


static func delete_selected(log: Callable) -> void:
	for id in MapState.selected_ids.duplicate():
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		if bool(rec.get("required", false)):
			log.call("player object is undeletable")
			continue
		var cmd = ObjectCommandScript.new()
		cmd.kind = ObjectCommandScript.Kind.DELETE
		cmd.variant = MapState.find_object_variant(id)
		cmd.object_id = id
		cmd.before = rec.duplicate(true)
		UndoStack.push(cmd)
	MapState.selected_ids.clear()


static func apply_inspector(edits: Array) -> void:
	_push_edits(edits)


static func nudge_selected(dx: float, dz: float, log: Callable) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	if MapState.selected_ids.is_empty():
		_log(log, "nothing selected")
		return
	var edits: Array = []
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		var before := rec.duplicate(true)
		var after := before.duplicate(true)
		after["x"] = float(before.get("x", 0.0)) + dx
		after["z"] = float(before.get("z", 0.0)) + dz
		if not bool(after.get("pinned_y", false)):
			after["y"] = _terrain_y(float(after["x"]), float(after["z"]))
		if not _record_match(before, after):
			edits.append({"before": before, "after": after})
	if edits.is_empty():
		_log(log, "nothing to nudge")
		return
	_push_edits(edits)
	var n := edits.size()
	_log(log, "nudged %d object%s by %.0f, %.0f m" % [n, "s" if n != 1 else "", dx, dz])


static func rotate_selected(delta_yaw: float, log: Callable) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	if MapState.selected_ids.is_empty():
		_log(log, "nothing selected")
		return
	var edits: Array = []
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		var before := rec.duplicate(true)
		var after := before.duplicate(true)
		after["yaw_deg"] = wrap_yaw_deg(float(before.get("yaw_deg", 0.0)) + delta_yaw)
		if not _record_match(before, after):
			edits.append({"before": before, "after": after})
	if edits.is_empty():
		_log(log, "nothing to rotate")
		return
	_push_edits(edits)
	var n := edits.size()
	_log(log, "rotated %d object%s %+g°" % [n, "s" if n != 1 else "", delta_yaw])


static func try_select_transform(keycode: int, shift: bool, log: Callable) -> bool:
	if ToolState.tool != "select":
		return false
	if MapState.selected_ids.is_empty():
		return false
	if not MapState.has_session:
		return false
	var step := NUDGE_SHIFT_M if shift else NUDGE_M
	match keycode:
		KEY_LEFT:
			nudge_selected(-step, 0.0, log)
			return true
		KEY_RIGHT:
			nudge_selected(step, 0.0, log)
			return true
		KEY_UP:
			nudge_selected(0.0, -step, log)
			return true
		KEY_DOWN:
			nudge_selected(0.0, step, log)
			return true
		KEY_R:
			rotate_selected(ROTATE_SHIFT_DEG if shift else ROTATE_DEG, log)
			return true
	return false


static func gui_text_focused(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var focus := viewport.gui_get_focus_owner()
	if focus == null:
		return false
	return focus is LineEdit or focus is TextEdit or focus is CodeEdit or focus is SpinBox


static func wrap_yaw_deg(deg: float) -> float:
	var y := fposmod(deg + 180.0, 360.0) - 180.0
	if is_equal_approx(y, -180.0):
		return 180.0
	return y


static func apply_ramp(sculpt: SculptTool, a: Vector3, b: Vector3, log: Callable) -> void:
	var delta := b - a
	var length := Vector2(delta.x, delta.z).length()
	if length < 1.0:
		return
	var dir := Vector2(delta.x, delta.z) / length
	var steps := int(ceil(length / HeightField.CELL_M)) + 1
	sculpt.mode = "flatten"
	sculpt.begin_stroke(MapState.field, a.x, a.z, false)
	for i in steps:
		var t := float(i) / float(max(steps - 1, 1))
		sculpt.flatten_target = int(round(lerpf(a.y, b.y, t) / HeightField.HEIGHT_SCALE))
		var c := a + Vector3(dir.x, 0, dir.y) * (t * length)
		sculpt.stamp(MapState.field, c.x, c.z)
	var cmd = sculpt.end_stroke(MapState.field)
	if cmd:
		UndoStack.push(cmd, true)
	log.call("ramp %.0f m  slope %.1f°  (30° is the climb limit)" % [length, rad_to_deg(atan2(absf(b.y - a.y), length))])


static func _push_edits(edits: Array) -> void:
	if edits.is_empty():
		return
	var items: Array = []
	for e in edits:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var before: Dictionary = e.get("before", {})
		var after: Dictionary = e.get("after", {})
		if before.is_empty():
			continue
		var oid := str(before.get("id", ""))
		items.append({
			"object_id": oid,
			"variant": MapState.find_object_variant(oid),
			"before": before,
			"after": after,
		})
	if items.is_empty():
		return
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.EDIT
	cmd.object_id = items[0]["object_id"]
	cmd.variant = items[0]["variant"]
	cmd.before = items[0]["before"]
	cmd.after = items[0]["after"]
	if items.size() > 1:
		cmd.items = items
	UndoStack.push(cmd)


static func _record_match(a: Dictionary, b: Dictionary) -> bool:
	return (
		str(a.get("label", "")) == str(b.get("label", ""))
		and is_equal_approx(float(a.get("x", 0.0)), float(b.get("x", 0.0)))
		and is_equal_approx(float(a.get("y", 0.0)), float(b.get("y", 0.0)))
		and is_equal_approx(float(a.get("z", 0.0)), float(b.get("z", 0.0)))
		and is_equal_approx(float(a.get("yaw_deg", 0.0)), float(b.get("yaw_deg", 0.0)))
		and int(a.get("team", 0)) == int(b.get("team", 0))
		and bool(a.get("pinned_y", false)) == bool(b.get("pinned_y", false))
	)


static func _terrain_y(x: float, z: float) -> float:
	if MapState.field == null:
		return 0.0
	return MapState.field.height_at(x, z)


static func _log(log: Callable, msg: String) -> void:
	if log.is_valid():
		log.call(msg)


static func _default_team(prjid: String, info: Dictionary) -> int:
	var p := prjid.to_lower()
	if p == "player":
		return 1
	if str(info.get("category", "")) in ["scrap", "geyser", "spawn", "environment"] or p == "pspwn_1":
		return 0
	return 0
