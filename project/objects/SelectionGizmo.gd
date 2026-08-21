extends Node3D
class_name SelectionGizmo
## Select-tool move / rotate gizmo at the selection pivot.

const HANDLE_NONE := ""
const HANDLE_X := "x"
const HANDLE_Z := "z"
const HANDLE_XZ := "xz"
const HANDLE_YAW := "yaw"

const SNAP_GRID_STEPS: Array[float] = [0.0, 1.0, 5.0, 10.0, 20.0]
const SNAP_ANGLE_STEPS: Array[float] = [0.0, 15.0, 45.0, 90.0]

const BASE_SIZE := 20.0
const ARROW_LEN := 16.0
const ARROW_SHAFT_R := 0.38
const ARROW_HEAD_R := 1.35
const ARROW_HEAD_H := 3.1
const CENTER_EXTENT := 2.4
const CENTER_THICK := 0.55
const RING_RADIUS := 14.0
const RING_TUBE := 0.42
const PICK_PAD := 1.15

const COL_X := Color(0.92, 0.20, 0.16)
const COL_Z := Color(0.20, 0.46, 0.96)
const COL_XZ := Color(0.94, 0.90, 0.28)
const COL_YAW := Color(0.96, 0.78, 0.18)

var _hover: String = HANDLE_NONE
var _active: String = HANDLE_NONE
var _mats: Dictionary = {}


func _ready() -> void:
	_build()
	visible = false


func hover_handle() -> String:
	return _hover


func set_hover_handle(handle: String) -> void:
	if _hover == handle:
		return
	_hover = handle
	_refresh_mats()


func set_active_handle(handle: String) -> void:
	if _active == handle:
		return
	_active = handle
	_refresh_mats()


func clear_handles() -> void:
	if _hover.is_empty() and _active.is_empty():
		return
	_hover = HANDLE_NONE
	_active = HANDLE_NONE
	_refresh_mats()


func hide_gizmo() -> void:
	visible = false
	clear_handles()


func sync_at(pivot: Vector3, camera: Camera3D, highlight: String = HANDLE_NONE) -> void:
	visible = true
	global_position = pivot
	if camera == null:
		scale = Vector3.ONE
	else:
		var dist := camera.global_position.distance_to(pivot)
		var world := clampf(dist * 0.04, 12.0, 90.0)
		scale = Vector3.ONE * (world / BASE_SIZE)
	if highlight != _hover and _active.is_empty():
		_hover = highlight
		_refresh_mats()
	elif highlight != HANDLE_NONE and highlight != _hover:
		_hover = highlight
		_refresh_mats()


func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var empty := {"handle": HANDLE_NONE, "t": -1.0, "point": Vector3.ZERO}
	if not visible or direction.length_squared() < 0.0000001:
		return empty
	var dir := direction.normalized()
	var best := HANDLE_NONE
	var best_t := 1.0e9
	var best_pt := Vector3.ZERO
	var xf := global_transform
	var s := maxf(absf(scale.x), 0.001)
	var hits: Array = [
		{"handle": HANDLE_XZ, "t": _pick_center(origin, dir, xf, s)},
		{"handle": HANDLE_X, "t": _pick_axis(origin, dir, xf, s, Vector3.RIGHT)},
		{"handle": HANDLE_Z, "t": _pick_axis(origin, dir, xf, s, Vector3.BACK)},
		{"handle": HANDLE_YAW, "t": _pick_ring(origin, dir, xf.origin, s)},
	]
	for rec in hits:
		var t := float(rec.get("t", -1.0))
		if t < 0.0:
			continue
		# Near-ties keep the earlier handle (center, then axes, then ring).
		if best != HANDLE_NONE and t >= best_t - 0.05:
			continue
		best_t = t
		best = str(rec.get("handle", HANDLE_NONE))
		best_pt = origin + dir * t
	if best.is_empty():
		return empty
	return {"handle": best, "t": best_t, "point": best_pt}


