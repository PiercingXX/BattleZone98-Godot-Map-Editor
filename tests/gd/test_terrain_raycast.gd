extends RefCounted
## TerrainRaycast: real hits, honest misses, and no phantom hit on the border.


func run(t) -> void:
	var field := _flat(64, 64, 200)  # 315 m square, flat at 20 m
	var surface := 20.0

	# Straight down from above the middle: a plain hit.
	var down: Dictionary = TerrainRaycast.intersect(
		Vector3(100.0, 400.0, 100.0), Vector3.DOWN, field
	)
	t.ok(bool(down.get("hit", false)), "straight down hits")
	var p: Vector3 = down["position"]
	t.near(p.x, 100.0)
	t.near(p.z, 100.0)
	t.near(p.y, surface)

	# Shallow but descending: still a real intersection, inside the map.
	var shallow: Dictionary = TerrainRaycast.intersect(
		Vector3(10.0, 60.0, 10.0), Vector3(1.0, -0.2, 0.6), field
	)
	t.ok(bool(shallow.get("hit", false)), "a descending ray still hits")

	# The bug: a ray that leaves the map still in the air used to come back
	# as a hit on the far border, hundreds of metres from the cursor. Every
	# near-horizon view produced one, and brush strokes bridged to it.
	var horizon: Dictionary = TerrainRaycast.intersect(
		Vector3(10.0, 120.0, 10.0), Vector3(1.0, -0.01, 0.0), field
	)
	t.eq(horizon.get("hit"), false, "a ray leaving the map above ground misses")

	var upward: Dictionary = TerrainRaycast.intersect(
		Vector3(150.0, 60.0, 150.0), Vector3(1.0, 0.4, 0.2), field
	)
	t.eq(upward.get("hit"), false, "a ray angled up misses")

	var away: Dictionary = TerrainRaycast.intersect(
		Vector3(-50.0, 60.0, 150.0), Vector3(-1.0, -0.5, 0.0), field
	)
	t.eq(away.get("hit"), false, "a ray pointing away from the map misses")

	# A ray that ends below the surface is the case the fallback exists for.
	var under: Dictionary = TerrainRaycast.intersect(
		Vector3(150.0, 5.0, 150.0), Vector3(1.0, -0.02, 0.0), field
	)
	t.ok(bool(under.get("hit", false)), "a ray already under the surface reports one")

	# Every reported hit is inside the map, whatever the angle.
	var w := float(field.grid_x - 1) * HeightField.CELL_M
	for i in 24:
		var ang := float(i) * TAU / 24.0
		var res: Dictionary = TerrainRaycast.intersect(
			Vector3(w * 0.5, 90.0, w * 0.5),
			Vector3(cos(ang), -0.05, sin(ang)),
			field
		)
		if not bool(res.get("hit", false)):
			continue
		var q: Vector3 = res["position"]
		t.ok(q.x >= -0.01 and q.x <= w + 0.01, "hit x in range at %d" % i)
		t.ok(q.z >= -0.01 and q.z <= w + 0.01, "hit z in range at %d" % i)


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field
