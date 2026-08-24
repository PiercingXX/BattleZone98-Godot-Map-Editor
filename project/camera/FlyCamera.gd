extends Camera3D
class_name FlyCamera
## RMB look, wheel zoom, MMB orbit, WASD fly. Shift/Ctrl/Alt camera verbs
## (pan, orbit, truck, sprint/slow) are fly-tool only. Map mode is north-up.

signal speed_changed(mps: float)
signal map_mode_changed(on: bool)

const MAP_CAM_Y := 2500.0
const MAP_SIZE_MIN := 40.0
const MAP_SIZE_MAX := 20000.0
const ZOOM_FACTOR := 0.85
const ORBIT_WHEEL_STEP_PX := 60.0
## Base rate for buttonless Ctrl+move orbit, before Settings.orbit_sensitivity.
const BUTTONLESS_ORBIT_RATE := 0.03
const MAP_WHEEL_PAN_PX := 60.0
const HOVER_LIFT_M := 40.0
const HOVER_BACK_M := 40.0
## Walk mode's floor: how far above the surface the eye is held.
const WALK_CLEARANCE_M := 4.0
## Godot identity looks −Z (south). Yaw π faces +Z (north).
const NORTH_YAW := PI

## The game draws the world in a frame that is a reflection of Godot's: with
## north (+z) up, east (+x) is on the RIGHT, and no right-handed basis gives a
## camera looking down both of those at once. Map mode has always used a
## mirrored basis for exactly that reason (`map_mode_basis`) — and map mode is
## the view that matches the game. The perspective camera needs the same
## mirror, or the 3D viewport shows the mirror image of what the game draws.
##
## Only the VIEW is mirrored. Positions, the heightfield, every BZN coordinate
## and everything the UI reports stay true to the file. `aim_basis()` is the
## un-mirrored orientation, and it is the one euler / yaw / pitch math works
## in — `rotation` on a mirrored basis decomposes to nonsense.
const VIEW_MIRROR := Basis(
	Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)
)
const COMPASS_HUB_RATIO := 0.28
## Seconds from rest to 1.0× default speed (and back) at accel_mul 1.0.
const ACCEL_TIME_S := 1.0

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
## Prefs / file picker / minimap hover set this false. No look, fly, or capture.
var controls_enabled: bool = true:
	set(v):
		controls_enabled = v
		if not v:
			_halt_motion()
## World-space WASD/QE velocity (m/s). Linear accel/drag toward wish.
var _velocity: Vector3 = Vector3.ZERO
## Map-mode WASD pan velocity, world XZ stored as (x, z).
var _map_velocity: Vector2 = Vector2.ZERO