static func snap_scalar(v: float, step: float) -> float:
	if step <= 0.0 or not is_finite(v) or not is_finite(step):
		return v
	return snappedf(v, step)


static func snap_xz(x: float, z: float, grid: float) -> Vector2:
	return Vector2(snap_scalar(x, grid), snap_scalar(z, grid))


static func snap_angle_deg(deg: float, step: float) -> float:
	if step <= 0.0 or not is_finite(deg):
		return EditActions.wrap_yaw_deg(deg)
	return EditActions.wrap_yaw_deg(snap_scalar(deg, step))


static func coerce_snap_grid(raw: Variant) -> float:
	return _coerce_choice(raw, SNAP_GRID_STEPS)


static func coerce_snap_angle(raw: Variant) -> float:
	return _coerce_choice(raw, SNAP_ANGLE_STEPS)


static func selection_pivot(records: Array) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for raw in records:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		acc += Vector3(
			float(rec.get("x", 0.0)),
			float(rec.get("y", 0.0)),
			float(rec.get("z", 0.0)),
		)
		n += 1
	if n == 0:
		return Vector3.ZERO
	return acc / float(n)


static func ray_ground(origin: Vector3, direction: Vector3, plane_y: float) -> Vector3:
	if direction.length_squared() < 0.0000001:
		return Vector3(NAN, NAN, NAN)
	var dir := direction.normalized()
	if absf(dir.y) < 0.0000001:
		return Vector3(NAN, NAN, NAN)
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return Vector3(NAN, NAN, NAN)
	return origin + dir * t


static func move_delta(
	handle: String,
	pivot: Vector3,
	start_hit: Vector3,
	now_hit: Vector3,
	snap_grid: float
) -> Vector3:
	if not start_hit.is_finite() or not now_hit.is_finite():
		return Vector3.ZERO
	var raw := now_hit - start_hit
	raw.y = 0.0
	match handle:
		HANDLE_X:
			raw.z = 0.0
		HANDLE_Z:
			raw.x = 0.0
		HANDLE_XZ:
			pass
		_:
			return Vector3.ZERO
	var dest := Vector3(pivot.x + raw.x, pivot.y, pivot.z + raw.z)
	if snap_grid > 0.0:
		dest.x = snap_scalar(dest.x, snap_grid)
		dest.z = snap_scalar(dest.z, snap_grid)
		if handle == HANDLE_X:
			dest.z = pivot.z
		elif handle == HANDLE_Z:
			dest.x = pivot.x
	return Vector3(dest.x - pivot.x, 0.0, dest.z - pivot.z)


static func yaw_delta_deg(
	pivot: Vector3, start_hit: Vector3, now_hit: Vector3, snap_angle: float
) -> float:
	if not start_hit.is_finite() or not now_hit.is_finite():
		return 0.0
	var a0 := atan2(start_hit.x - pivot.x, start_hit.z - pivot.z)
	var a1 := atan2(now_hit.x - pivot.x, now_hit.z - pivot.z)
	var delta := rad_to_deg(wrapf(a1 - a0, -PI, PI))
	if snap_angle > 0.0:
		delta = snap_scalar(delta, snap_angle)
	return EditActions.wrap_yaw_deg(delta)


static func rotate_point_xz(x: float, z: float, px: float, pz: float, yaw_deg: float) -> Vector2:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var p := b * Vector3(x - px, 0.0, z - pz)
	return Vector2(px + p.x, pz + p.z)


static func transformed_xz_yaw(
	x: float, z: float, yaw_deg: float, dx: float, dz: float, delta_yaw: float, pivot: Vector3
) -> Dictionary:
	var nx := x
	var nz := z
	var nyaw := yaw_deg
	if not is_zero_approx(delta_yaw):
		var p := rotate_point_xz(x, z, pivot.x, pivot.z, delta_yaw)
		nx = p.x
		nz = p.y
		nyaw = EditActions.wrap_yaw_deg(yaw_deg + delta_yaw)
	return {"x": nx + dx, "z": nz + dz, "yaw_deg": nyaw}


