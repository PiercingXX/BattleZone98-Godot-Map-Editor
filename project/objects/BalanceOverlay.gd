extends Node3D
class_name BalanceOverlay
## Design-time fairness overlay: geyser/scrap discs, spawn-pair lines, team totals.

## Session-only View toggle. Settings is not the owner (same as ghost variants).
static var enabled: bool = false

## Recompute delay after objects_mutated.
const DEBOUNCE_S := 0.5
## Pocket radius: same metre bound B3 uses for intra-cluster spawn gaps.
const ECONOMY_RADIUS_M := BzCheckBalance.B3_MAX_SPACING_M
## Pair is fair when |d − mean| / mean is within E5's 15% relative gap.
const FAIR_PAIR_FRAC := BzLayout.E5_GAP
const GEYSER_RADIUS_M := 28.0
const SCRAP_RADIUS_M := 14.0
const LIFT_M := 0.6
const LABEL_LIFT_M := 16.0
const LINE_WIDTH_M := 1.4

var _active: bool = false
var _timer: Timer
var _snapshot: Dictionary = {}


func _ready() -> void:
	_ensure_timer()
	if enabled and MapState.has_session:
		set_active(true)


func set_active(on: bool) -> void:
	_ensure_timer()
	if on == _active:
		return
	_active = on
	if on:
		_connect_signals()
		_recompute()
	else:
		_disconnect_signals()
		if _timer:
			_timer.stop()
		_clear_geometry()
		_snapshot = {}


func schedule_recompute() -> void:
	if not _active:
		return
	_ensure_timer()
	_timer.start(DEBOUNCE_S)


static func compute_objects(objects: Dictionary, variant: String) -> Dictionary:
	var recs: Variant = objects.get(variant, [])
	if typeof(recs) != TYPE_ARRAY:
		return compute([])
	return compute(recs)


static func compute(records: Array) -> Dictionary:
	var circles: Array = []
	var geysers: Array = []
	var scrap: Array = []
	var spawns: Array = []
	for rec in records:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = rec
		if is_geyser_record(d):
			geysers.append(d)
			circles.append(_circle_of(d, "geyser", GEYSER_RADIUS_M))
		elif is_scrap_record(d):
			scrap.append(d)
			circles.append(_circle_of(d, "scrap", SCRAP_RADIUS_M))
		elif is_spawn_record(d):
			spawns.append(d)
	circles.sort_custom(func(a, b):
		var ka := str(a.get("kind", "")) + "\t" + str(a.get("id", ""))
		var kb := str(b.get("kind", "")) + "\t" + str(b.get("id", ""))
		return ka < kb
	)

	var pairs: Array = []
	var mean_pair_m := 0.0
	if spawns.size() >= 2:
		var dists: PackedFloat64Array = PackedFloat64Array()
		for i in spawns.size():
			var a: Dictionary = spawns[i]
			var ap := _xz(a)
			var aid := _id(a)
			for j in range(i + 1, spawns.size()):
				var b: Dictionary = spawns[j]
				var d: float = ap.distance_to(_xz(b))
				dists.append(d)
				var bid := _id(b)
				var first := aid
				var second := bid
				var ax := ap.x
				var az := ap.y
				var bx := float(b.get("x", 0.0))
				var bz := float(b.get("z", 0.0))
				if second < first:
					var tmp_id := first
					first = second
					second = tmp_id
					var tx := ax
					var tz := az
					ax = bx
					az = bz
					bx = tx
					bz = tz
				pairs.append({
					"a_id": first,
					"b_id": second,
					"ax": ax,
					"az": az,
					"bx": bx,
					"bz": bz,
					"distance": d,
					"fair": true,
				})
		var acc := 0.0
		for d in dists:
			acc += d
		mean_pair_m = acc / float(dists.size())
		for pair in pairs:
			var dist: float = float(pair["distance"])
			var fair := true
			if mean_pair_m > 0.0:
				fair = absf(dist - mean_pair_m) <= mean_pair_m * FAIR_PAIR_FRAC
			pair["fair"] = fair
		pairs.sort_custom(func(a, b):
			var ka := str(a.get("a_id", "")) + "\t" + str(a.get("b_id", ""))
			var kb := str(b.get("a_id", "")) + "\t" + str(b.get("b_id", ""))
			return ka < kb
		)

	var clusters: Dictionary = {}
	for s in spawns:
		var team: int = int((s as Dictionary).get("team", 0))
		if not clusters.has(team):
			clusters[team] = []
		var members: Array = clusters[team]
		members.append(s)
		clusters[team] = members
	var teams: Array = []
	var team_ids: Array = clusters.keys()
	team_ids.sort()
	for team in team_ids:
		var members: Array = clusters[team]
		if members.is_empty():
			continue
		var cx := 0.0
		var cz := 0.0
		for s in members:
			var p := _xz(s)
			cx += p.x
			cz += p.y
		cx /= float(members.size())
		cz /= float(members.size())
		var geyser_n := 0
		var scrap_n := 0
		for g in geysers:
			if _within_cluster(g, members):
				geyser_n += 1
		for sc in scrap:
			if _within_cluster(sc, members):
				scrap_n += 1
		teams.append({
			"team": int(team),
			"x": cx,
			"z": cz,
			"geysers": geyser_n,
			"scrap": scrap_n,
			"spawns": members.size(),
		})

	return {
		"circles": circles,
		"pairs": pairs,
		"teams": teams,
		"mean_pair_m": mean_pair_m,
	}


