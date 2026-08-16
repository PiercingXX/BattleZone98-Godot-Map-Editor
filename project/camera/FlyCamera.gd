extends Camera3D
class_name FlyCamera
## WASD facing-plane, Q/E world vertical, RMB look. Speed in m/s.

signal speed_changed(mps: float)

var base_speed: float = 80.0
var looking: bool = false
var _look_sens: float = 0.003


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			looking = mb.pressed
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
			)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			base_speed = clampf(base_speed * 1.15, 5.0, 2000.0)
			speed_changed.emit(base_speed)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			base_speed = clampf(base_speed / 1.15, 5.0, 2000.0)
			speed_changed.emit(base_speed)
			get_viewport().set_input_as_handled()
	elif looking and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * _look_sens)
		rotation.x = clampf(rotation.x - mm.relative.y * _look_sens, -1.2, 1.2)
		get_viewport().set_input_as_handled()


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


func frame_map(width_m: float, depth_m: float, height_m: float) -> void:
	base_speed = maxf(40.0, maxf(width_m, depth_m) * 0.08)
	global_position = Vector3(width_m * 0.5, height_m + maxf(80.0, depth_m * 0.15), depth_m * 0.15)
	look_at(Vector3(width_m * 0.5, height_m, depth_m * 0.55), Vector3.UP)
	speed_changed.emit(base_speed)


func top_down(width_m: float, depth_m: float) -> void:
	global_position = Vector3(width_m * 0.5, maxf(width_m, depth_m) * 0.9, depth_m * 0.5)
	look_at(Vector3(width_m * 0.5, 0.0, depth_m * 0.5), Vector3.FORWARD)
	speed_changed.emit(base_speed)


func _text_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE:
			# Caller wires overview via group.
			get_tree().call_group("editor_shell", "camera_overview")
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F:
			get_tree().call_group("editor_shell", "camera_frame")
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_H:
			get_tree().call_group("editor_shell", "toggle_slope")
			get_viewport().set_input_as_handled()
