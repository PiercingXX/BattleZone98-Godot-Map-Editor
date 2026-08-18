extends Node3D
class_name ObjectMarkers
## Proxy boxes. Selection and a placement ghost. Rebuilds by id-diff.

const VIEW_GEYSERS := "geysers"
const VIEW_SCRAP := "scrap"
const VIEW_SPAWNS := "spawns"
const VIEW_BUILDINGS := "buildings"
const VIEW_UNITS := "units"
const VIEW_PROPS := "props"
const LABEL_RANGE_M := 400.0
const LABEL_MAX := 48
const LABEL_NAME := "ObjectLabel"
const OUTLINE_NAME := "OutlineHull"
const OUTLINE_SCALE := 1.10
const _SKIP_STYLE := [LABEL_NAME, OUTLINE_NAME, "VariantTag"]

## Shared team tint tables. Index 0 is team 1; team 0 is TEAM_NEUTRAL.
const TEAM_NEUTRAL := Color(0.55, 0.55, 0.58)
const TEAM_PALETTE: Array[Color] = [
	Color(0.22, 0.82, 0.35),
	Color(0.88, 0.22, 0.20),
	Color(0.25, 0.48, 0.95),
	Color(0.95, 0.85, 0.18),
	Color(0.85, 0.35, 0.85),
	Color(0.18, 0.82, 0.82),
	Color(0.95, 0.55, 0.15),
]
const TEAM_PALETTE_COLORBLIND: Array[Color] = [
	Color(0.90, 0.62, 0.00),
	Color(0.34, 0.71, 0.91),
	Color(0.00, 0.62, 0.45),
	Color(0.94, 0.89, 0.26),
	Color(0.00, 0.45, 0.70),
	Color(0.84, 0.37, 0.00),
	Color(0.80, 0.47, 0.65),
]

## When true, objects on non-active variants stay in the viewport as
## unpickable onion-skin ghosts. Session-only (Settings is not the owner).
static var ghost_other_variants: bool = false

var _box: BoxMesh
var _ghost: Node3D
var _by_id: Dictionary = {}
var _gltf_cache: Dictionary = {}
var _selected_set: Dictionary = {}
var _hover_id: String = ""
var _hull_mat: StandardMaterial3D


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3(8, 6, 8)
	set_process(false)
	if Settings != null and Settings.has_signal("prefs_changed"):
		if not Settings.prefs_changed.is_connected(_on_prefs_changed):
			Settings.prefs_changed.connect(_on_prefs_changed)


func _on_prefs_changed() -> void:
	apply_visibility()


func _process(_delta: float) -> void:
	if _hover_id.is_empty() or _selected_set.has(_hover_id):
		set_process(false)
		return
	var inst: Node3D = _by_id.get(_hover_id) as Node3D
	if inst == null:
		set_process(false)
		return
	var base_s: Vector3 = inst.get_meta("base_scale", inst.scale)
	var pulse := 1.05 + 0.05 * sin(float(Time.get_ticks_msec()) * 0.01)
	inst.scale = base_s * pulse


func reset() -> void:
	# Session changed: ids from the old map must not survive into the new
	# one (backend ids are only unique within a session).
	for id in _by_id.keys():
		var inst: Node = _by_id[id]
		if inst:
			inst.queue_free()
	_by_id.clear()
	_selected_set.clear()
	_hover_id = ""
	set_process(false)
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func rebuild(objects: Dictionary, field: HeightField) -> void:
	var live: Dictionary = {}
	for variant in objects.keys():
		var records: Variant = objects[variant]
		if typeof(records) != TYPE_ARRAY:
			continue
		var vname := str(variant)
		var ghosted := is_variant_ghosted(vname)
		for rec in records:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			live[str(rec.get("id", ""))] = {
				"rec": rec, "ghosted": ghosted, "variant": vname,
			}
	for id in _by_id.keys():
		if id in live:
			continue
		var gone: Node = _by_id[id]
		if gone:
			gone.queue_free()
		_by_id.erase(id)
	for id in live.keys():
		var rec: Dictionary = live[id]["rec"]
		var ghosted: bool = live[id]["ghosted"]
		var vname := str(live[id]["variant"])
		if _by_id.has(id):
			_update_placed(_by_id[id], rec, field, ghosted, vname)
		else:
			_place(rec, field, ghosted, vname)


