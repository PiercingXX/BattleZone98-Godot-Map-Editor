extends RefCounted
class_name TerrainErosion
## Thermal and hydraulic erosion over a row-major height grid in metres.
##
## Both passes mutate a PackedFloat64Array in place. Heights are metres, not
## raw units, so a talus angle is a plain slope in m/m and reads the same as
## the validator's thresholds (tan 5 deg buildable, tan 30 deg traversable).
##
## Determinism (C6):
##  * thermal is Jacobi — every cell reads the previous iteration's field and
##    writes into a separate delta buffer, so the result cannot depend on scan
##    order. The deltas are still accumulated in a fixed row-major order, so
##    even the floating-point summation order is pinned.
##  * hydraulic is sequential by nature (droplet N sees droplet N-1's work),
##    so its order is pinned instead: droplets run 0..N-1 and their spawn
##    points come from an integer xorshift, never from RandomNumberGenerator
##    or the clock.

## Droplet constants that are not worth a slider.
const _GRAVITY := 4.0
const _EVAPORATE := 0.02
const _MIN_CAPACITY := 0.02
const _START_SPEED := 1.0
const _START_WATER := 1.0


## Talus-angle material transport. Where the drop to a neighbour exceeds the
## talus angle, a `weight` fraction of the excess moves downhill. `dilation`
## picks how it is shared: 0 sends it all to the steepest neighbour, 1 spreads
## it over every neighbour past the talus line in proportion to its excess.
## Wide shelves want dilation; sharp scree wants none.
##
## `weight` above 0.5 makes the scheme oscillate — GenParams.validate() caps
## it there.
static func thermal(
	h: PackedFloat64Array,
	gx: int,
	gz: int,
	cell_m: float,
	steps: int,
	weight: float,
	talus_slope: float,
	dilation: float
) -> void:
	if steps < 1 or gx < 2 or gz < 2 or h.size() != gx * gz:
		return
	var drop := maxf(0.0, talus_slope) * cell_m
	var w := clampf(weight, 0.0, 0.5)
	var dil := clampf(dilation, 0.0, 1.0)
	var steep := 1.0 - dil
	var delta := PackedFloat64Array()
	delta.resize(h.size())
	for _step in steps:
		delta.fill(0.0)
		for z in gz:
			var row := z * gx
			var up := row - gx
			var down := row + gx
			var prev := 0.0
			for x in gx:
				var i := row + x
				var h0: float = h[i]
				var e_up := 0.0
				var e_left := 0.0
				var e_right := 0.0
				var e_down := 0.0
				if z > 0:
					e_up = h0 - h[up + x] - drop
					if e_up < 0.0:
						e_up = 0.0
				if x > 0:
					e_left = h0 - prev - drop
					if e_left < 0.0:
						e_left = 0.0
				if x < gx - 1:
					e_right = h0 - h[i + 1] - drop
					if e_right < 0.0:
						e_right = 0.0
				if z < gz - 1:
					e_down = h0 - h[down + x] - drop
					if e_down < 0.0:
						e_down = 0.0
				prev = h0
				var total := e_up + e_left + e_right + e_down
				if total <= 0.0:
					continue
				var best := e_up
				var slot := 0
				if e_left > best:
					best = e_left
					slot = 1
				if e_right > best:
					best = e_right
					slot = 2
				if e_down > best:
					best = e_down
					slot = 3
				var moved := best * w
				var share := dil * moved / total
				delta[i] -= moved
				if e_up > 0.0:
					delta[up + x] += e_up * share + (moved * steep if slot == 0 else 0.0)
				if e_left > 0.0:
					delta[i - 1] += e_left * share + (moved * steep if slot == 1 else 0.0)
				if e_right > 0.0:
					delta[i + 1] += e_right * share + (moved * steep if slot == 2 else 0.0)
				if e_down > 0.0:
					delta[down + x] += e_down * share + (moved * steep if slot == 3 else 0.0)
		for i in h.size():
			h[i] += delta[i]


