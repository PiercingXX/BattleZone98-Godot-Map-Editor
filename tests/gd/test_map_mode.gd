extends RefCounted
## Ortho map mode math, north snap, go-to parsing, pose restore.


func run(t) -> void:
	_parse_goto(t)
	_north_and_rose(t)
	_compass_hit(t)
	_ortho_math(t)
	_basis(t)
	await _camera_live(t)


func _parse_goto(t) -> void:
	var a := FlyCamera.parse_goto("100, 200")
	t.near(a.x, 100.0)
	t.near(a.y, 200.0)
	var b := FlyCamera.parse_goto("12.5  -8")
	t.near(b.x, 12.5)
	t.near(b.y, -8.0)
	var c := FlyCamera.parse_goto("1,2,3")
	t.near(c.x, 1.0, 0.0001, "extra y ignored")
	t.near(c.y, 2.0, 0.0001)
	t.ok(not FlyCamera.parse_goto("").is_finite(), "empty fails")
	t.ok(not FlyCamera.parse_goto("100").is_finite(), "one number fails")
	t.ok(not FlyCamera.parse_goto("foo, bar").is_finite(), "words fail")
	t.ok(not FlyCamera.parse_goto("   ").is_finite())
	var d := FlyCamera.parse_goto("  -3.25,40.0  ")
	t.near(d.x, -3.25)
	t.near(d.y, 40.0)


func _north_and_rose(t) -> void:
	t.near(FlyCamera.north_yaw(), PI, 0.0001, "north yaw faces +z")
	t.near(FlyCamera.rose_radians_from_look(Vector3(0.0, 0.0, 1.0)), 0.0, 0.0001, "facing north")
	# The view is mirrored (FlyCamera.VIEW_MIRROR) so east is screen-right,
	# which puts north on the RIGHT of the rose when facing east.
	t.near(FlyCamera.rose_radians_from_look(Vector3(1.0, 0.0, 0.0)), PI / 2.0, 0.0001, "facing east, N on the right")
	t.near(FlyCamera.rose_radians_from_look(Vector3(-1.0, 0.0, 0.0)), -PI / 2.0, 0.0001, "facing west, N on the left")
	var south := FlyCamera.rose_radians_from_look(Vector3(0.0, 0.0, -1.0))
	t.ok(absf(absf(south) - PI) < 0.0001, "facing south, N at the bottom")
	t.near(FlyCamera.rose_radians_from_look(Vector3(0.0, -1.0, 0.0)), 0.0, 0.0001, "look-down is N-up")
	var look := FlyCamera.look_dir_from_basis_z(Vector3(0.0, 0.0, 1.0))
	t.near(look.z, -1.0, 0.0001, "identity basis looks south")


func _compass_hit(t) -> void:
	var sz := Vector2(80, 80)
	t.eq(FlyCamera.compass_hit(Vector2(40, 40), sz, 0.0), "center")
	t.eq(FlyCamera.compass_hit(Vector2(40, 8), sz, 0.0), "n")
	t.eq(FlyCamera.compass_hit(Vector2(72, 40), sz, 0.0), "e")
	t.eq(FlyCamera.compass_hit(Vector2(40, 72), sz, 0.0), "s")
	t.eq(FlyCamera.compass_hit(Vector2(8, 40), sz, 0.0), "w")
	t.eq(FlyCamera.compass_hit(Vector2(-4, 40), sz, 0.0), "", "outside the rose")
	t.eq(FlyCamera.compass_hit(Vector2(72, 40), sz, PI / 2.0), "n", "rose clockwise 90°, N is on the right")
	t.eq(FlyCamera.compass_hit(Vector2(40, 8), sz, PI / 2.0), "w", "W arm rotates to the top")