static func preview_poses(
	records: Array, dx: float, dz: float, delta_yaw: float, pivot: Vector3, field: HeightField
) -> Dictionary:
	var out := {}
	for raw in records:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		var id := str(rec.get("id", ""))
		if id.is_empty():
			continue
		var pose := transformed_xz_yaw(
			float(rec.get("x", 0.0)),
			float(rec.get("z", 0.0)),
			float(rec.get("yaw_deg", 0.0)),
			dx,
			dz,
			delta_yaw,
			pivot,
		)
		var y := float(rec.get("y", 0.0))
		if not bool(rec.get("pinned_y", false)) and field != null:
			y = field.height_at(float(pose["x"]), float(pose["z"]))
		out[id] = {
			"x": float(pose["x"]),
			"y": y,
			"z": float(pose["z"]),
			"yaw_deg": float(pose["yaw_deg"]),
		}
	return out


static func label_text_for(rec: Dictionary) -> String:
	var prjid := str(rec.get("prjid", "")).strip_edges()
	var label := str(rec.get("label", "")).strip_edges()
	if prjid.is_empty():
		return label
	if label.is_empty() or label == prjid:
		return prjid
	return "%s  %s" % [prjid, label]


static func pick_nearest_label_ids(candidates: Array, range_m: float, cap: int) -> Array[String]:
	var ranked: Array = []
	for raw in candidates:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		var dist := float(rec.get("dist", INF))
		if not is_finite(dist) or dist > range_m:
			continue
		var id := str(rec.get("id", ""))
		if id.is_empty():
			continue
		ranked.append({"id": id, "dist": dist})
	ranked.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	var out: Array[String] = []
	var n := mini(maxi(cap, 0), ranked.size())
	for i in n:
		out.append(str(ranked[i]["id"]))
	return out


static func _coerce_choice(raw: Variant, allowed: Array[float]) -> float:
	var v := 0.0
	match typeof(raw):
		TYPE_FLOAT, TYPE_INT:
			v = float(raw)
		TYPE_STRING:
			var s := str(raw).strip_edges().to_lower()
			if s == "off" or s.is_empty():
				return 0.0
			if s.ends_with("m") or s.ends_with("°"):
				s = s.substr(0, s.length() - 1).strip_edges()
			if not s.is_valid_float():
				return 0.0
			v = float(s)
		_:
			return 0.0
	if not is_finite(v) or v < 0.0:
		return 0.0
	var best := 0.0
	var best_d := INF
	for c in allowed:
		var d := absf(v - c)
		if d < best_d:
			best_d = d
			best = c
	return best


func _build() -> void:
	_add_arrow(HANDLE_X, COL_X, Vector3(0.0, 0.0, -PI * 0.5))
	_add_arrow(HANDLE_Z, COL_Z, Vector3(PI * 0.5, 0.0, 0.0))
	var center := MeshInstance3D.new()
	center.name = "HandleXZ"
	var box := BoxMesh.new()
	box.size = Vector3(CENTER_EXTENT * 2.0, CENTER_THICK, CENTER_EXTENT * 2.0)
	center.mesh = box
	center.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	center.material_override = _make_mat(COL_XZ)
	_mats[HANDLE_XZ] = center.material_override
	add_child(center)
	var ring := MeshInstance3D.new()
	ring.name = "HandleYaw"
	ring.mesh = _torus_mesh(RING_RADIUS, RING_TUBE, 40, 8)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = _make_mat(COL_YAW)
	_mats[HANDLE_YAW] = ring.material_override
	add_child(ring)


