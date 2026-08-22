extends RefCounted
class_name PoissonDisc
## Bridson 2007 dart throwing in 2D — "Fast Poisson Disk Sampling in
## Arbitrary Dimensions".
##
## Background grid of cell r/sqrt(2) so a cell holds at most one sample and a
## neighbour query is a fixed 5x5 window; an active list seeded with one
## point; k candidates per iteration drawn from the annulus [r, 2r] around a
## random active point, accepted when no sample lies within r. O(n), and
## unlike a jittered grid it leaves no lattice for the eye to find.
##
## The rng belongs to the caller. Hand it a freshly seeded generator and the
## point set is reproducible sample for sample — which is what makes scatter
## a seed plus a mask rather than a stored transform list.

## Bridson suggests k = 30. 15 halves the cost for a barely looser packing,
## and scatter regenerates on every brush stamp.
const K_DEFAULT := 15
## Guard against a pathological radius over a huge rect. Hitting it truncates
## the set (still deterministically) rather than exhausting memory.
const MAX_POINTS := 200000


static func sample(
	rect: Rect2,
	radius: float,
	rng: RandomNumberGenerator,
	k: int = K_DEFAULT,
	max_points: int = MAX_POINTS
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if rng == null or radius <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return out
	if max_points < 1:
		return out
	# Coordinates live in two float arrays rather than a PackedVector2Array:
	# the candidate loop runs tens of thousands of times per chunk and every
	# Vector2 it does not build is time back in the frame budget.
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	var cell: float = radius / sqrt(2.0)
	var inv_cell: float = 1.0 / cell
	var gw: int = maxi(1, int(ceil(rect.size.x / cell)))
	var gh: int = maxi(1, int(ceil(rect.size.y / cell)))
	var grid := PackedInt32Array()
	grid.resize(gw * gh)
	grid.fill(-1)
	var r2: float = radius * radius
	var x0: float = rect.position.x
	var z0: float = rect.position.y
	var x1: float = x0 + rect.size.x
	var z1: float = z0 + rect.size.y

	var fx: float = x0 + rng.randf() * rect.size.x
	var fz: float = z0 + rng.randf() * rect.size.y
	px.append(fx)
	pz.append(fz)
	var gx0: int = mini(int((fx - x0) * inv_cell), gw - 1)
	var gz0: int = mini(int((fz - z0) * inv_cell), gh - 1)
	grid[gz0 * gw + gx0] = 0
	var active := PackedInt32Array()
	active.append(0)
	var active_n := 1
	var kk: int = maxi(1, k)

	while active_n > 0 and px.size() < max_points:
		var ai: int = rng.randi_range(0, active_n - 1)
		var parent: int = active[ai]
		var ax: float = px[parent]
		var az: float = pz[parent]
		var placed := false
		var tries := 0
		while tries < kk:
			tries += 1
			var ang: float = rng.randf() * TAU
			# Uniform over the annulus: r * sqrt(1 + 3u) puts equal area in
			# equal probability, where r * (1 + u) would crowd the inner ring.
			var rr: float = radius * sqrt(1.0 + 3.0 * rng.randf())
			var cxf: float = ax + cos(ang) * rr
			var czf: float = az + sin(ang) * rr
			if cxf < x0 or cxf >= x1 or czf < z0 or czf >= z1:
				continue
			var cx: int = mini(int((cxf - x0) * inv_cell), gw - 1)
			var cz: int = mini(int((czf - z0) * inv_cell), gh - 1)
			# A sample within r can only sit two cells away: the grid holds at
			# most one point per r/sqrt(2) cell.
			var zlo: int = maxi(cz - 2, 0)
			var zhi: int = mini(cz + 2, gh - 1)
			var xlo: int = maxi(cx - 2, 0)
			var xhi: int = mini(cx + 2, gw - 1)
			var bad := false
			var zz := zlo
			while zz <= zhi:
				var row: int = zz * gw
				var xx := xlo
				while xx <= xhi:
					var idx: int = grid[row + xx]
					xx += 1
					if idx < 0:
						continue
					var ddx: float = px[idx] - cxf
					var ddz: float = pz[idx] - czf
					if ddx * ddx + ddz * ddz < r2:
						bad = true
						break
				if bad:
					break
				zz += 1
			if bad:
				continue
			px.append(cxf)
			pz.append(czf)
			grid[cz * gw + cx] = px.size() - 1
			# The active list is used as a stack of active_n entries; a
			# retired slot is refilled rather than the array regrown.
			if active_n < active.size():
				active[active_n] = px.size() - 1
			else:
				active.append(px.size() - 1)
			active_n += 1
			placed = true
			break
		if not placed:
			# Exhausted: retire the parent. Swap-remove — the draw above is
			# uniform over the list, so order carries no meaning.
			active_n -= 1
			active[ai] = active[active_n]
	out.resize(px.size())
	for i in px.size():
		out[i] = Vector2(px[i], pz[i])
	return out