func handle_event(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if map_mode:
		_handle_map_event(event)
		return
	var mods := is_modifier_camera_allowed()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# Modifier+RMB drags: Shift pans the view, Ctrl/Alt orbits the
			# pivot, plain RMB free-looks. Only the fly tool owns those
			# modifiers so paint/clone/eyedropper can keep Ctrl/Alt/Shift.
			looking = false
			orbiting = false
			pan_dragging = false
			if mb.pressed and mods and mb.shift_pressed:
				pan_dragging = true
			elif mb.pressed and mods and (mb.ctrl_pressed or mb.alt_pressed):
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
			if mb.pressed and mods and mb.shift_pressed:
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
			if mods and mb.shift_pressed:
				_truck(dir)
			elif mods and mb.alt_pressed:
				_orbit_step(dir)
			else:
				_dolly(dir)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if looking:
			_apply_look(mm.relative)
		elif orbiting:
			_orbit(mm.relative)
		elif pan_dragging:
			_pan_ground(mm.relative)
		elif mm.button_mask == 0 and _fly_keys_down():
			# Shift/Ctrl also modulate WASD speed; never hijack mid-flight.
			pass
		elif mods and mm.button_mask == 0 and mm.ctrl_pressed:
			# Buttonless Ctrl+move orbits the pivot, deliberately slow. Ctrl is
			# held for things that are not orbiting, so the default is a
			# hundredth of drag-orbit speed and Preferences can take it lower.
			_orbit(mm.relative * BUTTONLESS_ORBIT_RATE * Settings.coerce_orbit_sensitivity(
				Settings.orbit_sensitivity
			))
		elif mods and mm.button_mask == 0 and mm.alt_pressed:
			# Buttonless Alt+move pans the camera tripod-style.
			_apply_look(mm.relative)
		elif mods and mm.button_mask == 0 and mm.shift_pressed:
			_pan_ground(mm.relative)


## The un-mirrored orientation: what the camera would be if the view were not
## reflected. VIEW_MIRROR is its own inverse, so the same multiply goes both
## ways.
func aim_basis() -> Basis:
	var b: Basis = global_transform.basis if is_inside_tree() else transform.basis
	return b * VIEW_MIRROR


func set_aim_basis(b: Basis) -> void:
	var m := b * VIEW_MIRROR
	if is_inside_tree():
		global_transform.basis = m
	else:
		transform.basis = m


func aim_rotation() -> Vector3:
	return aim_basis().get_euler()


func set_aim_rotation(r: Vector3) -> void:
	set_aim_basis(Basis.from_euler(r))


## `look_at` builds a right-handed basis; the view mirror goes back on after.
func _aim_at(target: Vector3, up: Vector3 = Vector3.UP) -> void:
	look_at(target, up)
	set_aim_basis(global_transform.basis if is_inside_tree() else transform.basis)


## Yaw + pitch from a mouse delta, in the un-mirrored frame so the euler stays
## meaningful. Roll is pinned at zero, same as the old rotate_y + rotation.x.
func _apply_look(rel: Vector2) -> void:
	var e := aim_rotation()
	e.y += look_yaw_delta(rel.x, _look_sens)
	e.x = clampf(
		e.x + look_pitch_delta(rel.y, Settings.invert_look, _look_sens), -1.35, 1.35
	)
	e.z = 0.0
	set_aim_rotation(e)


func is_modifier_camera_allowed() -> bool:
	return controls_enabled and ToolState.tool == "fly"


func _handle_map_event(event: InputEvent) -> void:
	var mods := is_modifier_camera_allowed()
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
			if mods and mb.shift_pressed:
				pan_by_pixels(Vector2(dir * MAP_WHEEL_PAN_PX, 0.0))
			else:
				zoom_to_cursor(dir)
	elif event is InputEventMouseMotion:
		var mmm := event as InputEventMouseMotion
		if panning:
			pan_by_pixels(mmm.relative)
		elif mods and mmm.button_mask == 0 and mmm.shift_pressed:
			pan_by_pixels(mmm.relative)


func begin_pan() -> void:
	if not map_mode or not controls_enabled:
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


func _halt_motion() -> void:
	_end_pointer_capture()
	panning = false
	_velocity = Vector3.ZERO
	_map_velocity = Vector2.ZERO


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
	# Same sign as look_yaw_delta: the mirrored view reverses which way a
	# world yaw appears to turn, so dragging right still swings right.
	var yaw := rel.x * _look_sens
	var pitch := -rel.y * _look_sens
	offset = offset.rotated(Vector3.UP, yaw)
	var right := Vector3.UP.cross(offset).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var pitched := offset.rotated(right, pitch)
	if pitched.normalized().dot(Vector3.UP) > 0.95 or pitched.normalized().dot(Vector3.UP) < -0.95:
		pitched = offset
	global_position = pivot + pitched.normalized() * dist
	_aim_at(pivot)


func _process(delta: float) -> void:
	if not controls_enabled:
		_halt_motion()
		if not map_mode:
			enforce_walk_floor()
		return
	if map_mode:
		if _text_focused():
			_map_velocity = Vector2.ZERO
		else:
			_process_map_pan(delta)
		return
	if _text_focused():
		_velocity = Vector3.ZERO
	else:
		_process_fly(delta)
	# Unconditionally, once a frame — not inside the WASD branch above. The
	# wheel and drag verbs move the camera between frames and never went
	# through that branch, so walk mode let the mouse fly you underground.
	# Sculpting under a parked camera has to push it up too.
	enforce_walk_floor()


func _process_fly(delta: float) -> void:
	if not controls_enabled:
		_velocity = Vector3.ZERO
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
	var mods := is_modifier_camera_allowed()
	var speed_mul := Settings.coerce_camera_speed(Settings.camera_speed_mul)
	var mul := speed_multiplier(
		mods and Input.is_key_pressed(KEY_SHIFT),
		mods and Input.is_key_pressed(KEY_CTRL),
		speed_mul,
	)
	var wish_vel := Vector3.ZERO
	if wish.length_squared() >= 0.0001:
		wish_vel = wish.normalized() * base_speed * mul
	var accel := translation_accel(base_speed, speed_mul, Settings.camera_accel_mul)
	_velocity = integrate_velocity(_velocity, wish_vel, accel, delta)
	if _velocity.length_squared() < 0.0001:
		_velocity = Vector3.ZERO
		return
	global_position += _velocity * delta


## Walk mode's promise: the eye never gets closer than WALK_CLEARANCE_M to the
## surface. Raises only — a camera already well clear is left alone, so framing
## and bookmarks are unaffected. Map mode is exempt: that camera is orthographic
## and parked at MAP_CAM_Y, where height carries no meaning.
func enforce_walk_floor() -> void:
	if map_mode or not Settings.walk_mode:
		return
	if not MapState.has_session or MapState.field == null or MapState.field.grid_x <= 1:
		return
	var ground := MapState.field.height_at(global_position.x, global_position.z)
	global_position.y = maxf(global_position.y, ground + WALK_CLEARANCE_M)


func _process_map_pan(delta: float) -> void:
	if not controls_enabled:
		_map_velocity = Vector2.ZERO
		return
	var wish := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		wish.y += 1.0
	if Input.is_key_pressed(KEY_S):
		wish.y -= 1.0
	if Input.is_key_pressed(KEY_A):
		wish.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		wish.x += 1.0
	var mods := is_modifier_camera_allowed()
	var speed_mul := Settings.coerce_camera_speed(Settings.camera_speed_mul)
	var mul := speed_multiplier(
		mods and Input.is_key_pressed(KEY_SHIFT),
		mods and Input.is_key_pressed(KEY_CTRL),
		speed_mul,
	)
	var wish_vel := Vector2.ZERO
	if wish.length_squared() >= 0.0001:
		wish_vel = wish.normalized() * base_speed * mul
	var accel := translation_accel(base_speed, speed_mul, Settings.camera_accel_mul)
	var next := integrate_velocity(
		Vector3(_map_velocity.x, 0.0, _map_velocity.y),
		Vector3(wish_vel.x, 0.0, wish_vel.y),
		accel,
		delta,
	)
	_map_velocity = Vector2(next.x, next.z)
	if _map_velocity.length_squared() < 0.0001:
		_map_velocity = Vector2.ZERO
		return
	global_position.x += _map_velocity.x * delta
	global_position.z += _map_velocity.y * delta
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
	_aim_at(pivot)
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
	_aim_at(pivot, Vector3.FORWARD)
	speed_changed.emit(base_speed)


func set_map_mode(on: bool) -> void:
	if map_mode == on:
		return
	_velocity = Vector3.ZERO
	_map_velocity = Vector2.ZERO
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
	_aim_at(world)


func snap_yaw_north() -> void:
	if map_mode:
		_apply_map_orientation()
		return
	var e := aim_rotation()
	e.y = NORTH_YAW
	e.z = 0.0
	set_aim_rotation(e)


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
	var d := make_bookmark(pos, aim_rotation(), pivot)
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
	# Bookmarks store the un-mirrored orientation, so the view mirror goes back
	# on here. Assigning `rotation` instead would decompose a mirrored basis
	# into nonsense euler and garble the restored view.
	set_aim_rotation(bookmark_rotation(d))
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
	## 0 when facing +z (north); Godot 2D-positive (clockwise) so N stays
	## screen-up. The mirrored view puts east on the right, so facing east
	## leaves north on the RIGHT of the rose, not the left.
	if look.x * look.x + look.z * look.z < 0.0000001:
		return 0.0
	return atan2(look.x, look.z)


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
	## Positive: the view is mirrored (VIEW_MIRROR), which reverses the
	## apparent turn of a world yaw, so dragging right swings the view right.
	return rel_x * sens


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


## m/s². At accel_mul 1.0, rest → 1.0× (base_speed * camera_speed_mul) in ACCEL_TIME_S.
static func translation_accel(base_speed: float, camera_speed_mul: float, accel_mul: float) -> float:
	return (base_speed * camera_speed_mul) / ACCEL_TIME_S * Settings.coerce_camera_accel(accel_mul)


## Linear approach of vel toward wish_vel at `accel` m/s². Same rate is drag.
static func integrate_velocity(vel: Vector3, wish_vel: Vector3, accel: float, delta: float) -> Vector3:
	var dv := wish_vel - vel
	var max_change := accel * maxf(delta, 0.0)
	var d2 := dv.length_squared()
	if d2 <= max_change * max_change:
		return wish_vel
	return vel + dv * (max_change / sqrt(d2))


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
