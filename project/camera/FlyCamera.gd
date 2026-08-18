extends Camera3D
class_name FlyCamera
## RMB look, wheel zoom (Ctrl+wheel too), Shift+wheel truck, Alt+wheel orbit,
## Ctrl+move orbit, Shift+move pan, MMB orbit, WASD fly. Map mode is north-up.

signal speed_changed(mps: float)
signal map_mode_changed(on: bool)

const MAP_CAM_Y := 2500.0
const MAP_SIZE_MIN := 40.0
const MAP_SIZE_MAX := 20000.0
const ZOOM_FACTOR := 0.85
const ORBIT_WHEEL_STEP_PX := 60.0
const MAP_WHEEL_PAN_PX := 60.0
const HOVER_LIFT_M := 40.0
const HOVER_BACK_M := 40.0
## Godot identity looks −Z (south). Yaw π faces +Z (north).
const NORTH_YAW := PI
const COMPASS_HUB_RATIO := 0.28

var base_speed: float = 80.0
var looking: bool = false
var orbiting: bool = false
var panning: bool = false
## Shift+RMB (or Shift+MMB) drag: grab-pan in 3D.
var pan_dragging: bool = false
var pivot: Vector3 = Vector3.ZERO
var map_mode: bool = false
var _look_sens: float = 0.003
var _saved_3d: Dictionary = {}
var _map_size: float = 800.0


func handle_event(event: InputEvent) -> void:
	if map_mode:
		_handle_map_event(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# Modifier+RMB drags: Shift pans the view, Ctrl/Alt orbits the
			# pivot, plain RMB free-looks. RMB is camera-only, so single
			# modifiers stay free of tool click bindings.
			looking = false
			orbiting = false
			pan_dragging = false
			if mb.pressed and mb.shift_pressed:
				pan_dragging = true
			elif mb.pressed and (mb.ctrl_pressed or mb.alt_pressed):
				orbiting = true
			else:
				looking = mb.pressed
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED
				if looking or orbiting
				else Input.MOUSE_MODE_VISIBLE
			)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = mb.pressed
			looking = false
			pan_dragging = false
			if mb.pressed and mb.shift_pressed:
				orbiting = false
				pan_dragging = true
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if orbiting else Input.MOUSE_MODE_VISIBLE
			)
		elif mb.pressed and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP
			or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			# GIMP-style modifiers: Shift+wheel trucks left/right,
			# Alt+wheel orbits the pivot, plain and Ctrl+wheel zoom.
			if mb.shift_pressed:
				_truck(dir)
			elif mb.alt_pressed:
				_orbit_step(dir)
			else:
				_dolly(dir)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if looking:
			rotate_y(look_yaw_delta(mm.relative.x, _look_sens))
			rotation.x = clampf(
				rotation.x + look_pitch_delta(mm.relative.y, Settings.invert_look, _look_sens),
				-1.35,
				1.35,
			)
		elif orbiting:
			_orbit(mm.relative)
		elif pan_dragging:
			_pan_ground(mm.relative)
		elif mm.button_mask == 0 and _fly_keys_down():
			# Shift/Ctrl also modulate WASD speed; never hijack mid-flight.
			pass
		elif mm.button_mask == 0 and mm.ctrl_pressed:
			# Buttonless Ctrl+move orbits the pivot, deliberately slow
			# (~1/16 of drag-orbit speed).
			_orbit(mm.relative * 0.06)
		elif mm.button_mask == 0 and mm.alt_pressed:
			# Buttonless Alt+move pans the camera tripod-style.
			rotate_y(look_yaw_delta(mm.relative.x, _look_sens))
			rotation.x = clampf(
				rotation.x + look_pitch_delta(mm.relative.y, Settings.invert_look, _look_sens),
				-1.35,
				1.35,
			)
		elif mm.button_mask == 0 and mm.shift_pressed:
			_pan_ground(mm.relative)


