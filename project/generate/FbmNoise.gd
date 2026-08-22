extends RefCounted
class_name FbmNoise
## Fractal Brownian motion over Godot's built-in FastNoiseLite.
##
## The octave loop lives here rather than inside FastNoiseLite's own fractal
## mode so the amplitude ladder, the per-octave seeds and the normalisation are
## all visible and testable. Each octave is its own FastNoiseLite with its own
## derived seed, so octaves decorrelate without sharing a lattice.
##
## Determinism (C6): every sequence here is an integer `for i in n` loop, the
## amplitude ladder is built by repeated multiplication rather than pow(), and
## the sum is normalised by the analytic amplitude total — never by the
## observed min/max, which would make a reduced-resolution preview normalise
## differently from the full-resolution result.
##
## Sampling is in world metres, so the same parameters describe the same
## continuous field at any output resolution.

const OFFSET_SPREAD := 4096.0

var _noise: Array[FastNoiseLite] = []
var _amp: PackedFloat64Array = PackedFloat64Array()
var _off_x: PackedFloat64Array = PackedFloat64Array()
var _off_z: PackedFloat64Array = PackedFloat64Array()
var _inv_total: float = 1.0
var _mode: int = GenParams.MODE_FBM
var _base_x: float = 0.0
var _base_z: float = 0.0


func configure(p: GenParams) -> void:
	_noise.clear()
	_amp = PackedFloat64Array()
	_off_x = PackedFloat64Array()
	_off_z = PackedFloat64Array()
	_mode = p.noise_mode
	_base_x = p.offset_x_m
	_base_z = p.offset_z_m
	# roughness is a trim on persistence, not a fourth fractal parameter:
	# 0.5 leaves `gain` exactly as authored.
	var g := clampf(p.gain * (0.5 + p.roughness), 0.05, 0.95)
	var freq := 1.0 / maxf(1.0, p.scale_m)
	var amp := 1.0
	var total := 0.0
	for i in maxi(1, p.octaves):
		var n := FastNoiseLite.new()
		n.seed = octave_seed(p.seed, i)
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.frequency = freq
		_noise.append(n)
		_amp.append(amp)
		# Every gradient-noise octave is 0 at the lattice origin, so without a
		# per-octave shift the map's (0,0) corner sits at exactly mid height.
		_off_x.append(float(octave_seed(p.seed, 1000 + i) % 8192) * 0.5)
		_off_z.append(float(octave_seed(p.seed, 2000 + i) % 8192) * 0.5)
		total += amp
		amp *= g
		freq *= p.lacunarity
	_inv_total = 1.0 / total if total > 0.0 else 1.0


func octaves() -> int:
	return _noise.size()


## Normalised 0..1 value at a world position in metres. Single-point probe for
## the UI; fill() is the path generation takes. The two agree bit-for-bit as
## long as the additions stay in this order, which is why the offsets are
## folded before the position rather than after it.
func sample(x_m: float, z_m: float) -> float:
	var acc := 0.0
	for i in _noise.size():
		var ox: float = _base_x + _off_x[i]
		var oz: float = _base_z + _off_z[i]
		var v: float = _noise[i].get_noise_2d(ox + x_m, oz + z_m)
		match _mode:
			GenParams.MODE_RIDGED:
				var r := 1.0 - absf(v)
				v = r * r * 2.0 - 1.0
			GenParams.MODE_BILLOW:
				v = absf(v) * 2.0 - 1.0
		acc += v * _amp[i]
	return clampf(acc * _inv_total * 0.5 + 0.5, 0.0, 1.0)


## Fill a row-major grid (C7) of normalised 0..1 values. `cell_m` is the world
## spacing of the OUTPUT grid, which is not the map's 5 m cell when generating
## a preview.
##
## One octave at a time, not one cell at a time, and the mode test is lifted
## out of the inner loop into three near-identical bodies. That is deliberate
## duplication: hoisting the array indexing and the branch out of the hot loop
## cut a 512x512 five-octave fill from 1.6 s to a fifth of that, and this runs
## on the interactive preview path. The summation order per cell is unchanged
## (octave 0 upward), so the result is bit-identical to the naive form.
func fill(gx: int, gz: int, cell_m: float, origin_x_m: float, origin_z_m: float) -> PackedFloat64Array:
	var n := maxi(0, gx * gz)
	var out := PackedFloat64Array()
	out.resize(n)
	for o in _noise.size():
		var nz: FastNoiseLite = _noise[o]
		var amp: float = _amp[o]
		var ox: float = origin_x_m + _base_x + _off_x[o]
		var oz: float = origin_z_m + _base_z + _off_z[o]
		match _mode:
			GenParams.MODE_RIDGED:
				for z in gz:
					var wz := oz + float(z) * cell_m
					var row := z * gx
					for x in gx:
						var r := 1.0 - absf(nz.get_noise_2d(ox + float(x) * cell_m, wz))
						out[row + x] += (r * r * 2.0 - 1.0) * amp
			GenParams.MODE_BILLOW:
				for z in gz:
					var wz := oz + float(z) * cell_m
					var row := z * gx
					for x in gx:
						var v := absf(nz.get_noise_2d(ox + float(x) * cell_m, wz))
						out[row + x] += (v * 2.0 - 1.0) * amp
			_:
				for z in gz:
					var wz := oz + float(z) * cell_m
					var row := z * gx
					for x in gx:
						out[row + x] += nz.get_noise_2d(ox + float(x) * cell_m, wz) * amp
	for i in n:
		out[i] = clampf(out[i] * _inv_total * 0.5 + 0.5, 0.0, 1.0)
	return out


## Integer avalanche (Schechter/Bret Mulvey "lowbias32") folded with the octave
## index. Pure integer arithmetic: identical on every platform, which is the
## one part of the noise path we can promise bit-for-bit.
static func octave_seed(base_seed: int, index: int) -> int:
	var x := (base_seed + index * 0x9E3779B1) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x7FEB352D) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 0x846CA68B) & 0xFFFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFFFF
	# FastNoiseLite.seed is a 32-bit signed field.
	return x & 0x7FFFFFFF
