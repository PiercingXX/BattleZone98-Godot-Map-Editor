extends RefCounted
class_name EditActions
## Object / ramp / select actions used by the shell.

const ObjectCommandScript = preload("res://project/commands/ObjectCommand.gd")


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


static func apply_inspector(before: Dictionary, after: Dictionary) -> void:
	if before.is_empty():
		return
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.EDIT
	cmd.variant = MapState.find_object_variant(str(before.get("id", "")))
	cmd.object_id = str(before.get("id", ""))
	cmd.before = before
	cmd.after = after
	UndoStack.push(cmd)


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


static func _default_team(prjid: String, info: Dictionary) -> int:
	var p := prjid.to_lower()
	if p == "player":
		return 1
	if str(info.get("category", "")) in ["scrap", "geyser", "spawn", "environment"] or p == "pspwn_1":
		return 0
	return 0