## Droplet hydraulic erosion, in the usual sediment-capacity form: a droplet
## follows the gradient, picks up material while it is accelerating downhill
## and drops it when it slows or the ground rises. Written from the published
## description of the method, with slopes normalised by cell size so a preview
## grid and a full-resolution grid carve comparable networks.
##
## `droplets` is an absolute count; the caller scales it with the cell count.
static func hydraulic(
	h: PackedFloat64Array,
	gx: int,
	gz: int,
	cell_m: float,
	rng_seed: int,
	droplets: int,
	lifetime: int,
	inertia: float,
	capacity: float,
	erode: float,
	deposit: float
) -> void:
	if droplets < 1 or gx < 4 or gz < 4 or h.size() != gx * gz:
		return
	var inert := clampf(inertia, 0.0, 0.999)
	var k_cap := maxf(0.0001, capacity)
	var k_erode := clampf(erode, 0.0, 1.0)
	var k_deposit := clampf(deposit, 0.0, 1.0)
	var span_x := float(gx - 2)
	var span_z := float(gz - 2)
	# xorshift32 never leaves zero, so force a non-zero state.
	var state: int = FbmNoise.octave_seed(rng_seed, 7717) | 1
	for _d in droplets:
		state = _xorshift32(state)
		var px := 1.0 + float(state) / 4294967296.0 * span_x
		state = _xorshift32(state)
		var pz := 1.0 + float(state) / 4294967296.0 * span_z
		var dx := 0.0
		var dz := 0.0
		var speed := _START_SPEED
		var water := _START_WATER
		var sediment := 0.0
		var last_i := -1
		var last_u := 0.0
		var last_v := 0.0
		for _life in lifetime:
			var cx := int(px)
			var cz := int(pz)
			if cx < 0 or cz < 0 or cx >= gx - 1 or cz >= gz - 1:
				break
			var u := px - float(cx)
			var v := pz - float(cz)
			var i := cz * gx + cx
			last_i = i
			last_u = u
			last_v = v
			var h00: float = h[i]
			var h10: float = h[i + 1]
			var h01: float = h[i + gx]
			var h11: float = h[i + gx + 1]
			var gx_grad := (h10 - h00) * (1.0 - v) + (h11 - h01) * v
			var gz_grad := (h01 - h00) * (1.0 - u) + (h11 - h10) * u
			var here := (
				h00 * (1.0 - u) * (1.0 - v)
				+ h10 * u * (1.0 - v)
				+ h01 * (1.0 - u) * v
				+ h11 * u * v
			)
			dx = dx * inert - gx_grad * (1.0 - inert)
			dz = dz * inert - gz_grad * (1.0 - inert)
			var len_d := sqrt(dx * dx + dz * dz)
			if len_d < 0.000001:
				break
			dx /= len_d
			dz /= len_d
			px += dx
			pz += dz
			if px < 1.0 or pz < 1.0 or px >= float(gx - 1) or pz >= float(gz - 1):
				break
			var next := _sample(h, gx, px, pz)
			var dh := next - here
			var cap := maxf(-dh / cell_m * speed * water * k_cap, _MIN_CAPACITY)
			if dh > 0.0 or sediment > cap:
				# Uphill: fill the pit, never more than the pit holds.
				var give := minf(dh, sediment) if dh > 0.0 else (sediment - cap) * k_deposit
				give = maxf(0.0, give)
				sediment -= give
				_deposit(h, gx, i, u, v, give)
			else:
				var take := minf((cap - sediment) * k_erode, -dh)
				take = maxf(0.0, take)
				sediment += take
				_erode_brush(h, gx, gz, cx, cz, take)
			var v2 := speed * speed + (-dh) * _GRAVITY
			speed = sqrt(v2) if v2 > 0.0 else 0.0
			water *= 1.0 - _EVAPORATE
		# A droplet that dies still carrying its load drops it where it stopped.
		# Without this the map loses every gram that was in transit — metres of
		# it once the droplet count is realistic — and the whole field sinks.
		if sediment > 0.0 and last_i >= 0:
			_deposit(h, gx, last_i, last_u, last_v, sediment)


static func _xorshift32(state: int) -> int:
	var x := state & 0xFFFFFFFF
	x = (x ^ (x << 13)) & 0xFFFFFFFF
	x = x ^ (x >> 17)
	return (x ^ (x << 5)) & 0xFFFFFFFF


static func _sample(h: PackedFloat64Array, gx: int, px: float, pz: float) -> float:
	var cx := int(px)
	var cz := int(pz)
	var u := px - float(cx)
	var v := pz - float(cz)
	var i := cz * gx + cx
	return (
		h[i] * (1.0 - u) * (1.0 - v)
		+ h[i + 1] * u * (1.0 - v)
		+ h[i + gx] * (1.0 - u) * v
		+ h[i + gx + 1] * u * v
	)


static func _deposit(h: PackedFloat64Array, gx: int, i: int, u: float, v: float, amount: float) -> void:
	if amount <= 0.0:
		return
	h[i] += amount * (1.0 - u) * (1.0 - v)
	h[i + 1] += amount * u * (1.0 - v)
	h[i + gx] += amount * (1.0 - u) * v
	h[i + gx + 1] += amount * u * v


## Radius-1 weighted brush. Eroding a single cell digs one-cell needles that
## the 5 m grid cannot render; spreading it over 3x3 gives channels instead.
static func _erode_brush(
	h: PackedFloat64Array, gx: int, gz: int, cx: int, cz: int, amount: float
) -> void:
	if amount <= 0.0:
		return
	var x0 := maxi(0, cx - 1)
	var x1 := mini(gx - 1, cx + 1)
	var z0 := maxi(0, cz - 1)
	var z1 := mini(gz - 1, cz + 1)
	var total := 0.0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			total += 2.0 if (x == cx and z == cz) else 1.0
	if total <= 0.0:
		return
	var unit := amount / total
	for z in range(z0, z1 + 1):
		var row := z * gx
		for x in range(x0, x1 + 1):
			h[row + x] -= unit * (2.0 if (x == cx and z == cz) else 1.0)