func set_ghost(visible: bool, rec: Dictionary, field: HeightField, normal: Vector3) -> void:
	if not visible:
		if _ghost:
			_ghost.visible = false
		return
	var prjid := str(rec.get("prjid", ""))
	if _ghost == null or str(_ghost.get_meta("prjid", "")) != prjid:
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		_ghost = _make_visual(rec, true)
		_ghost.set_meta("prjid", prjid)
		add_child(_ghost)
	_ghost.visible = true
	var x := float(rec.get("x", 0.0))
	var z := float(rec.get("z", 0.0))
	var y := field.height_at(x, z) if field else float(rec.get("y", 0.0))
	_ghost.position = Vector3(x, y, z)
	if rec.get("up_convention", "upright") == "follow" and normal.length_squared() > 0.01:
		_ghost.look_at(_ghost.position + Vector3(normal.x, 0.0, normal.z) + Vector3(0.01, 0, 0), normal)
	else:
		_ghost.rotation = Vector3(0.0, deg_to_rad(float(rec.get("yaw_deg", 0.0))), 0.0)


func highlight(ids: Array) -> void:
	_selected_set.clear()
	for id in ids:
		_selected_set[str(id)] = true
	_refresh_styles()


func preview_poses(poses: Dictionary) -> void:
	for key in poses.keys():
		var inst := _by_id.get(str(key)) as Node3D
		if inst == null:
			continue
		var raw: Variant = poses[key]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var pose: Dictionary = raw
		inst.position = Vector3(
			float(pose.get("x", inst.position.x)),
			float(pose.get("y", inst.position.y)),
			float(pose.get("z", inst.position.z)),
		)
		inst.rotation.y = deg_to_rad(float(pose.get("yaw_deg", rad_to_deg(inst.rotation.y))))


func restore_placed() -> void:
	for id in _by_id.keys():
		var inst := _by_id[id] as Node3D
		if inst == null:
			continue
		var rec := MapState.find_object(str(id))
		if rec.is_empty():
			continue
		var variant := str(inst.get_meta("variant", MapState.find_object_variant(str(id))))
		_update_placed(inst, rec, MapState.field, is_variant_ghosted(variant), variant)
	_refresh_styles()


func refresh_labels(camera: Camera3D) -> void:
	if not Settings.view_labels or camera == null:
		_hide_all_labels()
		return
	var cam := camera.global_position
	var cands: Array = []
	for id in _by_id.keys():
		var inst := _by_id[id] as Node3D
		if inst == null or not inst.visible:
			continue
		var rec := MapState.find_object(str(id))
		if rec.is_empty():
			continue
		var dist := cam.distance_to(inst.global_position)
		cands.append({"id": str(id), "dist": dist})
	var keep := SelectionGizmo.pick_nearest_label_ids(cands, LABEL_RANGE_M, LABEL_MAX)
	var shown: Dictionary = {}
	for id in keep:
		shown[id] = true
	for id in _by_id.keys():
		var inst := _by_id[id] as Node3D
		if inst == null:
			continue
		if shown.has(str(id)):
			_show_label(inst, MapState.find_object(str(id)))
		else:
			_hide_label(inst)


func set_hover(id: String) -> void:
	if _hover_id == id:
		_sync_hover_process()
		return
	_hover_id = id
	_refresh_styles()


func hovered_id() -> String:
	return _hover_id


func apply_visibility() -> void:
	for id in _by_id.keys():
		var inst: Node3D = _by_id[id] as Node3D
		if inst == null:
			continue
		var rec := MapState.find_object(str(id))
		var variant := str(inst.get_meta("variant", MapState.find_object_variant(str(id))))
		var ghosted := is_variant_ghosted(variant)
		inst.set_meta("ghosted", ghosted)
		inst.visible = is_id_visible(str(id))
		if rec.is_empty():
			continue
		if ghosted:
			_apply_ghost_look(inst, rec, variant)
		else:
			_apply_team_accent(inst, rec)
			_apply_fade(inst, false)
		_sync_variant_tag(inst, rec, variant, ghosted)
	_refresh_styles()