static func is_geyser_record(rec: Dictionary) -> bool:
	return BzCheckFormats.GEYSER_CLASSES.has(_prjid(rec))


static func is_scrap_record(rec: Dictionary) -> bool:
	return BzOdf.is_scrap_prjid(_prjid(rec))


static func is_spawn_record(rec: Dictionary) -> bool:
	return _prjid(rec) == BzCheckFormats.SPAWN_CLASS


static func _circle_of(rec: Dictionary, kind: String, radius: float) -> Dictionary:
	var p := _xz(rec)
	return {
		"id": _id(rec),
		"kind": kind,
		"x": p.x,
		"z": p.y,
		"radius": radius,
	}


static func _within_cluster(rec: Dictionary, members: Array) -> bool:
	var p := _xz(rec)
	for s in members:
		if p.distance_to(_xz(s)) <= ECONOMY_RADIUS_M:
			return true
	return false


static func _prjid(rec: Dictionary) -> String:
	return str(rec.get("prjid", "")).to_lower()


static func _id(rec: Dictionary) -> String:
	return str(rec.get("id", ""))


static func _xz(rec: Dictionary) -> Vector2:
	return Vector2(float(rec.get("x", 0.0)), float(rec.get("z", 0.0)))


func _recompute() -> void:
	_clear_geometry()
	if not _active or not MapState.has_session:
		_snapshot = {}
		return
	var recs: Variant = MapState.objects.get(MapState.active_variant, [])
	var records: Array = recs if typeof(recs) == TYPE_ARRAY else []
	_snapshot = compute(records)
	_build_geometry(_snapshot)


func _build_geometry(snap: Dictionary) -> void:
	var field: HeightField = MapState.field
	var circles: Array = snap.get("circles", [])
	if not circles.is_empty():
		_build_discs(circles, field)
	var pairs: Array = snap.get("pairs", [])
	if not pairs.is_empty():
		_build_pairs(pairs, field)
	var teams: Array = snap.get("teams", [])
	for team in teams:
		if typeof(team) != TYPE_DICTIONARY:
			continue
		_build_team_label(team, field)