func _handle_map_event(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				begin_pan()
			else:
				end_pan()
		elif mb.pressed and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP
			or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.shift_pressed:
				pan_by_pixels(Vector2(dir * MAP_WHEEL_PAN_PX, 0.0))
			else:
				zoom_to_cursor(dir)
	elif event is InputEventMouseMotion:
		var mmm := event as InputEventMouseMotion
		if panning:
			pan_by_pixels(mmm.relative)
		elif mmm.button_mask == 0 and mmm.shift_pressed:
			pan_by_pixels(mmm.relative)


func begin_pan() -> void:
	if not map_mode:
		return
	panning = true
	looking = false
	orbiting = false
	_end_pointer_capture()


func end_pan() -> void:
	panning = false
	_end_pointer_capture()


static func _fly_keys_down() -> bool:
	return (
		Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A)
		or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
		or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E)
	)


func _end_pointer_capture() -> void:
	looking = false
	orbiting = false
	pan_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _dolly(sign: float) -> void:
	var step := maxf(8.0, base_speed * Settings.coerce_camera_speed(Settings.camera_speed_mul) * 0.35) * sign
	# Zoom along the ray under the cursor, so the point you point at is
	# what you approach (and what stays put on screen), not screen center.
	var dir := -global_transform.basis.z
	if is_inside_tree():
		dir = project_ray_normal(get_viewport().get_mouse_position())
	global_position -= dir * step


## Shift+wheel: slide left/right along the ground plane.
func _truck(sign: float) -> void:
	var step := maxf(8.0, base_speed * Settings.coerce_camera_speed(Settings.camera_speed_mul) * 0.35) * sign
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	global_position += right * step


## Alt+wheel: step the orbit around the pivot.
func _orbit_step(sign: float) -> void:
	_orbit(Vector2(sign * ORBIT_WHEEL_STEP_PX, 0.0))


## Shift+move: grab-pan the world, ground-parallel, scaled by height.
func _pan_ground(rel: Vector2) -> void:
	var scale := maxf(global_position.y, 40.0) * 0.0016
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	global_position += (-right * rel.x + fwd * rel.y) * scale


func _orbit(rel: Vector2) -> void:
	var offset := global_position - pivot
	var dist := maxf(offset.length(), 8.0)
	var yaw := -rel.x * _look_sens
	var pitch := -rel.y * _look_sens
	offset = offset.rotated(Vector3.UP, yaw)
	var right := Vector3.UP.cross(offset).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var pitched := offset.rotated(right, pitch)
	if pitched.normalized().dot(Vector3.UP) > 0.95 or pitched.normalized().dot(Vector3.UP) < -0.95:
		pitched = offset
	global_position = pivot + pitched.normalized() * dist
	look_at(pivot, Vector3.UP)


func _process(delta: float) -> void:
	if _text_focused():
		return
	if map_mode:
		_process_map_pan(delta)
		return
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		wish += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		wish -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		wish += global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		wish += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		wish -= Vector3.UP
	if wish.length_squared() < 0.0001:
		return
	var mul := speed_multiplier(
		Input.is_key_pressed(KEY_SHIFT),
		Input.is_key_pressed(KEY_CTRL),
		Settings.coerce_camera_speed(Settings.camera_speed_mul),
	)
	global_position += wish.normalized() * base_speed * mul * delta
	if Settings.walk_mode and MapState.has_session and MapState.field.grid_x > 1:
		var ground := MapState.field.height_at(global_position.x, global_position.z)
		global_position.y = maxf(global_position.y, ground + 4.0)


func _process_map_pan(delta: float) -> void:
	var wish := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		wish.y += 1.0
	if Input.is_key_pressed(KEY_S):
		wish.y -= 1.0
	if Input.is_key_pressed(KEY_A):
		wish.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		wish.x += 1.0
	if wish.length_squared() < 0.0001:
		return
	var mul := speed_multiplier(
		Input.is_key_pressed(KEY_SHIFT),
		Input.is_key_pressed(KEY_CTRL),
		Settings.coerce_camera_speed(Settings.camera_speed_mul),
	)
	var step := wish.normalized() * base_speed * mul * delta
	global_position.x += step.x
	global_position.z += step.y
	pivot.x = global_position.x
	pivot.z = global_position.z
	_apply_map_orientation()