static func classify_record(rec: Dictionary) -> String:
	var prjid := str(rec.get("prjid", ""))
	var info := MapState.class_info(prjid)
	var cat := str(info.get("category", "")).strip_edges().to_lower()
	if cat.is_empty():
		cat = str(rec.get("category", "")).strip_edges().to_lower()
	if cat.is_empty():
		cat = _categorize_prjid(prjid)
	return view_group_for_category(cat)


static func view_group_for_category(category: String) -> String:
	match category.strip_edges().to_lower():
		"geyser":
			return VIEW_GEYSERS
		"scrap":
			return VIEW_SCRAP
		"spawn":
			return VIEW_SPAWNS
		"building":
			return VIEW_BUILDINGS
		"craft":
			return VIEW_UNITS
		"pilot":
			return VIEW_UNITS
		_:
			return VIEW_PROPS


static func is_record_visible(rec: Dictionary) -> bool:
	if rec.is_empty():
		return false
	return Settings.view_group_visible(classify_record(rec))


func is_id_visible(id: String) -> bool:
	if id.is_empty():
		return false
	var rec := MapState.find_object(id)
	if rec.is_empty() or not is_record_visible(rec):
		return false
	var variant := MapState.find_object_variant(id)
	if variant == MapState.active_variant:
		return true
	return ghost_other_variants


## True when this variant should draw as an onion-skin ghost of the active one.
static func is_variant_ghosted(variant: String) -> bool:
	return ghost_other_variants and str(variant) != MapState.active_variant


## Click / marquee / hover may only hit the active variant. Ghosts never pick.
static func is_id_pickable(id: String) -> bool:
	if id.is_empty():
		return false
	var rec := MapState.find_object(id)
	if rec.is_empty() or not is_record_visible(rec):
		return false
	return MapState.find_object_variant(id) == MapState.active_variant


static func variant_display_name(variant: String) -> String:
	# Game-mode names instead of the raw BZN suffixes.
	match str(variant):
		"":
			return "DM"
		"_S":
			return "Strat"
		"_ST":
			return "Teams"
		"_SW":
			return "Wingman"
	return variant


static func variant_tint(variant: String) -> Color:
	match str(variant):
		"":
			return Color(0.40, 0.72, 1.00)
		"_S":
			return Color(0.98, 0.72, 0.22)
		"_ST":
			return Color(0.78, 0.42, 0.95)
		"_SW":
			return Color(0.28, 0.90, 0.62)
	return Color(0.70, 0.74, 0.80)


static func team_palette(colorblind: bool = false) -> Array[Color]:
	if colorblind:
		return TEAM_PALETTE_COLORBLIND
	return TEAM_PALETTE


static func team_color(team: int) -> Color:
	if team <= 0:
		return TEAM_NEUTRAL
	var cycle := team_palette(Settings.colorblind_teams)
	return cycle[(team - 1) % cycle.size()]


static func _categorize_prjid(prjid: String) -> String:
	# Prefix fallback matching BzAssets._categorize (prjid only; no backend import).
	var p := prjid.to_lower()
	if p == "player":
		return "craft"
	if p.begins_with("npscr") or p == "sscr_1" or p == "blc-pell":
		return "scrap"
	if p.contains("geiz") or p.contains("geyser"):
		return "geyser"
	if p.begins_with("pspwn"):
		return "spawn"
	return "prop"


func screen_points(camera: Camera3D) -> Dictionary:
	var out: Dictionary = {}
	if camera == null:
		return out
	for id in _by_id.keys():
		var inst: Node3D = _by_id[id]
		if inst == null or not inst.visible:
			continue
		if not is_id_pickable(str(id)):
			continue
		var rec := MapState.find_object(str(id))
		if rec.is_empty():
			continue
		var size := _size_for(str(rec.get("prjid", "")))
		var world := inst.position + Vector3(0.0, size.y * 0.5, 0.0)
		if camera.is_position_behind(world):
			continue
		out[str(id)] = camera.unproject_position(world)
	return out


func _refresh_styles() -> void:
	for id in _by_id.keys():
		var inst: Node3D = _by_id[id]
		if inst == null:
			continue
		if bool(inst.get_meta("ghosted", false)):
			continue
		var selected := _selected_set.has(id)
		var hovered := str(id) == _hover_id and not selected
		_apply_style(inst, selected, hovered)
	_sync_hover_process()


