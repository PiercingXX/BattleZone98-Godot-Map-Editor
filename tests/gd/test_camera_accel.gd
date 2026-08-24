extends RefCounted
## Fly translation accel/drag, fly-tool-only modifier camera, controls_enabled.


func run(t) -> void:
	var saved := {
		"tool": ToolState.tool,
		"speed": Settings.camera_speed_mul,
		"accel": Settings.camera_accel_mul,
	}
	_accel_math(t)
	_integrate(t)
	await _fly_drag(t)
	await _map_drag(t)
	await _modifier_gate(t)
	await _map_plain_pan(t)
	await _controls_enabled(t)
	ToolState.tool = saved["tool"]
	Settings.camera_speed_mul = saved["speed"]
	Settings.camera_accel_mul = saved["accel"]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _make_cam(t) -> FlyCamera:
	var cam := FlyCamera.new()
	t.tree.root.add_child(cam)
	return cam


func _free_cam(cam: FlyCamera) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.queue_free()


func _accel_math(t) -> void:
	t.near(FlyCamera.translation_accel(80.0, 1.0, 1.0), 80.0, 0.0001,
		"mul 1.0: 1.0× speed in 1 s")
	t.near(FlyCamera.translation_accel(80.0, 1.0, 2.0), 160.0, 0.0001,
		"mul 2.0 doubles the rate")
	t.near(FlyCamera.translation_accel(80.0, 2.0, 1.0), 160.0, 0.0001,
		"speed_mul 2.0 still fills in 1 s")
	t.near(
		FlyCamera.translation_accel(80.0, 1.0, 0.1),
		80.0 * Settings.CAM_ACCEL_MIN,
		0.0001,
		"accel_mul below min is coerced",
	)
	t.near(
		FlyCamera.translation_accel(80.0, 1.0, 99.0),
		80.0 * Settings.CAM_ACCEL_MAX,
		0.0001,
		"accel_mul above max is coerced",
	)


func _integrate(t) -> void:
	var wish := Vector3(0.0, 0.0, -80.0)
	var accel := 80.0
	var vel := FlyCamera.integrate_velocity(Vector3.ZERO, wish, accel, 1.0)
	t.near(vel.z, -80.0, 0.0001, "one 1 s step reaches full 1.0×")
	vel = FlyCamera.integrate_velocity(Vector3.ZERO, wish, accel, 0.5)
	t.near(vel.z, -40.0, 0.0001, "half a second is half speed")
	vel = FlyCamera.integrate_velocity(wish, Vector3.ZERO, accel, 1.0)
	t.near(vel.length(), 0.0, 0.0001, "one 1 s step of drag stops from full")
	vel = FlyCamera.integrate_velocity(Vector3.ZERO, wish, 160.0, 0.5)
	t.near(vel.z, -80.0, 0.0001, "accel_mul 2.0 fills in 0.5 s")
	vel = Vector3.ZERO
	var dt := 0.05
	for i in 20:
		vel = FlyCamera.integrate_velocity(vel, wish, accel, dt)
	t.near(vel.z, -80.0, 0.0001, "20 frames also reach full in 1 s")
	for i in 20:
		vel = FlyCamera.integrate_velocity(vel, Vector3.ZERO, accel, dt)
	t.near(vel.length(), 0.0, 0.0001, "20 frames of drag stop in 1 s")


func _fly_drag(t) -> void:
	var cam := _make_cam(t)
	await t.tree.process_frame
	cam.base_speed = 80.0
	Settings.camera_speed_mul = 1.0
	Settings.camera_accel_mul = 1.0
	cam._velocity = Vector3(0.0, 0.0, -80.0)
	var dt := 0.05
	for i in 10:
		cam._process_fly(dt)
	t.near(cam._velocity.z, -40.0, 0.01, "0.5 s of drag halves 1.0× speed")
	for i in 10:
		cam._process_fly(dt)
	t.near(cam._velocity.length(), 0.0, 0.01, "_process_fly stops in 1 s from full")
	_free_cam(cam)
	await t.tree.process_frame