func frame_map(width_m: float, depth_m: float, height_m: float) -> void:
	base_speed = maxf(40.0, maxf(width_m, depth_m) * 0.08)
	if map_mode:
		frame_map_ortho(width_m, depth_m)
		return
	pivot = Vector3(width_m * 0.5, height_m, depth_m * 0.5)
	global_position = Vector3(width_m * 0.5, height_m + maxf(120.0, depth_m * 0.22), depth_m * -0.02)
	look_at(pivot, Vector3.UP)
	speed_changed.emit(base_speed)


func frame_map_ortho(width_m: float, depth_m: float) -> void:
	var aspect := 16.0 / 9.0
	if is_inside_tree():
		var r := get_viewport().get_visible_rect().size
		if r.y > 1.0:
			aspect = r.x / r.y
	size = ortho_frame_size(width_m, depth_m, aspect)
	_map_size = size
	global_position = Vector3(width_m * 0.5, MAP_CAM_Y, depth_m * 0.5)
	pivot = Vector3(width_m * 0.5, 0.0, depth_m * 0.5)
	_apply_map_orientation()
	speed_changed.emit(base_speed)


func top_down(width_m: float, depth_m: float) -> void:
	pivot = Vector3(width_m * 0.5, 0.0, depth_m * 0.5)
	global_position = Vector3(width_m * 0.5, maxf(width_m, depth_m) * 0.95, depth_m * 0.5)
	look_at(pivot, Vector3.FORWARD)
	speed_changed.emit(base_speed)


func set_map_mode(on: bool) -> void:
	if map_mode == on:
		return
	if on:
		_saved_3d = _pose_dict()
		map_mode = true
		projection = PROJECTION_ORTHOGONAL
		var focus := Vector2(pivot.x, pivot.z)
		_map_size = clampf(maxf(global_position.y * 1.15, 80.0), MAP_SIZE_MIN, MAP_SIZE_MAX)
		size = _map_size
		global_position = Vector3(focus.x, MAP_CAM_Y, focus.y)
		pivot = Vector3(focus.x, 0.0, focus.y)
		_apply_map_orientation()
		panning = false
		_end_pointer_capture()
	else:
		map_mode = false
		panning = false
		_end_pointer_capture()
		_restore_3d_pose()
	map_mode_changed.emit(map_mode)


func hover_point(world: Vector3) -> void:
	pivot = world
	if map_mode:
		global_position.x = world.x
		global_position.z = world.z
		global_position.y = MAP_CAM_Y
		_apply_map_orientation()
		return
	global_position = hover_perspective_position(world)
	look_at(world, Vector3.UP)


func snap_yaw_north() -> void:
	if map_mode:
		_apply_map_orientation()
		return
	rotation.y = NORTH_YAW


func zoom_to_cursor(wheel_sign: float) -> void:
	if not map_mode:
		_dolly(wheel_sign)
		return
	var mouse := Vector2.ZERO
	if is_inside_tree():
		mouse = get_viewport().get_mouse_position()
	var old_size := size
	var new_size := ortho_zoom_size(old_size, wheel_sign)
	var before := _ground_xz_at_screen(mouse)
	size = new_size
	_map_size = new_size
	var after := _ground_xz_at_screen(mouse)
	global_position.x += before.x - after.x
	global_position.z += before.y - after.y
	pivot.x = global_position.x
	pivot.z = global_position.z
	_apply_map_orientation()