func _sync_hover_process() -> void:
	set_process(not _hover_id.is_empty() and not _selected_set.has(_hover_id))


func _apply_style(root: Node3D, selected: bool, hovered: bool) -> void:
	if not root.has_meta("base_scale"):
		root.set_meta("base_scale", root.scale)
	var base_s: Vector3 = root.get_meta("base_scale")
	if hovered and not selected:
		root.scale = base_s * 1.05
	else:
		root.scale = base_s
	_style_mats(root, selected, hovered)
	_sync_outline(root, selected)


func _style_mats(node: Node, selected: bool, hovered: bool) -> void:
	if node is MeshInstance3D and str(node.name) != OUTLINE_NAME:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		if not mat.has_meta("base_albedo"):
			mat.set_meta("base_albedo", mat.albedo_color)
		var base: Color = mat.get_meta("base_albedo")
		if selected:
			var tinted := base.lerp(Color(1.0, 0.92, 0.15, base.a), 0.38)
			tinted.a = base.a
			mat.albedo_color = tinted
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.88, 0.12)
			mat.emission_energy_multiplier = 1.15
			mat.next_pass = null
		elif hovered:
			var tinted := base.lerp(Color(0.45, 0.92, 1.0, base.a), 0.42)
			tinted.a = base.a
			mat.albedo_color = tinted
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.85, 1.0)
			mat.emission_energy_multiplier = 1.05
			mat.next_pass = null
		else:
			mat.albedo_color = base
			mat.emission_enabled = false
			mat.emission_energy_multiplier = 1.0
			mat.next_pass = null
	for child in node.get_children():
		if _skip_style(child):
			continue
		_style_mats(child, selected, hovered)


func _sync_outline(root: Node, selected: bool) -> void:
	if selected:
		_ensure_outlines(root)
	else:
		_clear_outlines(root)


func _ensure_outlines(node: Node) -> void:
	if node is MeshInstance3D and str(node.name) != OUTLINE_NAME:
		var mi := node as MeshInstance3D
		var hull := mi.get_node_or_null(OUTLINE_NAME) as MeshInstance3D
		if hull == null:
			hull = MeshInstance3D.new()
			hull.name = OUTLINE_NAME
			hull.mesh = mi.mesh
			hull.material_override = _outline_mat()
			hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hull.scale = Vector3.ONE * OUTLINE_SCALE
			mi.add_child(hull)
		else:
			hull.mesh = mi.mesh
			hull.visible = true
	for child in node.get_children():
		if _skip_style(child) and str(child.name) != OUTLINE_NAME:
			continue
		if str(child.name) == OUTLINE_NAME:
			continue
		_ensure_outlines(child)


func _clear_outlines(node: Node) -> void:
	var hull := node.get_node_or_null(OUTLINE_NAME)
	if hull:
		node.remove_child(hull)
		hull.free()
	for child in node.get_children():
		if _skip_style(child):
			continue
		_clear_outlines(child)


func _outline_mat() -> StandardMaterial3D:
	if _hull_mat == null:
		_hull_mat = StandardMaterial3D.new()
		_hull_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hull_mat.albedo_color = Color(1.0, 0.88, 0.16)
		_hull_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_hull_mat.grow = false
		_hull_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_hull_mat.no_depth_test = false
	return _hull_mat


func _skip_style(node: Node) -> bool:
	return str(node.name) in _SKIP_STYLE


func _show_label(inst: Node3D, rec: Dictionary) -> void:
	if rec.is_empty():
		_hide_label(inst)
		return
	var tag := inst.get_node_or_null(LABEL_NAME) as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = LABEL_NAME
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.font_size = 22
		tag.pixel_size = 0.038
		tag.outline_size = 5
		tag.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
		tag.modulate = Color(0.96, 0.96, 0.90, 0.95)
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.add_child(tag)
	tag.visible = true
	tag.text = SelectionGizmo.label_text_for(rec)
	var size := _size_for(str(rec.get("prjid", "")))
	var lift := size.y + 1.6
	var vtag := inst.get_node_or_null("VariantTag") as Label3D
	if vtag != null and vtag.visible:
		lift += 1.4
	tag.position = Vector3(0.0, lift, 0.0)


func _hide_label(inst: Node) -> void:
	if inst == null:
		return
	var tag := inst.get_node_or_null(LABEL_NAME) as Label3D
	if tag:
		tag.visible = false


