extends RefCounted
class_name GenParams
## Every knob the procedural terrain generator reads, in one object.
##
## Determinism (C6) is a property of this object: the same GenParams and the
## same output grid must yield the same PackedInt32Array on every run. Nothing
## here is seeded from the clock, and nothing downstream iterates a Dictionary
## to produce output — the only Dictionary use is to_dict/from_dict, which is
## serialisation, not generation.
##
## Terrain is authored in metres and quantised exactly once, at the end, into
## the 13-bit raw field: 0.1 m per unit (C3), clamped to 1..4095 (C2).

## Octave shaping. FBM is plain fractal Brownian motion; RIDGED inverts and
## squares each octave for sharp crests; BILLOW takes the absolute value for
## rounded lumps.
enum {
	MODE_FBM = 0,
	MODE_RIDGED = 1,
	MODE_BILLOW = 2,
}

## Large-scale closed-form landform mixed in over the noise. Circular shapes
## use metres, not normalised UV, so a non-square map still gets a circle.
enum {
	SHAPE_NONE = 0,
	SHAPE_CRATER = 1,
	SHAPE_BASIN = 2,
	SHAPE_VALLEY = 3,
	SHAPE_PLATEAU = 4,
	SHAPE_BORDER = 5,
}

const OCTAVES_MAX := 10
const RELIEF_M_MAX := 409.0
const DROPLETS_MAX := 400000

## Preset that produced these values, for the UI title and the log line. Not
## read by the generator.
var preset: String = ""

var seed: int = 1
## World-space origin of the noise lattice, in metres. Panning the same seed.
var offset_x_m: float = 0.0
var offset_z_m: float = 0.0
## Feature size of the first octave, in metres. frequency = 1 / scale_m.
var scale_m: float = 640.0
## Convenience trim on `gain`; 0.5 is neutral, 1.0 doubles the detail weight.
## Kept separate so a preset can expose one "more detail" slider without the
## user having to reason about persistence.
var roughness: float = 0.5
var octaves: int = 5
var lacunarity: float = 2.0
## Per-octave amplitude multiplier (persistence).
var gain: float = 0.5
var noise_mode: int = MODE_FBM

## Remap LUT over the normalised 0..1 noise, uniformly sampled. This is where
## plateaus and terraces come from — see RemapCurve.
var curve: PackedFloat64Array = PackedFloat64Array()

var shape: int = SHAPE_NONE
## Signed amplitude of `shape`, in metres. The shape field is -1..1.
var shape_m: float = 0.0

## Flat-plane height the noise sits on, in raw units (1000 = 100 m).
var base_raw: int = 1000
## Peak-to-trough amplitude of the shaped noise, in metres.
var relief_m: float = 60.0

## Thermal erosion. steps = iterations, weight = fraction of the excess moved
## per iteration (<= 0.5 or it oscillates), slope = talus angle in m/m,
## dilation = 0 sends everything to the steepest neighbour, 1 spreads it over
## every neighbour that is below the talus line.
var erosion_steps: int = 0
var erosion_weight: float = 0.4
var erosion_slope: float = 0.30
var erosion_dilation: float = 0.5

## Droplet hydraulic erosion. 0 droplets disables the whole stage; it is the
## expensive one. Droplet count is scaled with the cell count so a preview and
## a full-resolution run carve comparable networks.
var hydro_droplets: int = 0
var hydro_lifetime: int = 24
var hydro_inertia: float = 0.06
var hydro_capacity: float = 3.0
var hydro_erode: float = 0.25
var hydro_deposit: float = 0.25


func _init() -> void:
	curve = RemapCurve.linear()


func copy() -> GenParams:
	var out := GenParams.new()
	out.from_dict(to_dict())
	return out


func to_dict() -> Dictionary:
	return {
		"preset": preset,
		"seed": seed,
		"offset_x_m": offset_x_m,
		"offset_z_m": offset_z_m,
		"scale_m": scale_m,
		"roughness": roughness,
		"octaves": octaves,
		"lacunarity": lacunarity,
		"gain": gain,
		"noise_mode": noise_mode,
		"curve": Array(curve),
		"shape": shape,
		"shape_m": shape_m,
		"base_raw": base_raw,
		"relief_m": relief_m,
		"erosion_steps": erosion_steps,
		"erosion_weight": erosion_weight,
		"erosion_slope": erosion_slope,
		"erosion_dilation": erosion_dilation,
		"hydro_droplets": hydro_droplets,
		"hydro_lifetime": hydro_lifetime,
		"hydro_inertia": hydro_inertia,
		"hydro_capacity": hydro_capacity,
		"hydro_erode": hydro_erode,
		"hydro_deposit": hydro_deposit,
	}