func pan_by_pixels(rel: Vector2) -> void:
	if not map_mode:
		return
	var height := 1.0
	if is_inside_tree():
		height = get_viewport().get_visible_rect().size.y
	var d := ortho_pan_delta(rel, size, height)
	global_position.x += d.x
	global_position.z += d.y
	pivot.x = global_position.x
	pivot.z = global_position.z
	_apply_map_orientation()


func _apply_map_orientation() -> void:
	var origin := Vector3(global_position.x, global_position.y, global_position.z)
	var xf := Transform3D(map_mode_basis(), origin)
	global_transform = xf


func _ground_xz_at_screen(screen: Vector2) -> Vector2:
	if not is_inside_tree():
		return Vector2(global_position.x, global_position.z)
	var origin := project_ray_origin(screen)
	var dir := project_ray_normal(screen)
	if absf(dir.y) < 0.0000001:
		return Vector2(origin.x, origin.z)
	var t := (0.0 - origin.y) / dir.y
	var p := origin + dir * t
	return Vector2(p.x, p.z)


func _pose_dict() -> Dictionary:
	var pos := global_position if is_inside_tree() else position
	var d := make_bookmark(pos, rotation, pivot)
	d["map_mode"] = map_mode
	d["size"] = size
	d["fov"] = fov
	d["projection"] = projection
	return d


func _restore_3d_pose() -> void:
	if _saved_3d.is_empty():
		projection = PROJECTION_PERSPECTIVE
		return
	projection = int(_saved_3d.get("projection", PROJECTION_PERSPECTIVE))
	if _saved_3d.has("fov"):
		fov = float(_saved_3d["fov"])
	if _saved_3d.has("size"):
		size = float(_saved_3d["size"])
	_apply_pose_transform(_saved_3d)


func _apply_pose_transform(d: Dictionary) -> void:
	# Rebuild the basis from scratch: map mode uses a mirrored
	# (left-handed) basis, and assigning `rotation` alone would keep that
	# mirror in the recomposed transform, garbling the restored 3D view.
	transform.basis = Basis.from_euler(bookmark_rotation(d))
	var pos := bookmark_position(d)
	if is_inside_tree():
		global_position = pos
	else:
		position = pos
	pivot = bookmark_pivot(d)


static func map_mode_basis() -> Basis:
	## Screen-right = +x (east), screen-up = +z (north), look = −y.
	## Left-handed so both north-up and east-right hold when looking down.
	return Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0))


static func hover_perspective_position(world: Vector3) -> Vector3:
	return Vector3(world.x, world.y + HOVER_LIFT_M, world.z - HOVER_BACK_M)


static func north_yaw() -> float:
	return NORTH_YAW


static func look_dir_from_basis_z(basis_z: Vector3) -> Vector3:
	return Vector3(-basis_z.x, 0.0, -basis_z.z)


static func rose_radians_from_look(look: Vector3) -> float:
	## 0 when facing +z (north); Godot 2D-positive (clockwise) so N stays screen-up.
	if look.x * look.x + look.z * look.z < 0.0000001:
		return 0.0
	return -atan2(look.x, look.z)


static func compass_hit(local: Vector2, widget_size: Vector2, rose_radians: float) -> String:
	if widget_size.x < 2.0 or widget_size.y < 2.0:
		return ""
	var center := widget_size * 0.5
	var delta := local - center
	var radius := minf(widget_size.x, widget_size.y) * 0.5
	var dist := delta.length()
	if dist > radius:
		return ""
	if dist <= radius * COMPASS_HUB_RATIO:
		return "center"
	var unrot := delta.rotated(-rose_radians)
	if absf(unrot.y) >= absf(unrot.x):
		return "n" if unrot.y < 0.0 else "s"
	return "e" if unrot.x >= 0.0 else "w"


static func ortho_zoom_size(current_size: float, wheel_sign: float) -> float:
	var factor := ZOOM_FACTOR if wheel_sign < 0.0 else 1.0 / ZOOM_FACTOR
	return clampf(current_size * factor, MAP_SIZE_MIN, MAP_SIZE_MAX)


