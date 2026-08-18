extends RefCounted
## Camera bookmark pose encode/decode and session sidecar round-trip.


func run(t) -> void:
	var pos := Vector3(12.5, 40.0, -8.25)
	var rot := Vector3(-0.4, 1.2, 0.0)
	var pivot := Vector3(640.0, 20.0, 640.0)
	var pose := FlyCamera.make_bookmark(pos, rot, pivot)
	t.near(FlyCamera.bookmark_position(pose).x, pos.x)
	t.near(FlyCamera.bookmark_position(pose).y, pos.y)
	t.near(FlyCamera.bookmark_position(pose).z, pos.z)
	t.near(FlyCamera.bookmark_rotation(pose).x, rot.x)
	t.near(FlyCamera.bookmark_rotation(pose).y, rot.y)
	t.near(FlyCamera.bookmark_pivot(pose).x, pivot.x)
	t.near(FlyCamera.bookmark_pivot(pose).z, pivot.z)
	t.eq(FlyCamera.bookmark_position({}), Vector3.ZERO, "empty pose falls back")

	t.eq(Keymap.bookmark_slot("bookmark.store.3"), 3)
	t.eq(Keymap.bookmark_slot("bookmark.recall.5"), 5)
	t.eq(Keymap.bookmark_slot("bookmark.store.9"), 0, "slot out of range")
	t.ok(Keymap.is_bookmark_store("bookmark.store.1"))
	t.ok(Keymap.is_bookmark_recall("bookmark.recall.2"))
	t.ok(not Keymap.is_bookmark_store("bookmark.recall.2"))

	var tmp := OS.get_temp_dir().path_join("bz_bookmarks_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	t.ok(not SessionIO.store_bookmark("", 1, pose), "no session")
	t.ok(not SessionIO.store_bookmark(tmp, 0, pose), "slot 0 invalid")
	t.ok(SessionIO.store_bookmark(tmp, 1, pose), "store slot 1")
	t.ok(SessionIO.store_bookmark(tmp, 5, pose), "store slot 5")
	var got := SessionIO.recall_bookmark(tmp, 1)
	t.near(FlyCamera.bookmark_position(got).x, pos.x, 0.0001, "recalled x")
	t.near(FlyCamera.bookmark_position(got).y, pos.y, 0.0001, "recalled y")
	t.near(FlyCamera.bookmark_rotation(got).y, rot.y, 0.0001, "recalled yaw")
	t.near(FlyCamera.bookmark_pivot(got).x, pivot.x, 0.0001, "recalled pivot")
	t.eq(SessionIO.recall_bookmark(tmp, 2), {}, "empty slot")
	t.eq(SessionIO.recall_bookmark(tmp, 0), {}, "invalid slot")

	var cam := FlyCamera.new()
	t.tree.root.add_child(cam)
	await t.tree.process_frame
	cam.global_position = pos
	cam.rotation = rot
	cam.pivot = pivot
	var captured := cam.capture_bookmark()
	cam.global_position = Vector3.ZERO
	cam.rotation = Vector3.ZERO
	cam.pivot = Vector3.ZERO
	cam.apply_bookmark(captured)
	t.near(cam.global_position.x, pos.x, 0.0001, "apply position")
	t.near(cam.rotation.y, rot.y, 0.0001, "apply rotation")
	t.near(cam.pivot.z, pivot.z, 0.0001, "apply pivot")
	cam.queue_free()
	await t.tree.process_frame

	var da := DirAccess.open(tmp)
	if da:
		for f in da.get_files():
			DirAccess.remove_absolute(tmp.path_join(str(f)))
	DirAccess.remove_absolute(tmp)