func from_dict(data: Dictionary) -> void:
	preset = str(data.get("preset", preset))
	seed = int(data.get("seed", seed))
	offset_x_m = float(data.get("offset_x_m", offset_x_m))
	offset_z_m = float(data.get("offset_z_m", offset_z_m))
	scale_m = float(data.get("scale_m", scale_m))
	roughness = float(data.get("roughness", roughness))
	octaves = int(data.get("octaves", octaves))
	lacunarity = float(data.get("lacunarity", lacunarity))
	gain = float(data.get("gain", gain))
	noise_mode = int(data.get("noise_mode", noise_mode))
	if data.has("curve"):
		var lut := PackedFloat64Array()
		for v in data["curve"]:
			lut.append(float(v))
		if lut.size() >= 2:
			curve = lut
	shape = int(data.get("shape", shape))
	shape_m = float(data.get("shape_m", shape_m))
	base_raw = int(data.get("base_raw", base_raw))
	relief_m = float(data.get("relief_m", relief_m))
	erosion_steps = int(data.get("erosion_steps", erosion_steps))
	erosion_weight = float(data.get("erosion_weight", erosion_weight))
	erosion_slope = float(data.get("erosion_slope", erosion_slope))
	erosion_dilation = float(data.get("erosion_dilation", erosion_dilation))
	hydro_droplets = int(data.get("hydro_droplets", hydro_droplets))
	hydro_lifetime = int(data.get("hydro_lifetime", hydro_lifetime))
	hydro_inertia = float(data.get("hydro_inertia", hydro_inertia))
	hydro_capacity = float(data.get("hydro_capacity", hydro_capacity))
	hydro_erode = float(data.get("hydro_erode", hydro_erode))
	hydro_deposit = float(data.get("hydro_deposit", hydro_deposit))


## "" when the parameters are usable, otherwise a message fit for the log.
func validate() -> String:
	if octaves < 1 or octaves > OCTAVES_MAX:
		return "octaves must be 1..%d (got %d)" % [OCTAVES_MAX, octaves]
	if scale_m < 20.0:
		return "scale must be at least 20 m (got %.1f)" % scale_m
	if lacunarity < 1.05 or lacunarity > 4.0:
		return "lacunarity must be 1.05..4.0 (got %.3f)" % lacunarity
	if gain < 0.05 or gain > 0.95:
		return "gain must be 0.05..0.95 (got %.3f)" % gain
	if roughness < 0.0 or roughness > 1.0:
		return "roughness must be 0.0..1.0 (got %.3f)" % roughness
	if noise_mode < MODE_FBM or noise_mode > MODE_BILLOW:
		return "unknown noise mode %d" % noise_mode
	if shape < SHAPE_NONE or shape > SHAPE_BORDER:
		return "unknown shape %d" % shape
	if curve.size() < 2:
		return "remap curve needs at least 2 samples (got %d)" % curve.size()
	if base_raw < 1 or base_raw > 4095:
		return "base height must be raw 1..4095 (got %d)" % base_raw
	if relief_m < 0.0 or relief_m > RELIEF_M_MAX:
		return "relief must be 0..%.0f m (got %.1f)" % [RELIEF_M_MAX, relief_m]
	if absf(shape_m) > RELIEF_M_MAX:
		return "shape amplitude must be within +-%.0f m" % RELIEF_M_MAX
	if erosion_steps < 0 or erosion_steps > 64:
		return "erosion steps must be 0..64 (got %d)" % erosion_steps
	if erosion_weight <= 0.0 or erosion_weight > 0.5:
		return "erosion weight must be 0..0.5 (got %.3f)" % erosion_weight
	if erosion_slope < 0.02 or erosion_slope > 2.0:
		return "erosion slope must be 0.02..2.0 m/m (got %.3f)" % erosion_slope
	if erosion_dilation < 0.0 or erosion_dilation > 1.0:
		return "erosion dilation must be 0.0..1.0 (got %.3f)" % erosion_dilation
	if hydro_droplets < 0 or hydro_droplets > DROPLETS_MAX:
		return "droplets must be 0..%d (got %d)" % [DROPLETS_MAX, hydro_droplets]
	if hydro_lifetime < 1 or hydro_lifetime > 128:
		return "droplet lifetime must be 1..128 (got %d)" % hydro_lifetime
	if hydro_inertia < 0.0 or hydro_inertia >= 1.0:
		return "droplet inertia must be 0.0..0.999 (got %.3f)" % hydro_inertia
	if hydro_capacity <= 0.0 or hydro_capacity > 64.0:
		return "droplet capacity must be 0..64 (got %.3f)" % hydro_capacity
	if hydro_erode < 0.0 or hydro_erode > 1.0:
		return "droplet erode rate must be 0.0..1.0 (got %.3f)" % hydro_erode
	if hydro_deposit < 0.0 or hydro_deposit > 1.0:
		return "droplet deposit rate must be 0.0..1.0 (got %.3f)" % hydro_deposit
	return ""


## Stable identity of the parameter set. Two GenParams with the same signature
## generate the same field at the same resolution, so a preview cache can key
## on it. Floats are printed at fixed precision so the string never depends on
## the platform's shortest-round-trip float formatting.
func signature() -> String:
	var parts := PackedStringArray([
		"s%d" % seed,
		"o%.4f,%.4f" % [offset_x_m, offset_z_m],
		"sc%.4f" % scale_m,
		"r%.4f" % roughness,
		"oc%d" % octaves,
		"la%.4f" % lacunarity,
		"g%.4f" % gain,
		"m%d" % noise_mode,
		"sh%d/%.4f" % [shape, shape_m],
		"b%d" % base_raw,
		"re%.4f" % relief_m,
		"e%d/%.4f/%.4f/%.4f" % [
			erosion_steps, erosion_weight, erosion_slope, erosion_dilation
		],
		"h%d/%d/%.4f/%.4f/%.4f/%.4f" % [
			hydro_droplets, hydro_lifetime, hydro_inertia, hydro_capacity,
			hydro_erode, hydro_deposit
		],
	])
	var curve_sig := PackedStringArray()
	for i in curve.size():
		curve_sig.append("%.4f" % curve[i])
	parts.append("c" + ",".join(curve_sig))
	return "|".join(parts)
