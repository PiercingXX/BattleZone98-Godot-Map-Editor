extends Camera3D
class_name FlyCamera
## RMB look, wheel zoom, MMB orbit, WASD fly.

signal speed_changed(mps: float)

var base_speed: float = 80.0
var looking: bool = false
var orbiting: bool = false
var pivot: Vector3 = Vector3.ZERO
var _look_sens: float = 0.003


func handle_event(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			looking = mb.pressed
			orbiting = false
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
			)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = mb.pressed
			looking = false
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if orbiting else Input.MOUSE_MODE_VISIBLE
			)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dolly(-1.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dolly(1.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if looking:
			rotate_y(-mm.relative.x * _look_sens)
			rotation.x = clampf(rotation.x - mm.relative.y * _look_sens, -1.35, 1.35)
		elif orbiting:
			_orbit(mm.relative)


func _dolly(sign: float) -> void:
	var step := maxf(8.0, base_speed * 0.35) * sign
	global_position += global_transform.basis.z * step


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
	var mul := 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		mul = 4.0
	elif Input.is_key_pressed(KEY_CTRL):
		mul = 0.25
	global_position += wish.normalized() * base_speed * mul * delta
	if Settings.walk_mode and MapState.has_session and MapState.field.grid_x > 1:
		var ground := MapState.field.height_at(global_position.x, global_position.z)
		global_position.y = maxf(global_position.y, ground + 4.0)


func frame_map(width_m: float, depth_m: float, height_m: float) -> void:
	base_speed = maxf(40.0, maxf(width_m, depth_m) * 0.08)
	pivot = Vector3(width_m * 0.5, height_m, depth_m * 0.5)
	global_position = Vector3(width_m * 0.5, height_m + maxf(120.0, depth_m * 0.22), depth_m * -0.02)
	look_at(pivot, Vector3.UP)
	speed_changed.emit(base_speed)


func top_down(width_m: float, depth_m: float) -> void:
	pivot = Vector3(width_m * 0.5, 0.0, depth_m * 0.5)
	global_position = Vector3(width_m * 0.5, maxf(width_m, depth_m) * 0.95, depth_m * 0.5)
	look_at(pivot, Vector3.FORWARD)
	speed_changed.emit(base_speed)


func _text_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox or focus is TextEdit
