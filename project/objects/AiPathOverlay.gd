extends Node3D
class_name AiPathOverlay
## Cheap AI-path overlay: line ribbons, point markers, name labels.

## Session-only View toggle (same ownership as BalanceOverlay).
static var enabled: bool = false

const LIFT_M := 1.2
const LABEL_LIFT_M := 10.0
const LINE_WIDTH_M := 1.6
const POINT_RADIUS_M := 4.5
const PICK_POINT_M := 10.0
const PICK_SEG_M := 8.0

var _active: bool = false
var _point_world: Array = []
var _seg_world: Array = []


func _ready() -> void:
	if enabled and MapState.has_session:
		set_active(true)


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		_connect_signals()
		rebuild()
	else:
		_disconnect_signals()
		_clear_geometry()
		_point_world.clear()
		_seg_world.clear()


func is_active() -> bool:
	return _active


func rebuild() -> void:
	_clear_geometry()
	_point_world.clear()
	_seg_world.clear()
	if not _active or not MapState.has_session:
		return
	var recs: Array = MapState.active_paths()
	var field: HeightField = MapState.field
	_build_paths(recs, field)


func pick_point(origin: Vector3, direction: Vector3) -> Dictionary:
	## Closest point marker along the ray. Empty dict on miss.
	if not _active or direction.length_squared() < 0.0001:
		return {}
	var dir := direction.normalized()
	var best := {}
	var best_t := 1.0e9
	var r2 := PICK_POINT_M * PICK_POINT_M
	for rec_v in _point_world:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if bool(rec.get("locked", false)):
			continue
		var p: Vector3 = rec["pos"]
		var t := _ray_point_t(origin, dir, p)
		if t < 0.0:
			continue
		var closest := origin + dir * t
		if closest.distance_squared_to(p) > r2:
			continue
		if t < best_t:
			best_t = t
			best = {
				"path": int(rec.get("path", -1)),
				"point": int(rec.get("point", -1)),
				"pos": p,
				"t": t,
			}
	return best


func pick_path(origin: Vector3, direction: Vector3) -> Dictionary:
	if not _active or direction.length_squared() < 0.0001:
		return {}
	var dir := direction.normalized()
	var best := {}
	var best_t := 1.0e9
	var r := PICK_SEG_M
	for rec_v in _seg_world:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if bool(rec.get("locked", false)):
			continue
		var a: Vector3 = rec["a"]
		var b: Vector3 = rec["b"]
		var hit: Dictionary = _ray_segment(origin, dir, a, b, r)
		if hit.is_empty():
			continue
		var t: float = float(hit["t"])
		if t < best_t:
			best_t = t
			best = {
				"path": int(rec.get("path", -1)),
				"point": int(rec.get("point", -1)),
				"t": t,
			}
	return best


static func is_editable(rec: Dictionary) -> bool:
	var name := str(rec.get("name", ""))
	if not bool(rec.get("has_label", not name.is_empty())):
		return false
	return true


static func kind_of(rec: Dictionary) -> String:
	if not is_editable(rec):
		return "unlabeled"
	if BzOpen.is_respawn_path_name(str(rec.get("name", ""))):
		return "respawn"
	return "nav"


func _build_paths(recs: Array, field: HeightField) -> void:
	var line_mesh := ImmediateMesh.new()
	var line_mat := _line_material()
	line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, line_mat)
	var marker_xfs: Array = []
	var marker_cols: Array = []
	for pi in recs.size():
		var rec_v: Variant = recs[pi]
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pts: Array = rec.get("points", []) if typeof(rec.get("points", [])) == TYPE_ARRAY else []
		var kind := kind_of(rec)
		var locked := not is_editable(rec)
		var col := _color_for(kind, pi == MapState.selected_path_index)
		var world: Array = []
		for qi in pts.size():
			var xz: Array = BzOpen._aipath_point(pts[qi])
			var x := float(xz[0])
			var z := float(xz[1])
			var y := _sample_h(field, x, z) + LIFT_M
			var pos := Vector3(x, y, z)
			world.append(pos)
			_point_world.append({
				"path": pi, "point": qi, "pos": pos, "locked": locked,
			})
			var selected := pi == MapState.selected_path_index and qi == MapState.selected_point_index
			marker_xfs.append(pos)
			marker_cols.append(Color(1.0, 0.92, 0.2) if selected else col)
		for qi in range(world.size() - 1):
			var a: Vector3 = world[qi]
			var b: Vector3 = world[qi + 1]
			_ribbon(line_mesh, a, b, col, LINE_WIDTH_M)
			_seg_world.append({
				"path": pi, "point": qi, "a": a, "b": b, "locked": locked,
			})
		if not world.is_empty():
			var label_pos: Vector3 = world[0]
			label_pos.y += LABEL_LIFT_M - LIFT_M
			_build_label(rec, kind, label_pos, col)
	line_mesh.surface_end()
	if not _seg_world.is_empty():
		var inst := MeshInstance3D.new()
		inst.name = "PathLines"
		inst.mesh = line_mesh
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
	if not marker_xfs.is_empty():
		_build_markers(marker_xfs, marker_cols)