func _hide_all_labels() -> void:
	for id in _by_id.keys():
		_hide_label(_by_id[id] as Node)


func pick(origin: Vector3, direction: Vector3) -> String:
	var best := ""
	var best_t := 1.0e9
	for id in _by_id.keys():
		var inst: Node3D = _by_id[id]
		if inst == null or not inst.visible:
			continue
		if not is_id_pickable(str(id)):
			continue
		var rec := MapState.find_object(str(id))
		if rec.is_empty():
			continue
		var size := _size_for(str(rec.get("prjid", "")))
		# inst.position is the object's base; the visual extends size.y up.
		var center := inst.position + Vector3(0.0, size.y * 0.5, 0.0)
		var t := _ray_aabb(origin, direction, center, size)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = str(id)
	return best


func _place(rec: Dictionary, field: HeightField, ghosted: bool, variant: String) -> void:
	var inst := _make_visual(rec, ghosted)
	_update_placed(inst, rec, field, ghosted, variant)
	add_child(inst)
	_by_id[str(rec.get("id", ""))] = inst


func _update_placed(inst: Node3D, rec: Dictionary, field: HeightField, ghosted: bool, variant: String) -> void:
	var x := float(rec.get("x", 0.0))
	var z := float(rec.get("z", 0.0))
	var y := float(rec.get("y", 0.0))
	if field and field.grid_x > 0 and not bool(rec.get("pinned_y", false)):
		y = field.height_at(x, z)
	inst.position = Vector3(x, y, z)
	inst.rotation.y = deg_to_rad(float(rec.get("yaw_deg", 0.0)))
	inst.set_meta("variant", variant)
	inst.set_meta("ghosted", ghosted)
	var shown := is_record_visible(rec)
	if shown and variant != MapState.active_variant:
		shown = ghost_other_variants
	inst.visible = shown
	if ghosted:
		_apply_ghost_look(inst, rec, variant)
	else:
		_apply_team_accent(inst, rec)
		_apply_fade(inst, false)
	_sync_variant_tag(inst, rec, variant, ghosted)


