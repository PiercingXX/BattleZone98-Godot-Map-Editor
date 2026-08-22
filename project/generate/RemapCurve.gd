extends RefCounted
class_name RemapCurve
## Remap LUT for the generator's normalised 0..1 noise.
##
## A uniformly sampled lookup table, not a spline: uniform sampling means
## evaluation is two array reads and a lerp, there is nothing to sort, and the
## table itself is the serialised form. That keeps the remap out of the
## determinism argument entirely (C6) — no ordering, no transcendentals.
##
## This is the knob that turns noise into RTS terrain. `plateau` splits the
## map into two flat tiers joined by ramps; `terrace` cuts mesa benches. A
## linear curve gives you rolling ground that is buildable almost nowhere.

const SAMPLES := 65


static func linear(samples: int = SAMPLES) -> PackedFloat64Array:
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = float(i) / float(n - 1)
	return out


static func constant(value: float, samples: int = SAMPLES) -> PackedFloat64Array:
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	out.fill(clampf(value, 0.0, 1.0))
	return out


## Flat lowland below `low`, flat highland above `high`, a ramp between. The
## ends have zero gradient, so both tiers are genuinely buildable.
static func plateau(low: float, high: float, samples: int = SAMPLES) -> PackedFloat64Array:
	var a := clampf(minf(low, high), 0.0, 1.0)
	var b := clampf(maxf(low, high), 0.0, 1.0)
	if b - a < 0.001:
		b = minf(1.0, a + 0.001)
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = smoothstep(a, b, float(i) / float(n - 1))
	return out


## `steps` mesa benches. `sharpness` 0 rounds every riser away, 1 makes each
## bench a flat shelf with a near-vertical riser.
static func terrace(steps: int, sharpness: float, samples: int = SAMPLES) -> PackedFloat64Array:
	var k := maxi(1, steps)
	var half := lerpf(0.5, 0.03, clampf(sharpness, 0.0, 1.0))
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n - 1)
		var s := t * float(k)
		var band := floorf(s)
		if band > float(k - 1):
			band = float(k - 1)
		var f := s - band
		out[i] = (band + smoothstep(0.5 - half, 0.5 + half, f)) / float(k)
	return out


## Bias the whole range toward the floor (`amount` < 0.5) or the ceiling
## (> 0.5) without clipping either end. Useful for "mostly lowland with a few
## peaks", which is what a 2-base RTS map wants.
static func bias(amount: float, samples: int = SAMPLES) -> PackedFloat64Array:
	var a := clampf(amount, 0.02, 0.98)
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n - 1)
		# Perlin's bias, written with a divide instead of pow so the curve
		# never touches libm.
		out[i] = t / ((1.0 / a - 2.0) * (1.0 - t) + 1.0)
	return out


## Piecewise-linear curve through authored control points, baked to a LUT.
## Points are matched by index; x values must be non-decreasing, and anything
## outside 0..1 is clamped. Out-of-order points are ignored rather than sorted,
## so the bake never depends on a sort's tie-breaking.
static func from_points(
	xs: PackedFloat64Array, ys: PackedFloat64Array, samples: int = SAMPLES
) -> PackedFloat64Array:
	var kx := PackedFloat64Array()
	var ky := PackedFloat64Array()
	var last := -1.0
	for i in mini(xs.size(), ys.size()):
		var x := clampf(xs[i], 0.0, 1.0)
		if x < last:
			continue
		last = x
		kx.append(x)
		ky.append(clampf(ys[i], 0.0, 1.0))
	if kx.size() < 2:
		return linear(samples)
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	var k := 0
	for i in n:
		var t := float(i) / float(n - 1)
		while k + 2 < kx.size() and kx[k + 1] < t:
			k += 1
		var x0 := kx[k]
		var x1 := kx[k + 1]
		var span := x1 - x0
		if span <= 0.0:
			out[i] = ky[k + 1] if t >= x1 else ky[k]
			continue
		var f := clampf((t - x0) / span, 0.0, 1.0)
		out[i] = ky[k] + (ky[k + 1] - ky[k]) * f
	return out


## Godot's Curve editor resource, sampled into a LUT. The generator never
## touches the Curve itself, so the dialog can hand one over and everything
## downstream stays on the deterministic path.
static func from_curve(curve: Curve, samples: int = SAMPLES) -> PackedFloat64Array:
	if curve == null:
		return linear(samples)
	var n := maxi(2, samples)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = clampf(float(curve.sample(float(i) / float(n - 1))), 0.0, 1.0)
	return out


static func blend(a: PackedFloat64Array, b: PackedFloat64Array, t: float) -> PackedFloat64Array:
	var n := maxi(a.size(), b.size())
	if n < 2:
		return linear()
	var f := clampf(t, 0.0, 1.0)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		var u := float(i) / float(n - 1)
		out[i] = eval(a, u) + (eval(b, u) - eval(a, u)) * f
	return out


static func eval(lut: PackedFloat64Array, t: float) -> float:
	var n := lut.size()
	if n == 0:
		return clampf(t, 0.0, 1.0)
	if n == 1:
		return lut[0]
	var u := clampf(t, 0.0, 1.0) * float(n - 1)
	var i := int(u)
	if i >= n - 1:
		return lut[n - 1]
	var f := u - float(i)
	return lut[i] + (lut[i + 1] - lut[i]) * f