func _ortho_math(t) -> void:
	t.near(FlyCamera.ortho_zoom_size(100.0, -1.0), 85.0, 0.0001, "wheel up zooms in")
	t.near(FlyCamera.ortho_zoom_size(85.0, 1.0), 100.0, 0.0001, "wheel down zooms out")
	t.near(FlyCamera.ortho_zoom_size(10.0, -1.0), FlyCamera.MAP_SIZE_MIN, 0.0001, "clamp min")
	var kept := FlyCamera.zoom_keep_point(100.0, 50.0, Vector2(0, 0), Vector2(40, 20))
	t.near(kept.x, 20.0, 0.0001, "zoom-to-cursor keeps the point")
	t.near(kept.y, 10.0, 0.0001)
	var pan := FlyCamera.ortho_pan_delta(Vector2(10.0, -8.0), 200.0, 100.0)
	t.near(pan.x, -20.0, 0.0001, "drag right moves camera west")
	t.near(pan.y, -16.0, 0.0001, "drag up moves camera south")
	t.eq(FlyCamera.ortho_pan_delta(Vector2(4, 4), 100.0, 0.0), Vector2.ZERO)
	t.near(FlyCamera.ortho_frame_size(1280.0, 1280.0, 1.0), 1280.0 * 1.08, 0.001)
	t.near(FlyCamera.ortho_frame_size(2560.0, 1280.0, 2.0), 1280.0 * 1.08, 0.001, "wide view fits depth")
	var hover := FlyCamera.hover_perspective_position(Vector3(10.0, 2.0, 8.0))
	t.near(hover.x, 10.0)
	t.near(hover.y, 42.0)
	t.near(hover.z, -32.0)


func _basis(t) -> void:
	var b := FlyCamera.map_mode_basis()
	t.near(b.x.x, 1.0, 0.0001, "screen-right is +x east")
	t.near(b.y.z, 1.0, 0.0001, "screen-up is +z north")
	t.near(b.z.y, 1.0, 0.0001, "camera +Z is world +Y")
	var look := -b.z
	t.near(look.x, 0.0, 0.0001)
	t.near(look.y, -1.0, 0.0001, "look is straight down")
	t.near(look.z, 0.0, 0.0001)


func _camera_live(t) -> void:
	var cam := FlyCamera.new()
	t.tree.root.add_child(cam)
	await t.tree.process_frame
	cam.global_position = Vector3(12.0, 50.0, 24.0)
	# Orientation goes through the aim API: `rotation` is the euler of the
	# mirrored basis and does not decompose to anything meaningful.
	cam.set_aim_rotation(Vector3(-0.35, 0.8, 0.0))
	cam.pivot = Vector3(100.0, 10.0, 200.0)
	cam.hover_point(Vector3(5.0, 2.0, 9.0))
	t.near(cam.global_position.x, 5.0, 0.0001, "3D hover x")
	t.near(cam.global_position.y, 42.0, 0.0001, "3D hover lift")
	t.near(cam.global_position.z, -31.0, 0.0001, "3D hover back")

	cam.global_position = Vector3(12.0, 50.0, 24.0)
	# Orientation goes through the aim API: `rotation` is the euler of the
	# mirrored basis and does not decompose to anything meaningful.
	cam.set_aim_rotation(Vector3(-0.35, 0.8, 0.0))
	cam.pivot = Vector3(100.0, 10.0, 200.0)
	cam.set_map_mode(true)
	t.ok(cam.map_mode)
	t.eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
	t.near(cam.global_position.x, 100.0, 0.001, "2D sits over the pivot")
	t.near(cam.global_position.z, 200.0, 0.001)
	t.near(cam.global_transform.basis.y.z, 1.0, 0.05, "2D screen-up is +z")
	var look := -cam.global_transform.basis.z
	t.near(look.y, -1.0, 0.05, "2D look is straight down")
	cam.hover_point(Vector3(15.0, 3.0, 25.0))
	t.near(cam.global_position.x, 15.0, 0.001, "2D hover x")
	t.near(cam.global_position.z, 25.0, 0.001, "2D hover z")
	t.eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
	cam.set_map_mode(false)
	t.ok(not cam.map_mode)
	t.eq(cam.projection, Camera3D.PROJECTION_PERSPECTIVE)
	t.near(cam.global_position.x, 12.0, 0.001, "leaving 2D restores x")
	t.near(cam.global_position.y, 50.0, 0.001, "leaving 2D restores y")
	t.near(cam.global_position.z, 24.0, 0.001, "leaving 2D restores z")
	t.near(cam.aim_rotation().y, 0.8, 0.001, "leaving 2D restores yaw")
	t.near(cam.aim_rotation().x, -0.35, 0.001, "leaving 2D restores pitch")
	t.near(
		cam.global_transform.basis.determinant(), -1.0, 0.001,
		"the 3D view stays mirrored, same as the map view"
	)

	cam.set_aim_rotation(Vector3(-0.3, 0.5, 0.0))
	cam.snap_yaw_north()
	# Euler decomposition can hand back either sign of a half turn.
	t.ok(
		absf(absf(cam.aim_rotation().y) - FlyCamera.north_yaw()) < 0.0001,
		"snap yaw to north"
	)
	t.near(cam.aim_rotation().x, -0.3, 0.0001, "snap keeps pitch")

	cam.queue_free()
	await t.tree.process_frame