func _map_drag(t) -> void:
	var cam := _make_cam(t)
	await t.tree.process_frame
	cam.base_speed = 80.0
	Settings.camera_speed_mul = 1.0
	Settings.camera_accel_mul = 1.0
	cam.map_mode = true
	cam._map_velocity = Vector2(80.0, 0.0)
	var dt := 0.05
	for i in 10:
		cam._process_map_pan(dt)
	t.near(cam._map_velocity.x, 40.0, 0.01, "map pan drag halves in 0.5 s")
	for i in 10:
		cam._process_map_pan(dt)
	t.near(cam._map_velocity.length(), 0.0, 0.01, "map pan stops in 1 s")
	_free_cam(cam)
	await t.tree.process_frame


func _modifier_gate(t) -> void:
	var cam := _make_cam(t)
	await t.tree.process_frame
	ToolState.tool = "fly"
	t.ok(cam.is_modifier_camera_allowed(), "fly tool allows modifier camera")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true, true, false, false))
	t.ok(cam.pan_dragging, "fly Shift+RMB pans")
	t.ok(not cam.looking)
	t.ok(not cam.orbiting)
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))

	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true, false, true, false))
	t.ok(cam.orbiting, "fly Ctrl+RMB orbits")
	t.ok(not cam.looking)
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))

	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true, false, false, true))
	t.ok(cam.orbiting, "fly Alt+RMB orbits")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))

	cam.handle_event(_btn(MOUSE_BUTTON_MIDDLE, true, true, false, false))
	t.ok(cam.pan_dragging, "fly Shift+MMB pans")
	t.ok(not cam.orbiting)
	cam.handle_event(_btn(MOUSE_BUTTON_MIDDLE, false))

	cam.global_position = Vector3(0.0, 100.0, 0.0)
	cam.rotation = Vector3.ZERO
	ToolState.tool = "fly"
	cam.handle_event(_wheel(true, true, false))
	var after := cam.global_position
	cam.global_position = Vector3(0.0, 100.0, 0.0)
	cam._truck(-1.0)
	t.near(after.x, cam.global_position.x, 0.001, "fly Shift+wheel trucks")
	t.near(after.z, cam.global_position.z, 0.001)

	ToolState.tool = "paint"
	t.ok(not cam.is_modifier_camera_allowed(), "paint tool blocks modifier camera")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true, true, false, false))
	t.ok(cam.looking, "non-fly Shift+RMB is plain look")
	t.ok(not cam.pan_dragging)
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))

	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true, false, true, false))
	t.ok(cam.looking, "non-fly Ctrl+RMB is plain look")
	t.ok(not cam.orbiting)
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))

	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true, false, false, false))
	t.ok(cam.looking, "plain RMB look still works off fly")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))

	cam.handle_event(_btn(MOUSE_BUTTON_MIDDLE, true, true, false, false))
	t.ok(cam.orbiting, "non-fly Shift+MMB is plain orbit")
	t.ok(not cam.pan_dragging)
	cam.handle_event(_btn(MOUSE_BUTTON_MIDDLE, false))

	cam.global_position = Vector3(0.0, 100.0, 0.0)
	cam.rotation = Vector3.ZERO
	cam.handle_event(_wheel(true, true, false))
	after = cam.global_position
	cam.global_position = Vector3(0.0, 100.0, 0.0)
	cam._dolly(-1.0)
	t.near(after.x, cam.global_position.x, 0.001, "non-fly Shift+wheel dollies")
	t.near(after.z, cam.global_position.z, 0.001)

	cam.global_position = Vector3(0.0, 100.0, 0.0)
	cam.handle_event(_wheel(true, false, false))
	after = cam.global_position
	cam.global_position = Vector3(0.0, 100.0, 0.0)
	cam._dolly(-1.0)
	t.near(after.x, cam.global_position.x, 0.001, "plain wheel zoom still works off fly")
	t.near(after.z, cam.global_position.z, 0.001)

	var yaw0 := cam.rotation.y
	cam.handle_event(_move(Vector2(30.0, 0.0), false, false, true))
	t.near(cam.rotation.y, yaw0, 0.0001, "non-fly Alt+move does not look")
	ToolState.tool = "fly"
	cam.handle_event(_move(Vector2(30.0, 0.0), false, false, true))
	t.ok(absf(cam.rotation.y - yaw0) > 0.0001, "fly Alt+move looks")

	cam.global_position = Vector3(0.0, 100.0, 0.0)
	var before := cam.global_position
	ToolState.tool = "paint"
	cam.handle_event(_move(Vector2(40.0, 0.0), true, false, false))
	t.near(cam.global_position.x, before.x, 0.0001, "non-fly Shift+move does not pan")
	ToolState.tool = "fly"
	cam.handle_event(_move(Vector2(40.0, 0.0), true, false, false))
	t.ok(absf(cam.global_position.x - before.x) > 0.01, "fly Shift+move pans")

	_free_cam(cam)
	await t.tree.process_frame