func _build_markers(positions: Array, colors: Array) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = POINT_RADIUS_M
	sphere.height = POINT_RADIUS_M * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sphere
	mm.instance_count = positions.size()
	for i in positions.size():
		var xf := Transform3D()
		xf.origin = positions[i]
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "PathPoints"
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.material_override = _disc_material()
	add_child(inst)


func _build_label(rec: Dictionary, kind: String, pos: Vector3, col: Color) -> void:
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.font_size = 14
	tag.pixel_size = 0.22
	tag.outline_size = 8
	tag.outline_modulate = Color(0.02, 0.02, 0.04, 0.92)
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.render_priority = 14
	var name := str(rec.get("name", ""))
	if name.is_empty():
		name = "(unlabeled)"
	var extra := ""
	if kind == "respawn":
		extra = "  · respawn"
	tag.text = name + extra
	var c := col
	c.a = 1.0
	tag.modulate = c
	tag.position = pos
	add_child(tag)


func _color_for(kind: String, selected: bool) -> Color:
	if selected:
		return Color(1.0, 0.86, 0.18, 0.95)
	match kind:
		"respawn":
			return Color(0.96, 0.52, 0.18, 0.92)
		"unlabeled":
			return Color(0.55, 0.55, 0.58, 0.55)
		_:
			return Color(0.22, 0.82, 0.92, 0.92)


func _ribbon(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var dir := b - a
	if dir.length_squared() < 0.0001:
		return
	var side := Vector3.UP.cross(dir.normalized())
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	side *= width * 0.5
	var a0 := a - side
	var a1 := a + side
	var b0 := b - side
	var b1 := b + side
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a0)
	mesh.surface_add_vertex(b0)
	mesh.surface_add_vertex(b1)
	mesh.surface_add_vertex(a0)
	mesh.surface_add_vertex(b1)
	mesh.surface_add_vertex(a1)


func _disc_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.disable_receive_shadows = true
	return mat


func _line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.disable_receive_shadows = true
	return mat


func _sample_h(field: HeightField, x: float, z: float) -> float:
	if field != null and field.grid_x > 1 and field.grid_z > 1:
		return field.height_at(x, z)
	return 0.0


func _ray_point_t(origin: Vector3, dir: Vector3, point: Vector3) -> float:
	return (point - origin).dot(dir)


func _ray_segment(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float) -> Dictionary:
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 0.0001:
		var t := _ray_point_t(origin, dir, a)
		if t < 0.0:
			return {}
		if (origin + dir * t).distance_squared_to(a) > radius * radius:
			return {}
		return {"t": t}
	# Closest approach of ray and segment.
	var ao := origin - a
	var d_ab := dir.dot(ab)
	var denom := ab_len2 - d_ab * d_ab
	var t_ray: float
	var t_seg: float
	if absf(denom) < 0.0001:
		t_seg = clampf(-ao.dot(ab) / ab_len2, 0.0, 1.0)
		t_ray = (a + ab * t_seg - origin).dot(dir)
	else:
		t_ray = (d_ab * ao.dot(ab) - ab_len2 * ao.dot(dir)) / denom
		t_seg = clampf((ao.dot(ab) + t_ray * d_ab) / ab_len2, 0.0, 1.0)
		t_ray = (a + ab * t_seg - origin).dot(dir)
	if t_ray < 0.0:
		return {}
	var closest := origin + dir * t_ray
	var on_seg := a + ab * t_seg
	if closest.distance_squared_to(on_seg) > radius * radius:
		return {}
	return {"t": t_ray}


func _clear_geometry() -> void:
	var doomed: Array = []
	for child in get_children():
		doomed.append(child)
	for child in doomed:
		remove_child(child)
		(child as Node).free()


func _connect_signals() -> void:
	if not MapState.aipaths_changed.is_connected(_on_aipaths_changed):
		MapState.aipaths_changed.connect(_on_aipaths_changed)
	if not MapState.session_changed.is_connected(_on_session_changed):
		MapState.session_changed.connect(_on_session_changed)
	if not MapState.objects_mutated.is_connected(_on_session_changed):
		MapState.objects_mutated.connect(_on_session_changed)


func _disconnect_signals() -> void:
	if MapState.aipaths_changed.is_connected(_on_aipaths_changed):
		MapState.aipaths_changed.disconnect(_on_aipaths_changed)
	if MapState.session_changed.is_connected(_on_session_changed):
		MapState.session_changed.disconnect(_on_session_changed)
	if MapState.objects_mutated.is_connected(_on_session_changed):
		MapState.objects_mutated.disconnect(_on_session_changed)


func _on_aipaths_changed() -> void:
	if _active:
		rebuild()


func _on_session_changed() -> void:
	if not _active:
		return
	if not MapState.has_session:
		_clear_geometry()
		_point_world.clear()
		_seg_world.clear()
		return
	rebuild()