func _build_discs(circles: Array, field: HeightField) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.2
	disc.radial_segments = 24
	disc.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = disc
	mm.instance_count = circles.size()
	for i in circles.size():
		var c: Dictionary = circles[i]
		var x := float(c.get("x", 0.0))
		var z := float(c.get("z", 0.0))
		var r := float(c.get("radius", SCRAP_RADIUS_M))
		var y := _sample_h(field, x, z) + LIFT_M
		var xf := Transform3D()
		xf.origin = Vector3(x, y, z)
		xf.basis = Basis.from_scale(Vector3(r, 1.0, r))
		mm.set_instance_transform(i, xf)
		var kind := str(c.get("kind", ""))
		if kind == "geyser":
			mm.set_instance_color(i, Color(0.95, 0.42, 0.12, 0.40))
		else:
			mm.set_instance_color(i, Color(0.90, 0.78, 0.18, 0.36))
	var inst := MultiMeshInstance3D.new()
	inst.name = "EconomyDiscs"
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.material_override = _disc_material()
	add_child(inst)


func _build_pairs(pairs: Array, field: HeightField) -> void:
	var mesh := ImmediateMesh.new()
	var mat := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for pair in pairs:
		if typeof(pair) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = pair
		var ax := float(p.get("ax", 0.0))
		var az := float(p.get("az", 0.0))
		var bx := float(p.get("bx", 0.0))
		var bz := float(p.get("bz", 0.0))
		var a := Vector3(ax, _sample_h(field, ax, az) + LIFT_M, az)
		var b := Vector3(bx, _sample_h(field, bx, bz) + LIFT_M, bz)
		var col := Color(0.22, 0.86, 0.32, 0.92) if bool(p.get("fair", false)) else Color(0.95, 0.22, 0.18, 0.92)
		_ribbon(mesh, a, b, col, LINE_WIDTH_M)
	mesh.surface_end()
	var inst := MeshInstance3D.new()
	inst.name = "SpawnPairs"
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func _build_team_label(team: Dictionary, field: HeightField) -> void:
	var x := float(team.get("x", 0.0))
	var z := float(team.get("z", 0.0))
	var n := int(team.get("team", 0))
	var tag := Label3D.new()
	tag.name = "Team%d" % n
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# The viewport is mirrored (FlyCamera.VIEW_MIRROR) so the 3D view
	# matches the game. Text is the one thing that must not come along.
	tag.scale.x = -1.0
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.font_size = 48
	tag.pixel_size = 0.0016
	tag.outline_size = 12
	tag.outline_modulate = Color(0.02, 0.02, 0.04, 0.92)
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.render_priority = 16
	tag.text = "Team %d\n%d geyser%s\n%d scrap" % [
		n,
		int(team.get("geysers", 0)),
		"" if int(team.get("geysers", 0)) == 1 else "s",
		int(team.get("scrap", 0)),
	]
	var col := ObjectMarkers.team_color(n)
	col.a = 1.0
	tag.modulate = col
	tag.position = Vector3(x, _sample_h(field, x, z) + LABEL_LIFT_M, z)
	add_child(tag)


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
	mat.no_depth_test = false
	return mat


func _sample_h(field: HeightField, x: float, z: float) -> float:
	if field != null and field.grid_x > 1 and field.grid_z > 1:
		return field.height_at(x, z)
	return 0.0


func _clear_geometry() -> void:
	var doomed: Array = []
	for child in get_children():
		if child == _timer:
			continue
		doomed.append(child)
	for child in doomed:
		remove_child(child)
		(child as Node).free()


func _ensure_timer() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.name = "Debounce"
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE_S
	_timer.timeout.connect(_recompute)
	add_child(_timer)


func _connect_signals() -> void:
	if not MapState.objects_mutated.is_connected(_on_objects_mutated):
		MapState.objects_mutated.connect(_on_objects_mutated)
	if not MapState.session_changed.is_connected(_on_session_changed):
		MapState.session_changed.connect(_on_session_changed)


func _disconnect_signals() -> void:
	if MapState.objects_mutated.is_connected(_on_objects_mutated):
		MapState.objects_mutated.disconnect(_on_objects_mutated)
	if MapState.session_changed.is_connected(_on_session_changed):
		MapState.session_changed.disconnect(_on_session_changed)


func _on_objects_mutated() -> void:
	schedule_recompute()


func _on_session_changed() -> void:
	if not _active:
		return
	if not MapState.has_session:
		_clear_geometry()
		_snapshot = {}
		return
	_recompute()
