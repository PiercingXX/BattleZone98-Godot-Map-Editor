extends RefCounted
class_name GenPresets
## Named starting points, tuned for Battlezone rather than for landscape art.
##
## The rule every preset obeys: a map is buildable pockets joined by navigable
## slopes. Plain fBm fails that badly — over a 5 m cell, tan 5 degrees is a
## 0.44 m step, so ordinary rolling noise is buildable almost nowhere. What
## makes these work is the remap curve: a plateau or terrace LUT has zero
## gradient over most of its range, so the flat ground is genuinely flat and
## the steepness is concentrated into ramps and walls you can route around.
##
## The measured buildable fractions for these presets on a 2560 m map are
## pinned by tests/gd/test_generate_presets.gd — if a preset drifts below the
## floor there, it stopped being a Battlezone preset.

const NAMES: PackedStringArray = ["mesa", "crater", "highlands", "canyon"]

const DEFAULT := "highlands"


static func names() -> PackedStringArray:
	return NAMES


static func has(name: String) -> bool:
	return NAMES.has(name)


static func title(name: String) -> String:
	match name:
		"mesa":
			return "Mesa plateaus"
		"crater":
			return "Crater basin"
		"highlands":
			return "Rolling highlands"
		"canyon":
			return "Ridged canyon"
	return name


static func describe(name: String) -> String:
	match name:
		"mesa":
			return "Stacked flat benches joined by short ramps. The most base-friendly preset."
		"crater":
			return "Flat arena floor inside a raised rim, with a broken outer apron."
		"highlands":
			return "Two gently rolling tiers with wide connecting slopes. Good all-rounder."
		"canyon":
			return "Broad buildable tops cut by narrow drivable canyons."
	return ""


## A preset is only a GenParams factory — the dialog edits the result freely.
static func make(name: String, seed_value: int = 1) -> GenParams:
	var p := GenParams.new()
	p.preset = name
	p.seed = seed_value
	match name:
		"mesa":
			p.scale_m = 900.0
			p.octaves = 5
			p.lacunarity = 2.0
			p.gain = 0.48
			p.roughness = 0.45
			p.noise_mode = GenParams.MODE_FBM
			p.curve = RemapCurve.terrace(3, 0.78)
			p.base_raw = 850
			p.relief_m = 78.0
			p.shape = GenParams.SHAPE_NONE
			p.shape_m = 0.0
			p.erosion_steps = 6
			p.erosion_weight = 0.35
			p.erosion_slope = 0.34
			p.erosion_dilation = 0.65
		"crater":
			p.scale_m = 620.0
			p.octaves = 4
			p.lacunarity = 2.1
			p.gain = 0.45
			p.roughness = 0.5
			p.noise_mode = GenParams.MODE_FBM
			p.curve = RemapCurve.plateau(0.34, 0.72)
			p.base_raw = 900
			p.relief_m = 20.0
			p.shape = GenParams.SHAPE_CRATER
			p.shape_m = 88.0
			p.erosion_steps = 8
			p.erosion_weight = 0.4
			p.erosion_slope = 0.28
			p.erosion_dilation = 0.7
		"highlands":
			p.scale_m = 820.0
			p.octaves = 5
			p.lacunarity = 2.0
			p.gain = 0.5
			p.roughness = 0.5
			p.noise_mode = GenParams.MODE_FBM
			p.curve = RemapCurve.plateau(0.36, 0.68)
			p.base_raw = 900
			p.relief_m = 52.0
			p.shape = GenParams.SHAPE_NONE
			p.shape_m = 0.0
			p.erosion_steps = 8
			p.erosion_weight = 0.4
			p.erosion_slope = 0.18
			p.erosion_dilation = 0.8
		"canyon":
			p.scale_m = 1100.0
			p.octaves = 5
			p.lacunarity = 2.15
			p.gain = 0.5
			p.roughness = 0.55
			p.noise_mode = GenParams.MODE_RIDGED
			p.curve = RemapCurve.plateau(0.32, 0.42)
			p.base_raw = 820
			p.relief_m = 68.0
			p.shape = GenParams.SHAPE_NONE
			p.shape_m = 0.0
			p.erosion_steps = 6
			p.erosion_weight = 0.42
			p.erosion_slope = 0.55
			p.erosion_dilation = 0.45
		_:
			p.preset = ""
	return p
