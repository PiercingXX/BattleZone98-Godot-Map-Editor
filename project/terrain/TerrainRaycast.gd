extends RefCounted
class_name TerrainRaycast
## Analytic ray / heightfield intersection. No physics shapes.


static func height_at(field: HeightField, x_m: float, z_m: float) -> float:
	if field == null:
		return 0.0
	return field.height_at(x_m, z_m)


static func normal_at(field: HeightField, x_m: float, z_m: float) -> Vector3:
	if field == null or field.grid_x < 2:
		return Vector3.UP
	var e := HeightField.CELL_M
	var h_l := field.height_at(x_m - e, z_m)
	var h_r := field.height_at(x_m + e, z_m)
	var h_d := field.height_at(x_m, z_m - e)
	var h_u := field.height_at(x_m, z_m + e)
	var dx := Vector3(2.0 * e, h_r - h_l, 0.0)
	var dz := Vector3(0.0, h_u - h_d, 2.0 * e)
	var n := dz.cross(dx)
	if n.length_squared() < 0.000001:
		return Vector3.UP
	return n.normalized()


static func intersect(origin: Vector3, direction: Vector3, field: HeightField) -> Dictionary:
	## DDA across height cells; intersect the two triangles of each cell.
	var miss := {"hit": false, "position": Vector3.ZERO, "normal": Vector3.UP}
	if field == null or field.grid_x < 2 or field.grid_z < 2:
		return miss
	var dir := direction.normalized()
	if absf(dir.y) < 0.0000001 and absf(dir.x) < 0.0000001 and absf(dir.z) < 0.0000001:
		return miss
	var width_m := float(field.grid_x - 1) * HeightField.CELL_M
	var depth_m := float(field.grid_z - 1) * HeightField.CELL_M
	var t_enter := 0.0
	var t_exit := 20000.0
	# Clip the ray to the map AABB in XZ, Y unbounded then tightened.
	var slabs := [
		[origin.x, dir.x, 0.0, width_m],
		[origin.z, dir.z, 0.0, depth_m],
	]
	for slab in slabs:
		var o: float = slab[0]
		var d: float = slab[1]
		var mn: float = slab[2]
		var mx: float = slab[3]
		if absf(d) < 0.0000001:
			if o < mn or o > mx:
				return miss
			continue
		var t1 := (mn - o) / d
		var t2 := (mx - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		t_enter = maxf(t_enter, t1)
		t_exit = minf(t_exit, t2)
		if t_enter > t_exit:
			return miss
	var start: Vector3 = origin + dir * maxf(t_enter, 0.0)
	var end: Vector3 = origin + dir * t_exit
	var cell := HeightField.CELL_M
	var x := int(floor(start.x / cell))
	var z := int(floor(start.z / cell))
	x = clampi(x, 0, field.grid_x - 2)
	z = clampi(z, 0, field.grid_z - 2)
	var step_x := 1 if dir.x >= 0.0 else -1
	var step_z := 1 if dir.z >= 0.0 else -1
	var t_max_x := _next_boundary(start.x, dir.x, cell, step_x)
	var t_max_z := _next_boundary(start.z, dir.z, cell, step_z)
	var t_delta_x := cell / absf(dir.x) if absf(dir.x) > 0.0000001 else INF
	var t_delta_z := cell / absf(dir.z) if absf(dir.z) > 0.0000001 else INF
	var walked := 0
	var limit := (field.grid_x + field.grid_z) * 4
	while walked < limit:
		var hit := _cell_hit(origin, dir, field, x, z)
		if hit.get("hit", false):
			return hit
		if t_max_x < t_max_z:
			x += step_x
			t_max_x += t_delta_x
		else:
			z += step_z
			t_max_z += t_delta_z
		if x < 0 or z < 0 or x > field.grid_x - 2 or z > field.grid_z - 2:
			break
		walked += 1
	# Fallback: drop a vertical sample at the XZ of the far point.
	if end.x >= 0.0 and end.z >= 0.0 and end.x <= width_m and end.z <= depth_m:
		var y := field.height_at(end.x, end.z)
		return {
			"hit": true,
			"position": Vector3(end.x, y, end.z),
			"normal": normal_at(field, end.x, end.z),
		}
	return miss


static func _next_boundary(pos: float, dir: float, cell: float, step: int) -> float:
	if absf(dir) < 0.0000001:
		return INF
	var next_line: float
	if step > 0:
		next_line = (floor(pos / cell) + 1.0) * cell
	else:
		next_line = floor(pos / cell) * cell
		if is_equal_approx(next_line, pos):
			next_line -= cell
	return (next_line - pos) / dir


static func _cell_hit(origin: Vector3, dir: Vector3, field: HeightField, cx: int, cz: int) -> Dictionary:
	var cell := HeightField.CELL_M
	var p00 := Vector3(float(cx) * cell, field.height_m(cx, cz), float(cz) * cell)
	var p10 := Vector3(float(cx + 1) * cell, field.height_m(cx + 1, cz), float(cz) * cell)
	var p01 := Vector3(float(cx) * cell, field.height_m(cx, cz + 1), float(cz + 1) * cell)
	var p11 := Vector3(float(cx + 1) * cell, field.height_m(cx + 1, cz + 1), float(cz + 1) * cell)
	var a := _tri(origin, dir, p00, p10, p11)
	if a.get("hit", false):
		a["normal"] = normal_at(field, a["position"].x, a["position"].z)
		return a
	var b := _tri(origin, dir, p00, p11, p01)
	if b.get("hit", false):
		b["normal"] = normal_at(field, b["position"].x, b["position"].z)
		return b
	return {"hit": false, "position": Vector3.ZERO, "normal": Vector3.UP}


static func _tri(origin: Vector3, dir: Vector3, v0: Vector3, v1: Vector3, v2: Vector3) -> Dictionary:
	# Möller–Trumbore
	var e1 := v1 - v0
	var e2 := v2 - v0
	var p := dir.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 0.0000001:
		return {"hit": false}
	var inv := 1.0 / det
	var tvec := origin - v0
	var u := tvec.dot(p) * inv
	if u < 0.0 or u > 1.0:
		return {"hit": false}
	var q := tvec.cross(e1)
	var v := dir.dot(q) * inv
	if v < 0.0 or u + v > 1.0:
		return {"hit": false}
	var t := e2.dot(q) * inv
	if t < 0.0:
		return {"hit": false}
	return {"hit": true, "position": origin + dir * t, "normal": Vector3.UP}