func _apply_fade(node: Node, faded: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
			var c: Color = mat.get_meta("base_albedo", mat.albedo_color)
			c.a = 0.28 if faded else 1.0
			mat.albedo_color = c
			mat.set_meta("base_albedo", c)
	for child in node.get_children():
		if _skip_style(child):
			continue
		_apply_fade(child, faded)


func _apply_ghost_look(root: Node, rec: Dictionary, variant: String) -> void:
	var tint := variant_tint(variant)
	tint.a = 0.28
	_paint_ghost_mats(root, tint)
	# Keep a whisper of team so stacked ghosts of different sides still read.
	var team := int(rec.get("team", 0))
	if team > 0:
		var accent := team_color(team)
		accent.a = 0.28
		_tint_ghost_toward(root, accent, 0.28)


func _paint_ghost_mats(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = col
		mat.set_meta("base_albedo", col)
		mat.emission_enabled = true
		mat.emission = Color(col.r, col.g, col.b)
		mat.emission_energy_multiplier = 0.35
	for child in node.get_children():
		if _skip_style(child):
			continue
		_paint_ghost_mats(child, col)


func _tint_ghost_toward(node: Node, accent: Color, weight: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			var mixed := mat.albedo_color.lerp(accent, weight)
			mixed.a = mat.albedo_color.a
			mat.albedo_color = mixed
			mat.set_meta("base_albedo", mixed)
	for child in node.get_children():
		if _skip_style(child):
			continue
		_tint_ghost_toward(child, accent, weight)


func _sync_variant_tag(inst: Node3D, rec: Dictionary, variant: String, ghosted: bool) -> void:
	var tag := inst.get_node_or_null("VariantTag") as Label3D
	if not ghosted:
		if tag:
			tag.visible = false
		return
	if tag == null:
		tag = Label3D.new()
		tag.name = "VariantTag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.font_size = 28
		tag.pixel_size = 0.045
		tag.outline_size = 6
		tag.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.add_child(tag)
	tag.visible = true
	tag.text = variant_display_name(variant)
	var tint := variant_tint(variant)
	tint.a = 0.92
	tag.modulate = tint
	var size := _size_for(str(rec.get("prjid", "")))
	tag.position = Vector3(0.0, size.y + 1.15, 0.0)


func _make_visual(rec: Dictionary, faded: bool) -> Node3D:
	var prjid := str(rec.get("prjid", ""))
	var loaded := _load_gltf(prjid)
	if loaded != null:
		if faded:
			_fade(loaded)
		_apply_team_accent(loaded, rec)
		return loaded
	var inst := MeshInstance3D.new()
	inst.mesh = _box
	var size := _size_for(prjid)
	inst.scale = Vector3(size.x / _box.size.x, size.y / _box.size.y, size.z / _box.size.z)
	# Local Y is in pre-scale mesh units so world offset is exactly size.y / 2
	# (pick() uses wrap.position + size.y * 0.5).
	inst.position.y = _box.size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _color_for(prjid, int(rec.get("team", 0)))
	if faded:
		mat.albedo_color.a = 0.22
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.set_meta("base_albedo", mat.albedo_color)
	inst.material_override = mat
	var wrap := Node3D.new()
	wrap.add_child(inst)
	return wrap


func _apply_team_accent(root: Node, rec: Dictionary) -> void:
	var col := _color_for(str(rec.get("prjid", "")), int(rec.get("team", 0)))
	_paint_accent(root, col)


func _paint_accent(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		var painted := col
		painted.a = mat.albedo_color.a
		mat.albedo_color = painted
		mat.set_meta("base_albedo", painted)
	for child in node.get_children():
		if _skip_style(child):
			continue
		_paint_accent(child, col)


func _load_gltf(prjid: String) -> Node3D:
	var info := MapState.class_info(prjid)
	var path := str(info.get("mesh", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if not _gltf_cache.has(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			return null
		var scene := doc.generate_scene(state)
		_gltf_cache[path] = scene
	var proto: Node = _gltf_cache[path]
	if proto == null:
		return null
	return proto.duplicate() as Node3D


func _fade(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.85, 1.0, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
	for child in node.get_children():
		_fade(child)


func _size_for(prjid: String) -> Vector3:
	var info := MapState.class_info(prjid)
	if not info.is_empty():
		var fp: Array = info.get("footprint_m", [8, 8])
		var h := float(info.get("height_m", 6.0))
		return Vector3(maxf(float(fp[0]), 2.0), maxf(h, 1.0), maxf(float(fp[1]), 2.0))
	var p := prjid.to_lower()
	if p == "player":
		return Vector3(8, 5, 8)
	if p == "pspwn_1":
		return Vector3(5, 2, 5)
	if "geyser" in p or p == "eggeizr1":
		return Vector3(14, 8, 14)
	return Vector3(8, 6, 8)


func _color_for(prjid: String, team: int = 0) -> Color:
	var base := _category_color(prjid)
	var accent := team_color(team)
	var weight := 0.28 if team <= 0 else 0.62
	return base.lerp(accent, weight)


func _category_color(prjid: String) -> Color:
	var p := prjid.to_lower()
	if p == "player":
		return Color(0.2, 0.85, 0.35)
	if p == "pspwn_1":
		return Color(0.95, 0.8, 0.2)
	if "geyser" in p or p == "eggeizr1":
		return Color(0.95, 0.45, 0.15)
	if p.begins_with("npscr") or p == "sscr_1":
		return Color(0.85, 0.7, 0.2)
	var info := MapState.class_info(prjid)
	match str(info.get("category", "")):
		"building":
			return Color(0.45, 0.5, 0.75)
		"craft":
			return Color(0.3, 0.65, 0.4)
		"environment":
			return Color(0.3, 0.55, 0.5)
	return Color(0.75, 0.75, 0.8)


func _ray_aabb(origin: Vector3, dir: Vector3, center: Vector3, size: Vector3) -> float:
	var minp := center - size * 0.5
	var maxp := center + size * 0.5
	var tmin := -1.0e9
	var tmax := 1.0e9
	for i in 3:
		var o := origin[i]
		var d := dir[i]
		var mn := minp[i]
		var mx := maxp[i]
		if absf(d) < 0.0000001:
			if o < mn or o > mx:
				return -1.0
			continue
		var t1 := (mn - o) / d
		var t2 := (mx - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return tmin if tmin >= 0.0 else tmax