static func zoom_keep_point(old_size: float, new_size: float, cam_xz: Vector2, point_xz: Vector2) -> Vector2:
	if old_size <= 0.0001:
		return cam_xz
	return point_xz - (point_xz - cam_xz) * (new_size / old_size)


static func ortho_pan_delta(mouse_delta: Vector2, ortho_size: float, viewport_height: float) -> Vector2:
	## Content follows the cursor. North-up, east-right: +x screen = +x world.
	if viewport_height <= 0.0001:
		return Vector2.ZERO
	var wpp := ortho_size / viewport_height
	return Vector2(-mouse_delta.x * wpp, mouse_delta.y * wpp)


static func ortho_frame_size(width_m: float, depth_m: float, aspect: float) -> float:
	var pad := 1.08
	var need_v := depth_m * pad
	var need_from_h := (width_m * pad) / maxf(aspect, 0.05)
	return clampf(maxf(need_v, need_from_h), MAP_SIZE_MIN, MAP_SIZE_MAX)


static func look_yaw_delta(rel_x: float, sens: float) -> float:
	return -rel_x * sens


static func look_pitch_delta(rel_y: float, invert: bool, sens: float) -> float:
	var sign := 1.0 if invert else -1.0
	return sign * rel_y * sens


static func speed_multiplier(sprint: bool, slow: bool, settings_mul: float) -> float:
	var m := settings_mul
	if sprint:
		m *= 4.0
	elif slow:
		m *= 0.25
	return m


static func parse_goto(text: String) -> Vector2:
	## "x, z" (comma or whitespace). First two floats. INF on failure.
	var s := text.strip_edges()
	if s.is_empty():
		return Vector2.INF
	s = s.replace(",", " ")
	s = s.replace(";", " ")
	var parts := s.split(" ", false)
	if parts.size() < 2:
		return Vector2.INF
	if not str(parts[0]).is_valid_float() or not str(parts[1]).is_valid_float():
		return Vector2.INF
	return Vector2(str(parts[0]).to_float(), str(parts[1]).to_float())


static func make_bookmark(pos: Vector3, rot: Vector3, pivot_pt: Vector3) -> Dictionary:
	return {
		"position": [pos.x, pos.y, pos.z],
		"rotation": [rot.x, rot.y, rot.z],
		"pivot": [pivot_pt.x, pivot_pt.y, pivot_pt.z],
	}


static func bookmark_position(d: Dictionary) -> Vector3:
	return _vec3_from(d.get("position", []), Vector3.ZERO)


static func bookmark_rotation(d: Dictionary) -> Vector3:
	return _vec3_from(d.get("rotation", []), Vector3.ZERO)


static func bookmark_pivot(d: Dictionary) -> Vector3:
	return _vec3_from(d.get("pivot", []), Vector3.ZERO)


static func _vec3_from(v: Variant, fallback: Vector3) -> Vector3:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() < 3:
		return fallback
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func capture_bookmark() -> Dictionary:
	return _pose_dict()


func apply_bookmark(d: Dictionary) -> void:
	if d.is_empty():
		return
	var want_map := bool(d.get("map_mode", false))
	var was_map := map_mode
	if want_map:
		if not map_mode:
			_saved_3d = _pose_dict()
		map_mode = true
		projection = PROJECTION_ORTHOGONAL
		_apply_pose_transform(d)
		if d.has("size"):
			size = maxf(float(d["size"]), MAP_SIZE_MIN)
			_map_size = size
		global_position.y = MAP_CAM_Y
		_apply_map_orientation()
	else:
		map_mode = false
		panning = false
		projection = int(d.get("projection", PROJECTION_PERSPECTIVE))
		if d.has("fov"):
			fov = float(d["fov"])
		_apply_pose_transform(d)
		if was_map:
			_end_pointer_capture()
	if was_map != map_mode:
		map_mode_changed.emit(map_mode)


func _text_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox or focus is RichTextLabel
