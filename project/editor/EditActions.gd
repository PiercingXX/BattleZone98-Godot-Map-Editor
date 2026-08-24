extends RefCounted
class_name EditActions
## Object / ramp / select actions used by the shell.

const ObjectCommandScript = preload("res://project/commands/ObjectCommand.gd")

const NUDGE_M := 1.0
const NUDGE_SHIFT_M := 5.0
const ROTATE_DEG := 15.0
const ROTATE_SHIFT_DEG := 90.0
const MARQUEE_DRAG_PX := 4.0
## Place-tool drag-to-aim: screen pixels before LMB-down becomes a yaw drag.
const PLACE_AIM_DEADZONE_PX := 20.0
## Select-tool query syntax. Also the LineEdit tooltip and help extra.
const OBJECT_QUERY_HELP := "Space-separated terms: class:<glob> (prjid, * wildcard; bare text is a class glob), team:<n>, cat:<category> (asset-index), label:<substr>. Matches the active variant; hidden view-filter categories are skipped."


static func terrain_selection_log(prefix: String = "") -> String:
	if MapState.selection_empty():
		return "deselected" if prefix.is_empty() else "%s (empty)" % prefix
	var n := MapState.selection_cell_count()
	var area := MapState.selection_area_m2()
	var body := "selection: %d cells (~%.0f m²)" % [n, area]
	if prefix.is_empty():
		return body
	return "%s (%s)" % [prefix, body]


static func select_all_terrain(log: Callable = Callable()) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log(log, "open a map first")
		return
	MapState.select_all_terrain()
	_log(log, terrain_selection_log("select all"))


static func deselect_terrain(log: Callable = Callable()) -> void:
	if MapState.selection_empty():
		_log(log, "no selection")
		return
	MapState.clear_selection()
	_log(log, "deselected")


static func invert_terrain(log: Callable = Callable()) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log(log, "open a map first")
		return
	MapState.invert_terrain_selection()
	_log(log, terrain_selection_log("inverted"))


static func feather_terrain(radius_m: float, log: Callable = Callable()) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log(log, "open a map first")
		return
	if MapState.selection_empty():
		_log(log, "no selection to feather")
		return
	if radius_m <= 0.0:
		_log(log, "feather radius must be greater than 0")
		return
	MapState.feather_terrain_selection(radius_m)
	_log(log, terrain_selection_log("feathered %.0f m" % radius_m))


static func grow_terrain(cells: int, log: Callable = Callable()) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log(log, "open a map first")
		return
	if MapState.selection_empty():
		_log(log, "no selection to grow")
		return
	if cells < 1:
		_log(log, "grow by at least 1 cell")
		return
	MapState.grow_terrain_selection(cells)
	_log(log, terrain_selection_log("grew %d cell%s" % [cells, "s" if cells != 1 else ""]))


static func shrink_terrain(cells: int, log: Callable = Callable()) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log(log, "open a map first")
		return
	if MapState.selection_empty():
		_log(log, "no selection to shrink")
		return
	if cells < 1:
		_log(log, "shrink by at least 1 cell")
		return
	MapState.shrink_terrain_selection(cells)
	_log(log, terrain_selection_log("shrunk %d cell%s" % [cells, "s" if cells != 1 else ""]))


static func rematch_material_edges(log: Callable = Callable()) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	if MapState.mat_grid_x < 1 or MapState.mat_grid_z < 1:
		_log(log, "map has no material grid")
		return
	var gx := MapState.mat_grid_x
	var gz := MapState.mat_grid_z
	var x0 := 0
	var z0 := 0
	var x1 := gx - 1
	var z1 := gz - 1
	if not MapState.selection_empty() and MapState.has_heightmap():
		var bounds := _mat_bounds_from_terrain_selection()
		if bounds.size.x < 1 or bounds.size.y < 1:
			_log(log, "selection does not cover any material tiles")
			return
		x0 = maxi(0, bounds.position.x - 1)
		z0 = maxi(0, bounds.position.y - 1)
		x1 = mini(gx - 1, bounds.position.x + bounds.size.x)
		z1 = mini(gz - 1, bounds.position.y + bounds.size.y)
	var w := x1 - x0 + 1
	var d := z1 - z0 + 1
	var before := _copy_materials_rect(x0, z0, w, d)
	MapState.rematch_materials_rect(x0, z0, w, d)
	MapState.flush_gpu()
	var after := _copy_materials_rect(x0, z0, w, d)
	if before == after:
		_log(log, "corners already matched")
		return
	var cmd = MaterialStrokeCommand.new()
	cmd.tool = "match"
	cmd.setup(x0, z0, w, d, before, after)
	UndoStack.push(cmd, true)
	MapState.mark_materials_dirty()
	_log(log, "matched caps and corners")