func _add_arrow(handle: String, col: Color, euler: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Handle%s" % handle.to_upper()
	root.rotation = euler
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var cyl := CylinderMesh.new()
	cyl.top_radius = ARROW_SHAFT_R
	cyl.bottom_radius = ARROW_SHAFT_R
	cyl.height = ARROW_LEN - ARROW_HEAD_H
	shaft.mesh = cyl
	shaft.position = Vector3(0.0, (ARROW_LEN - ARROW_HEAD_H) * 0.5, 0.0)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _make_mat(col)
	shaft.material_override = mat
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = ARROW_HEAD_R
	cone.height = ARROW_HEAD_H
	head.mesh = cone
	head.position = Vector3(0.0, ARROW_LEN - ARROW_HEAD_H * 0.5, 0.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.material_override = mat
	root.add_child(head)
	_mats[handle] = mat
	add_child(root)


func _make_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 12
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.set_meta("base_albedo", col)
	return mat


func _refresh_mats() -> void:
	for key in _mats.keys():
		var mat := _mats[key] as StandardMaterial3D
		if mat == null:
			continue
		var base: Color = mat.get_meta("base_albedo", mat.albedo_color)
		var lit := str(key) == _active or str(key) == _hover
		mat.albedo_color = base.lightened(0.35) if lit else base
		mat.emission_enabled = lit
		mat.emission = base
		mat.emission_energy_multiplier = 1.8 if lit else 1.0


func _pick_center(origin: Vector3, dir: Vector3, xf: Transform3D, s: float) -> float:
	var center := xf * Vector3.ZERO
	var size := Vector3(CENTER_EXTENT * 2.0 + PICK_PAD, 4.2, CENTER_EXTENT * 2.0 + PICK_PAD) * s
	return _ray_aabb(origin, dir, center, size)


func _pick_axis(origin: Vector3, dir: Vector3, xf: Transform3D, s: float, axis: Vector3) -> float:
	# Keep the shaft box outside the center square so a top-down ray at the
	# pivot hits XZ, not the overlapping X/Z AABB.
	var inner := CENTER_EXTENT + PICK_PAD * 0.5
	var outer := ARROW_LEN + PICK_PAD
	var mid_along := (inner + outer) * 0.5
	var along := outer - inner
	var mid := xf * (axis * mid_along)
	var thick := ARROW_HEAD_R * 2.0 + PICK_PAD * 2.0
	var size := Vector3(thick, 2.6, thick) * s
	if absf(axis.x) > 0.5:
		size.x = along * s
	else:
		size.z = along * s
	return _ray_aabb(origin, dir, mid, size)


func _pick_ring(origin: Vector3, dir: Vector3, pivot: Vector3, s: float) -> float:
	var hit := ray_ground(origin, dir, pivot.y)
	if not hit.is_finite():
		return -1.0
	var d := Vector2(hit.x - pivot.x, hit.z - pivot.z).length()
	var r := RING_RADIUS * s
	var tube := (RING_TUBE + 1.6) * s
	if absf(d - r) > tube:
		return -1.0
	return origin.distance_to(hit)


func _torus_mesh(ring_r: float, tube_r: float, rings: int, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		var a0 := TAU * float(i) / float(rings)
		var a1 := TAU * float(i + 1) / float(rings)
		for j in sides:
			var b0 := TAU * float(j) / float(sides)
			var b1 := TAU * float(j + 1) / float(sides)
			var p00 := _torus_pt(ring_r, tube_r, a0, b0)
			var p10 := _torus_pt(ring_r, tube_r, a1, b0)
			var p01 := _torus_pt(ring_r, tube_r, a0, b1)
			var p11 := _torus_pt(ring_r, tube_r, a1, b1)
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
	st.generate_normals()
	return st.commit()


func _torus_pt(ring_r: float, tube_r: float, a: float, b: float) -> Vector3:
	var rr := ring_r + tube_r * cos(b)
	return Vector3(rr * sin(a), tube_r * sin(b), rr * cos(a))


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