func _map_plain_pan(t) -> void:
	var cam := _make_cam(t)
	await t.tree.process_frame
	cam.map_mode = true
	ToolState.tool = "paint"
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true))
	t.ok(cam.panning, "map RMB pan works off fly")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))
	t.ok(not cam.panning)
	cam.handle_event(_btn(MOUSE_BUTTON_MIDDLE, true))
	t.ok(cam.panning, "map MMB pan works off fly")
	cam.handle_event(_btn(MOUSE_BUTTON_MIDDLE, false))

	cam.size = 800.0
	cam.global_position = Vector3(100.0, FlyCamera.MAP_CAM_Y, 100.0)
	cam.handle_event(_wheel(true, true, false))
	t.ok(not is_equal_approx(cam.size, 800.0), "non-fly map Shift+wheel still zooms")

	cam.size = 800.0
	var before := cam.global_position
	cam.handle_event(_move(Vector2(20.0, 0.0), true, false, false))
	t.near(cam.global_position.x, before.x, 0.001, "non-fly map Shift+move does not pan")

	ToolState.tool = "fly"
	cam.size = 800.0
	before = cam.global_position
	cam.handle_event(_wheel(true, true, false))
	t.near(cam.size, 800.0, 0.001, "fly map Shift+wheel does not zoom")
	t.ok(cam.global_position.distance_to(before) > 0.5, "fly map Shift+wheel pans")
	_free_cam(cam)
	await t.tree.process_frame


func _controls_enabled(t) -> void:
	var cam := _make_cam(t)
	await t.tree.process_frame
	ToolState.tool = "fly"
	t.ok(cam.is_modifier_camera_allowed())
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true))
	t.ok(cam.looking, "RMB looks while enabled")
	cam.controls_enabled = false
	t.ok(not cam.looking, "disabling releases look")
	t.ok(not cam.is_modifier_camera_allowed(), "disabled blocks modifier camera")
	t.eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "disabling does not keep capture")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true))
	t.ok(not cam.looking, "handle_event is a no-op while disabled")
	var pos0 := cam.global_position
	cam._velocity = Vector3(0.0, 0.0, -80.0)
	cam._process_fly(0.05)
	t.near(cam.global_position.z, pos0.z, 0.0001, "_process_fly does not move while disabled")
	t.near(cam._velocity.length(), 0.0, 0.0001, "disabled fly zeros leftover velocity")
	cam.map_mode = true
	cam._map_velocity = Vector2(80.0, 0.0)
	cam._process_map_pan(0.05)
	t.near(cam._map_velocity.length(), 0.0, 0.0001, "disabled map pan zeros leftover velocity")
	cam.begin_pan()
	t.ok(not cam.panning, "begin_pan refuses while disabled")
	cam.controls_enabled = true
	cam.map_mode = false
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, true))
	t.ok(cam.looking, "re-enabled RMB look works")
	cam.handle_event(_btn(MOUSE_BUTTON_RIGHT, false))
	_free_cam(cam)
	await t.tree.process_frame


func _btn(
	button: MouseButton,
	pressed: bool,
	shift := false,
	ctrl := false,
	alt := false,
) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	return ev


func _wheel(up: bool, shift: bool, alt: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


func _move(rel: Vector2, shift: bool, ctrl: bool, alt: bool) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.button_mask = 0
	return ev