static func _mat_bounds_from_terrain_selection() -> Rect2i:
	var empty := Rect2i()
	if MapState.selection_empty() or not MapState.has_heightmap():
		return empty
	var field: HeightField = MapState.field
	var hgx := field.grid_x
	var hgz := field.grid_z
	var sel := MapState.terrain_selection
	if sel.size() != hgx * hgz:
		return empty
	var cell := HeightField.CELL_M
	var tile := 20.0
	var min_x := MapState.mat_grid_x
	var min_z := MapState.mat_grid_z
	var max_x := -1
	var max_z := -1
	for hz in hgz:
		for hx in hgx:
			if sel[hz * hgx + hx] == 0:
				continue
			var tx := clampi(int(floor((float(hx) + 0.5) * cell / tile)), 0, MapState.mat_grid_x - 1)
			var tz := clampi(int(floor((float(hz) + 0.5) * cell / tile)), 0, MapState.mat_grid_z - 1)
			min_x = mini(min_x, tx)
			min_z = mini(min_z, tz)
			max_x = maxi(max_x, tx)
			max_z = maxi(max_z, tz)
	if max_x < min_x:
		return empty
	return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)


static func _copy_materials_rect(x0: int, z0: int, w: int, d: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(w * d)
	var gx := MapState.mat_grid_x
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if x >= 0 and z >= 0 and x < gx and z < MapState.mat_grid_z:
				out[i] = MapState.materials[z * gx + x]
			i += 1
	return out


static func select_terrain_by_material(log: Callable = Callable()) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log(log, "open a map first")
		return
	if MapState.mat_grid_x < 1:
		_log(log, "map has no material grid")
		return
	var mat := ToolState.paint_material
	MapState.select_terrain_by_material(mat, MapState.SEL_REPLACE)
	_log(log, terrain_selection_log("select by material %d" % mat))


static func terrain_combine_mode(shift: bool, alt: bool) -> String:
	if alt:
		return MapState.SEL_SUBTRACT
	if shift:
		return MapState.SEL_ADD
	return MapState.SEL_REPLACE


static func hover_status_text(prjid: String, label: String) -> String:
	return "%s %s — click to select" % [prjid, label]


static func screen_rect_from_drag(a: Vector2, b: Vector2) -> Rect2:
	var tl := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var br := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(tl, br - tl)


static func is_marquee_drag(a: Vector2, b: Vector2, threshold_px: float = MARQUEE_DRAG_PX) -> bool:
	return a.distance_to(b) >= threshold_px


static func point_in_screen_rect(p: Vector2, rect: Rect2) -> bool:
	# Inclusive on every edge so a box that lands on a marker still hits it.
	return (
		p.x >= rect.position.x
		and p.x <= rect.position.x + rect.size.x
		and p.y >= rect.position.y
		and p.y <= rect.position.y + rect.size.y
	)


static func ids_in_screen_rect(points: Dictionary, rect: Rect2) -> Array[String]:
	var out: Array[String] = []
	for key in points.keys():
		var raw: Variant = points[key]
		if typeof(raw) != TYPE_VECTOR2:
			continue
		if point_in_screen_rect(raw as Vector2, rect):
			out.append(str(key))
	out.sort()
	return out


static func select_id(id: String, shift: bool, log: Callable = Callable()) -> void:
	if id.is_empty():
		if shift:
			return
		MapState.selected_ids.clear()
		_log(log, "selection cleared")
		return
	if shift:
		if id in MapState.selected_ids:
			MapState.selected_ids.erase(id)
		else:
			MapState.selected_ids.append(id)
	else:
		MapState.selected_ids = [id] as Array[String]


static func select_marquee(ids: Array, shift: bool, log: Callable = Callable()) -> void:
	var picked: Array[String] = []
	var seen: Dictionary = {}
	for raw in ids:
		var id := str(raw)
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		picked.append(id)
	if shift:
		var added := 0
		for id in picked:
			if id not in MapState.selected_ids:
				MapState.selected_ids.append(id)
				added += 1
		if added > 0:
			_log(log, "added %d to selection" % added)
		return
	MapState.selected_ids = picked
	if picked.is_empty():
		_log(log, "selection cleared")
	else:
		_log(log, "selected %d object%s" % [picked.size(), "s" if picked.size() != 1 else ""])


static func select_click(markers: Node3D, camera: Camera3D, viewport: SubViewport, shift: bool, log: Callable = Callable()) -> void:
	var mouse := viewport.get_mouse_position()
	var id: String = markers.pick(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	select_id(id, shift, log)
	markers.highlight(MapState.selected_ids)


static func place_aim_exceeded(from_screen: Vector2, to_screen: Vector2) -> bool:
	return from_screen.distance_to(to_screen) > PLACE_AIM_DEADZONE_PX


## Battlezone yaw: 0 = +z (north), 90 = +x (east).
static func place_aim_yaw_deg(from: Vector3, toward: Vector3) -> float:
	var dx := toward.x - from.x
	var dz := toward.z - from.z
	if dx * dx + dz * dz < 0.0001:
		return ToolState.place_yaw_deg
	return wrap_yaw_deg(rad_to_deg(atan2(dx, dz)))


static func place_at(p: Vector3, normal: Vector3, keep: bool, log: Callable) -> void:
	var info: Dictionary = ToolState.armed
	var prjid := str(info.get("prjid", ""))
	if prjid.to_lower() == "player" and MapState.player_in_variant(MapState.active_variant):
		log.call("player already placed in this variant")
		return
	var snapped := snap_world_xz(p.x, p.z)
	p.x = snapped.x
	p.z = snapped.y
	if ToolState.snap_grid_m > 0.0 and MapState.field != null:
		p.y = _terrain_y(p.x, p.z)
	var is_building := ObjectMarkers.classify_record(info) == ObjectMarkers.VIEW_BUILDINGS
	var up_conv := "follow" if is_building else str(info.get("up_convention", "upright"))
	var yaw0 := ToolState.place_yaw_deg
	# Follow-normal craft keep their facing from the slope, not the last aim.
	if not is_building and up_conv == "follow":
		yaw0 = rad_to_deg(atan2(normal.x, normal.z))
	if ToolState.snap_angle > 0.0:
		yaw0 = SelectionGizmo.snap_angle_deg(yaw0, ToolState.snap_angle)
	yaw0 = wrap_yaw_deg(yaw0)
	var team := _default_team(prjid, info)
	var is_player := prjid.to_lower() == "player"
	var mode := ToolState.effective_symmetry()
	var poses: Array[Dictionary] = []
	if is_player:
		poses = [{"x": p.x, "z": p.z, "yaw_deg": yaw0, "k": 0}] as Array[Dictionary]
	else:
		poses = ToolState.world_image_poses(p.x, p.z, yaw0)
	var recs: Array = []
	for i in poses.size():
		var pose: Dictionary = poses[i]
		var rec := {
			"id": MapState.alloc_id(), "origin": "new", "prjid": prjid,
			"x": float(pose.get("x", p.x)),
			"y": p.y if i == 0 else _terrain_y(float(pose.get("x", p.x)), float(pose.get("z", p.z))),
			"z": float(pose.get("z", p.z)),
			"yaw_deg": wrap_yaw_deg(float(pose.get("yaw_deg", yaw0))),
			"team": team, "label": "%s%s" % [prjid, MapState.next_new_id],
			"up_convention": up_conv, "pinned_y": false, "managed": false,
			"required": is_player,
			"template_verified": bool(info.get("template_verified", false)),
			"placement_mode": str(info.get("placement_mode", "runtime")),
		}
		if info.has("category"):
			rec["category"] = info["category"]
		recs.append(rec)
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.ADD
	cmd.variant = MapState.active_variant
	cmd.object_id = recs[0]["id"]
	cmd.after = recs[0]
	if recs.size() > 1:
		var batch: Array = []
		for rec in recs:
			batch.append({
				"object_id": rec["id"],
				"variant": MapState.active_variant,
				"after": rec,
			})
		cmd.items = batch
	UndoStack.push(cmd)
	if not keep:
		ToolState.clear_armed()
	if recs.size() > 1:
		log.call("placed %d (%s symmetry)" % [recs.size(), ToolState.symmetry_log_name(mode)])
	else:
		log.call("placed %s at %.1f, %.1f (%s)" % [prjid, p.x, p.z, recs[0]["placement_mode"]])


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
		var nx := float(before.get("x", 0.0)) + dx
		var nz := float(before.get("z", 0.0)) + dz
		if ToolState.snap_grid_m > 0.0:
			var snapped := SelectionGizmo.snap_xz(nx, nz, ToolState.snap_grid_m)
			nx = snapped.x
			nz = snapped.y
		after["x"] = nx
		after["z"] = nz
		if not bool(after.get("pinned_y", false)):
			after["y"] = _terrain_y(nx, nz)
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
		var yaw := wrap_yaw_deg(float(before.get("yaw_deg", 0.0)) + delta_yaw)
		if ToolState.snap_angle > 0.0:
			yaw = SelectionGizmo.snap_angle_deg(yaw, ToolState.snap_angle)
		after["yaw_deg"] = yaw
		if not _record_match(before, after):
			edits.append({"before": before, "after": after})
	if edits.is_empty():
		_log(log, "nothing to rotate")
		return
	_push_edits(edits)
	var n := edits.size()
	_log(log, "rotated %d object%s %+.1f°" % [n, "s" if n != 1 else "", delta_yaw])


static func set_selection_team(team: int, log: Callable = Callable()) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	if MapState.selected_ids.is_empty():
		_log(log, "nothing selected")
		return
	var t := clampi(team, 0, 15)
	var edits: Array = []
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		if int(rec.get("team", 0)) == t:
			continue
		var before := rec.duplicate(true)
		var after := before.duplicate(true)
		after["team"] = t
		edits.append({"before": before, "after": after})
	if edits.is_empty():
		_log(log, "already team %d" % t)
		return
	_push_edits(edits)
	var n := edits.size()
	_log(log, "team %d → %d object%s" % [t, n, "s" if n != 1 else ""])


static func parse_object_query(text: String) -> Dictionary:
	var raw := text.strip_edges()
	var empty: Array = []
	if raw.is_empty():
		return {"ok": false, "error": "enter a query", "terms": empty}
	var terms: Array = []
	for part in raw.split(" ", false):
		var token := str(part).strip_edges()
		if token.is_empty():
			continue
		var colon := token.find(":")
		if colon < 0:
			terms.append({"kind": "class", "value": token})
			continue
		var key := token.substr(0, colon).strip_edges().to_lower()
		var value := token.substr(colon + 1).strip_edges()
		match key:
			"class":
				if value.is_empty():
					return {"ok": false, "error": "class: needs a glob", "terms": empty}
				terms.append({"kind": "class", "value": value})
			"team":
				if not value.is_valid_int():
					return {"ok": false, "error": "team: needs a number", "terms": empty}
				terms.append({"kind": "team", "value": value})
			"cat":
				if value.is_empty():
					return {"ok": false, "error": "cat: needs a category", "terms": empty}
				terms.append({"kind": "cat", "value": value})
			"label":
				if value.is_empty():
					return {"ok": false, "error": "label: needs a substring", "terms": empty}
				terms.append({"kind": "label", "value": value})
			_:
				return {"ok": false, "error": "unknown term '%s:'" % key, "terms": empty}
	if terms.is_empty():
		return {"ok": false, "error": "enter a query", "terms": empty}
	return {"ok": true, "error": "", "terms": terms}


static func class_glob_match(prjid: String, pattern: String) -> bool:
	if pattern.is_empty():
		return false
	return prjid.matchn(pattern)


static func category_for_record(rec: Dictionary, asset_index: Dictionary) -> String:
	var prjid := str(rec.get("prjid", ""))
	var classes: Variant = asset_index.get("classes", [])
	if typeof(classes) == TYPE_ARRAY:
		var needle := prjid.to_lower()
		for info in classes:
			if typeof(info) != TYPE_DICTIONARY:
				continue
			if str(info.get("prjid", "")).to_lower() == needle:
				return str(info.get("category", "")).strip_edges().to_lower()
	return str(rec.get("category", "")).strip_edges().to_lower()


static func record_matches_terms(rec: Dictionary, terms: Array, asset_index: Dictionary = {}) -> bool:
	if rec.is_empty():
		return false
	for raw in terms:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var term: Dictionary = raw
		var kind := str(term.get("kind", ""))
		var value := str(term.get("value", ""))
		match kind:
			"class":
				if not class_glob_match(str(rec.get("prjid", "")), value):
					return false
			"team":
				if int(rec.get("team", 0)) != int(value):
					return false
			"cat":
				if category_for_record(rec, asset_index) != value.strip_edges().to_lower():
					return false
			"label":
				if value.to_lower() not in str(rec.get("label", "")).to_lower():
					return false
			_:
				return false
	return true


static func query_matching_ids(
	records: Array,
	terms: Array,
	asset_index: Dictionary = {},
	skip_hidden: bool = false
) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for raw in records:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		if skip_hidden and not ObjectMarkers.is_record_visible(rec):
			continue
		if not record_matches_terms(rec, terms, asset_index):
			continue
		var id := str(rec.get("id", ""))
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		out.append(id)
	return out


static func select_by_query(query: String, add: bool, log: Callable = Callable()) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	var parsed := parse_object_query(query)
	if not bool(parsed.get("ok", false)):
		_log(log, str(parsed.get("error", "invalid query")))
		return
	var recs: Variant = MapState.objects.get(MapState.active_variant, [])
	if typeof(recs) != TYPE_ARRAY:
		recs = []
	var ids := query_matching_ids(recs, parsed.get("terms", []), MapState.asset_index, true)
	if add:
		var added := 0
		for id in ids:
			if id not in MapState.selected_ids:
				MapState.selected_ids.append(id)
				added += 1
		_log(log, "query added %d to selection" % added)
		return
	MapState.selected_ids = ids
	_log(log, "query selected %d object%s" % [ids.size(), "s" if ids.size() != 1 else ""])


static func class_needs_runtime_confirm(info: Dictionary) -> bool:
	return str(info.get("placement_mode", "runtime")) != "bzn"


static func replace_selection_class(
	prjid: String,
	log: Callable = Callable(),
	class_info: Dictionary = {},
	allow_runtime: bool = false
) -> Dictionary:
	var empty := {"ok": false, "error": "", "needs_confirm": false, "count": 0}
	if not MapState.has_session:
		_log(log, "open a map first")
		empty["error"] = "open a map first"
		return empty
	if MapState.selected_ids.is_empty():
		_log(log, "nothing selected")
		empty["error"] = "nothing selected"
		return empty
	var pid := prjid.strip_edges()
	if pid.is_empty():
		_log(log, "pick a class")
		empty["error"] = "pick a class"
		return empty
	if pid.to_lower() == "player":
		_log(log, "cannot replace selection with player")
		empty["error"] = "cannot replace selection with player"
		return empty
	var info := class_info.duplicate(true) if not class_info.is_empty() else MapState.class_info(pid)
	if info.is_empty():
		info = {"prjid": pid, "placement_mode": "runtime", "template_verified": false}
	var mode := str(info.get("placement_mode", "runtime"))
	if mode != "bzn" and not allow_runtime:
		var err := "class %s is not clone-safe (placement_mode=%s) — confirm to replace" % [pid, mode]
		_log(log, err)
		return {
			"ok": false,
			"error": err,
			"needs_confirm": true,
			"count": 0,
			"prjid": pid,
			"class_info": info,
		}
	var edits: Array = []
	var skipped := 0
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		if bool(rec.get("required", false)) or str(rec.get("prjid", "")).to_lower() == "player":
			skipped += 1
			continue
		if str(rec.get("prjid", "")).to_lower() == pid.to_lower():
			continue
		var before := rec.duplicate(true)
		var after := before.duplicate(true)
		after["prjid"] = pid
		if not before.has("placement_mode"):
			before["placement_mode"] = str(rec.get("placement_mode", "bzn"))
		if not before.has("template_verified"):
			before["template_verified"] = bool(rec.get("template_verified", false))
		after["placement_mode"] = mode
		after["template_verified"] = bool(info.get("template_verified", mode == "bzn"))
		edits.append({"before": before, "after": after})
	if edits.is_empty():
		var msg := "already %s" % pid if skipped == 0 else "nothing to replace"
		if skipped > 0 and MapState.selected_ids.size() == skipped:
			msg = "player object class cannot be replaced"
		_log(log, msg)
		empty["error"] = msg
		return empty
	_push_edits(edits)
	var n := edits.size()
	var line := "replaced class → %s on %d object%s" % [pid, n, "s" if n != 1 else ""]
	if skipped > 0:
		line += " (skipped %d required)" % skipped
	_log(log, line)
	return {"ok": true, "error": "", "needs_confirm": false, "count": n}


static func filter_visible_ids(ids: Array) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for raw in ids:
		var id := str(raw)
		if id.is_empty() or seen.has(id):
			continue
		if not ObjectMarkers.is_id_pickable(id):
			continue
		seen[id] = true
		out.append(id)
	return out


static func select_all_visible(log: Callable = Callable()) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	var ids: Array[String] = []
	var recs: Variant = MapState.objects.get(MapState.active_variant, [])
	if typeof(recs) != TYPE_ARRAY:
		recs = []
	for rec in recs:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		if not ObjectMarkers.is_record_visible(rec):
			continue
		var id := str(rec.get("id", ""))
		if id.is_empty():
			continue
		ids.append(id)
	MapState.selected_ids = ids
	if ids.is_empty():
		_log(log, "selection cleared")
	else:
		_log(log, "selected %d object%s" % [ids.size(), "s" if ids.size() != 1 else ""])


static func deselect_hidden(log: Callable = Callable()) -> int:
	var kept: Array[String] = []
	var n := 0
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty() or ObjectMarkers.is_record_visible(rec):
			kept.append(id)
		else:
			n += 1
	if n == 0:
		return 0
	MapState.selected_ids = kept
	_log(log, "deselected %d hidden object%s" % [n, "s" if n != 1 else ""])
	return n


static func try_select_transform(keycode: int, shift: bool, log: Callable) -> bool:
	if ToolState.tool != "select":
		return false
	if MapState.selected_ids.is_empty():
		return false
	if not MapState.has_session:
		return false
	var step := nudge_step_m(shift)
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
			rotate_selected(rotate_step_deg(shift), log)
			return true
	return false


static func gui_text_focused(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var focus := viewport.gui_get_focus_owner()
	if focus == null:
		return false
	return focus is LineEdit or focus is TextEdit or focus is CodeEdit or focus is SpinBox


static func nudge_step_m(shift: bool) -> float:
	var grid := ToolState.snap_grid_m
	if grid > 0.0:
		return grid * (5.0 if shift else 1.0)
	return NUDGE_SHIFT_M if shift else NUDGE_M


static func rotate_step_deg(shift: bool) -> float:
	var ang := ToolState.snap_angle
	if ang > 0.0:
		return ROTATE_SHIFT_DEG if shift else ang
	return ROTATE_SHIFT_DEG if shift else ROTATE_DEG


static func snap_world_xz(x: float, z: float) -> Vector2:
	return SelectionGizmo.snap_xz(x, z, ToolState.snap_grid_m)


static func apply_selection_transform(
	dx: float, dz: float, delta_yaw: float, pivot: Vector3, log: Callable = Callable()
) -> void:
	if not MapState.has_session:
		_log(log, "open a map first")
		return
	if MapState.selected_ids.is_empty():
		_log(log, "nothing selected")
		return
	if is_zero_approx(dx) and is_zero_approx(dz) and is_zero_approx(delta_yaw):
		_log(log, "nothing to transform")
		return
	var edits: Array = []
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		var before := rec.duplicate(true)
		var pose := SelectionGizmo.transformed_xz_yaw(
			float(before.get("x", 0.0)),
			float(before.get("z", 0.0)),
			float(before.get("yaw_deg", 0.0)),
			dx,
			dz,
			delta_yaw,
			pivot,
		)
		var after := before.duplicate(true)
		after["x"] = float(pose.get("x", after.get("x", 0.0)))
		after["z"] = float(pose.get("z", after.get("z", 0.0)))
		after["yaw_deg"] = wrap_yaw_deg(float(pose.get("yaw_deg", after.get("yaw_deg", 0.0))))
		if not bool(after.get("pinned_y", false)):
			after["y"] = _terrain_y(float(after["x"]), float(after["z"]))
		if not _record_match(before, after):
			edits.append({"before": before, "after": after})
	if edits.is_empty():
		_log(log, "nothing to transform")
		return
	_push_edits(edits)
	var n := edits.size()
	if is_zero_approx(dx) and is_zero_approx(dz):
		_log(log, "rotated %d object%s %+.1f°" % [n, "s" if n != 1 else "", delta_yaw])
	elif is_zero_approx(delta_yaw):
		_log(log, "moved %d object%s by %.1f, %.1f m" % [n, "s" if n != 1 else "", dx, dz])
	else:
		_log(log, "moved %d object%s by %.1f, %.1f m  rotated %+.1f°" % [
			n, "s" if n != 1 else "", dx, dz, delta_yaw,
		])


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
	# The march is one dab per cell, already the right density. A user's
	# brush spacing gate would drop most of them and leave a stepped ramp,
	# so this stroke opts out of the live brush and clears the gate itself.
	sculpt.follow_tool_state = false
	sculpt.spacing_frac = 0.0
	sculpt.spacing_ms = 0
	sculpt.begin_stroke(MapState.field, a.x, a.z, false)
	for i in steps:
		var t := float(i) / float(max(steps - 1, 1))
		sculpt.flatten_target = int(round(lerpf(a.y, b.y, t) / HeightField.HEIGHT_SCALE))
		var c := a + Vector3(dir.x, 0, dir.y) * (t * length)
		sculpt.stamp(MapState.field, c.x, c.z)
	var cmd = sculpt.end_stroke(MapState.field)
	# The shell reuses one SculptTool for every stroke; the next interactive
	# one must go back to following the live brush.
	sculpt.follow_tool_state = true
	if cmd:
		UndoStack.push(cmd, true)
	var line := "ramp %.0f m  slope %.1f°  (30° is the climb limit)" % [
		length, rad_to_deg(atan2(absf(b.y - a.y), length)),
	]
	var copies := ToolState.world_image_points(a.x, a.z).size()
	if copies > 1:
		line += "  (%s symmetry)" % ToolState.symmetry_log_name(ToolState.effective_symmetry())
	log.call(line)


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


static func variant_display_name(variant: String) -> String:
	return ObjectMarkers.variant_display_name(variant)


static func variant_object_count(variant: String) -> int:
	var recs: Variant = MapState.objects.get(variant, [])
	if typeof(recs) != TYPE_ARRAY:
		return 0
	return (recs as Array).size()


static func known_variants() -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var raw: Variant = MapState.manifest.get("variants", [])
	if typeof(raw) == TYPE_ARRAY and not (raw as Array).is_empty():
		for v in raw:
			var key := str(v)
			if seen.has(key):
				continue
			seen[key] = true
			out.append(key)
		return out
	for key in MapState.objects.keys():
		var s := str(key)
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	if out.is_empty():
		out.append("")
	return out


static func other_variants(from_variant: String = "__active__") -> Array[String]:
	var current := MapState.active_variant if from_variant == "__active__" else from_variant
	var out: Array[String] = []
	for v in known_variants():
		if v != current:
			out.append(v)
	return out


static func fill_variant_picker(menu: PopupMenu) -> void:
	if menu == null:
		return
	menu.clear()
	var id := 0
	for v in other_variants():
		var text := "%s (%d)" % [variant_display_name(v), variant_object_count(v)]
		menu.add_item(text, id)
		menu.set_item_metadata(menu.item_count - 1, v)
		id += 1


static func is_player_record(rec: Dictionary) -> bool:
	if rec.is_empty():
		return false
	return bool(rec.get("required", false)) or str(rec.get("prjid", "")).to_lower() == "player"


static func copy_to_variant_block_reason() -> String:
	if not MapState.has_session:
		return "open a map first"
	if MapState.selected_ids.is_empty():
		return "nothing selected"
	if other_variants().is_empty():
		return "no other variants"
	var copyable := 0
	var player_only := true
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		if is_player_record(rec):
			continue
		player_only = false
		copyable += 1
	if copyable == 0:
		if player_only and not MapState.selected_ids.is_empty():
			return "player object cannot be copied"
		return "nothing to copy"
	return ""


static func copy_selection_to_variant(target: String, log: Callable = Callable()) -> Dictionary:
	var empty := {"ok": false, "error": "", "count": 0, "ids": []}
	if not MapState.has_session:
		_log(log, "open a map first")
		empty["error"] = "open a map first"
		return empty
	if MapState.selected_ids.is_empty():
		_log(log, "nothing selected")
		empty["error"] = "nothing selected"
		return empty
	var dest := str(target)
	var known := known_variants()
	if dest not in known:
		_log(log, "unknown variant")
		empty["error"] = "unknown variant"
		return empty
	if dest == MapState.active_variant:
		_log(log, "pick a different variant")
		empty["error"] = "pick a different variant"
		return empty
	var batch: Array = []
	var skipped_player := 0
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		if is_player_record(rec):
			skipped_player += 1
			continue
		var after := rec.duplicate(true)
		after["id"] = MapState.alloc_id()
		after["required"] = false
		batch.append({
			"object_id": str(after["id"]),
			"variant": dest,
			"after": after,
		})
	if batch.is_empty():
		var msg := "player object cannot be copied" if skipped_player > 0 else "nothing to copy"
		_log(log, msg)
		empty["error"] = msg
		return empty
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.ADD
	cmd.variant = dest
	cmd.items = batch
	cmd.object_id = str(batch[0]["object_id"])
	cmd.after = batch[0]["after"]
	UndoStack.push(cmd)
	var n := batch.size()
	var dest_name := variant_display_name(dest)
	var line := "copied %d object%s to %s" % [n, "s" if n != 1 else "", dest_name]
	if skipped_player > 0:
		line += " (skipped player)"
	_log(log, line)
	var ids: Array = []
	for item in batch:
		ids.append(str(item["object_id"]))
	return {"ok": true, "error": "", "count": n, "ids": ids}


static func _default_team(prjid: String, info: Dictionary) -> int:
	var p := prjid.to_lower()
	if p == "player":
		return 1
	if str(info.get("category", "")) in ["scrap", "geyser", "spawn", "environment"] or p == "pspwn_1":
		return 0
	return 0
