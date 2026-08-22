extends RefCounted
## Walk mode's floor. The clamp used to live inside the WASD branch of
## FlyCamera._process, so it only ran on a frame where a movement key was
## held. Every mouse verb — wheel dolly, shift-wheel truck, drag pan, orbit —
## moves the camera without touching that branch, and walk mode let all four
## of them fly the eye underground. These cases pin the floor to the frame,
## not to the keyboard.

const GRID := 64
const RAW_FLAT := 1000  # HeightField.HEIGHT_SCALE 0.1 -> 100 m


func run(t) -> void:
	await _floor_raises_only(t)
	await _mouse_verbs_are_clamped(t)
	await _off_switches_and_exemptions(t)


func _make_field() -> HeightField:
	var field := HeightField.new()
	field.grid_x = GRID
	field.grid_z = GRID
	field.heights.resize(GRID * GRID)
	field.heights.fill(RAW_FLAT)
	return field


## Stand a camera in a session over flat 100 m ground. Returns the camera;
## the caller frees it. Restores MapState/Settings via _restore.
func _setup(t) -> Dictionary:
	var saved := {
		"session": MapState.has_session,
		"field": MapState.field,
		"walk": Settings.walk_mode,
	}
	MapState.field = _make_field()
	MapState.has_session = true
	Settings.walk_mode = true
	var cam := FlyCamera.new()
	t.tree.root.add_child(cam)
	return {"cam": cam, "saved": saved}


func _restore(ctx: Dictionary) -> void:
	var cam: FlyCamera = ctx["cam"]
	cam.queue_free()
	var saved: Dictionary = ctx["saved"]
	MapState.has_session = saved["session"]
	MapState.field = saved["field"]
	Settings.walk_mode = saved["walk"]


func _floor_raises_only(t) -> void:
	var ctx := _setup(t)
	var cam: FlyCamera = ctx["cam"]
	await t.tree.process_frame

	var floor_y := 100.0 + FlyCamera.WALK_CLEARANCE_M

	cam.global_position = Vector3(160.0, -2500.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, floor_y, 0.001, "an eye below the surface is lifted to the floor")

	cam.global_position = Vector3(160.0, 100.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, floor_y, 0.001, "an eye exactly on the surface is lifted clear")

	cam.global_position = Vector3(160.0, 4000.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, 4000.0, 0.001, "the floor raises only; a high camera is left alone")

	# XZ is untouched — this is a floor, not a leash.
	cam.global_position = Vector3(37.5, -10.0, 212.5)
	cam.enforce_walk_floor()
	t.near(cam.global_position.x, 37.5, 0.001, "x untouched")
	t.near(cam.global_position.z, 212.5, 0.001, "z untouched")

	_restore(ctx)


func _mouse_verbs_are_clamped(t) -> void:
	var ctx := _setup(t)
	var cam: FlyCamera = ctx["cam"]
	await t.tree.process_frame
	var floor_y := 100.0 + FlyCamera.WALK_CLEARANCE_M

	# The regression itself: a frame with no movement key held. The old
	# _process returned before the clamp on exactly this frame, which is
	# every frame you navigate with the mouse.
	cam.global_position = Vector3(160.0, -800.0, 160.0)
	cam._process(0.016)
	t.near(cam.global_position.y, floor_y, 0.001,
		"a frame with no key held still enforces the floor")

	# Each mouse verb, driven directly, then given its frame. The dolly runs
	# along the view ray, so aim down to make it a descent.
	cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	cam.global_position = Vector3(160.0, 120.0, 160.0)
	for i in range(40):
		cam._dolly(-1.0)
	t.ok(cam.global_position.y < 100.0, "dolly alone still drives the eye under the surface")
	cam._process(0.016)
	t.ok(cam.global_position.y >= floor_y - 0.001, "the frame after a dolly lifts it back out")

	cam.global_position = Vector3(160.0, -50.0, 160.0)
	cam._truck(1.0)
	cam._process(0.016)
	t.ok(cam.global_position.y >= floor_y - 0.001, "truck is clamped")

	cam.global_position = Vector3(160.0, -50.0, 160.0)
	cam._pan_ground(Vector2(20.0, 20.0))
	cam._process(0.016)
	t.ok(cam.global_position.y >= floor_y - 0.001, "ground pan is clamped")

	cam.pivot = Vector3(160.0, -60.0, 160.0)
	cam.global_position = Vector3(200.0, -50.0, 160.0)
	cam._orbit(Vector2(30.0, 0.0))
	cam._process(0.016)
	t.ok(cam.global_position.y >= floor_y - 0.001, "orbit is clamped")

	# Terrain rising under a parked camera pushes it up: no verb at all.
	cam.global_position = Vector3(160.0, floor_y, 160.0)
	var raised := PackedInt32Array()
	raised.resize(GRID * GRID)
	raised.fill(3000)  # 300 m
	MapState.field.heights = raised
	cam._process(0.016)
	t.near(cam.global_position.y, 300.0 + FlyCamera.WALK_CLEARANCE_M, 0.001,
		"ground sculpted up under a parked camera lifts it")

	_restore(ctx)


func _off_switches_and_exemptions(t) -> void:
	var ctx := _setup(t)
	var cam: FlyCamera = ctx["cam"]
	await t.tree.process_frame

	Settings.walk_mode = false
	cam.global_position = Vector3(160.0, -500.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, -500.0, 0.001, "walk mode off: no floor")

	# Map mode's camera is orthographic and parked at MAP_CAM_Y; clamping it
	# would fight frame_map_ortho for no visible gain.
	Settings.walk_mode = true
	cam.map_mode = true
	cam.global_position = Vector3(160.0, -500.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, -500.0, 0.001, "map mode is exempt")
	cam.map_mode = false

	MapState.has_session = false
	cam.global_position = Vector3(160.0, -500.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, -500.0, 0.001, "no session: nothing to stand on")
	MapState.has_session = true

	# A degenerate field would make height_at meaningless.
	MapState.field = HeightField.new()
	cam.global_position = Vector3(160.0, -500.0, 160.0)
	cam.enforce_walk_floor()
	t.near(cam.global_position.y, -500.0, 0.001, "empty heightfield: no floor")

	_restore(ctx)
