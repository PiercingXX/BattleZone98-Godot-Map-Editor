extends RefCounted
class_name ScatterSpecies
## One scatter species: how it looks and where it is allowed to grow.
##
## Rules are read at generation time only — none of this reaches game bytes.
## The species SLOT is what the painted mask stores, so a map's species order
## is load-bearing: reordering the list repaints every cell that referenced a
## moved slot. Slots are fixed at ScatterMask.SLOTS; a species list shorter
## than that simply leaves the high slots unpaintable.

const DEFAULT_SPACING_M := 12.0
const MIN_SPACING_M := 2.0
## Half a scatter chunk. Cross-chunk spacing is enforced against the eight
## neighbours only, which stays exact while a disc cannot reach past them.
const MAX_SPACING_M := 80.0
## Points per hectare a Poisson-disc set of radius r settles at: Bridson's
## dart throwing fills to roughly 0.7 / r^2 per m^2 in practice.
const PACK_PER_HA := 7000.0

var name: String = "plants"
## Poisson-disc radius: no two instances of this species land closer.
var spacing_m: float = DEFAULT_SPACING_M
var slope_min_deg: float = 0.0
var slope_max_deg: float = 12.0
var height_min_m: float = -10000.0
var height_max_m: float = 10000.0
## Material slots (tile word >> 12) this species refuses to grow on.
var exclude_slots: PackedInt32Array = PackedInt32Array()
var blade_h_m: float = 4.0
var blade_w_m: float = 2.2
## Per-instance size spread, +/- this fraction. 0.3 matches the legacy field.
var scale_jitter: float = 0.3


static func make(p_name: String, p_spacing_m: float = DEFAULT_SPACING_M) -> ScatterSpecies:
	var sp := ScatterSpecies.new()
	sp.name = p_name
	sp.spacing_m = clamp_spacing(p_spacing_m)
	return sp


static func clamp_spacing(v: float) -> float:
	return clampf(v, MIN_SPACING_M, MAX_SPACING_M)


## Poisson radius that yields roughly `per_ha` instances per hectare.
static func spacing_for_density(per_ha: float) -> float:
	if per_ha <= 0.0:
		return MAX_SPACING_M
	return clamp_spacing(sqrt(PACK_PER_HA / per_ha))


static func density_for_spacing(m: float) -> float:
	var r := clamp_spacing(m)
	return PACK_PER_HA / (r * r)


func density_per_ha() -> float:
	return density_for_spacing(spacing_m)


func radius_m() -> float:
	return clamp_spacing(spacing_m)


func allows_slope(deg: float) -> bool:
	return deg >= slope_min_deg and deg <= slope_max_deg


func allows_height(m: float) -> bool:
	return m >= height_min_m and m <= height_max_m


func allows_slot(slot: int) -> bool:
	for s in exclude_slots:
		if int(s) == slot:
			return false
	return true


## Preview tint. Derived from the slot so a species keeps its colour whatever
## it is called, and so two species never share one by accident.
static func tint(slot: int) -> Color:
	var h := fposmod(float(maxi(slot, 0)) * 0.6180339887, 1.0)
	return Color.from_hsv(h, 0.55, 0.72)


func to_dict() -> Dictionary:
	var slots: Array = []
	for s in exclude_slots:
		slots.append(int(s))
	return {
		"name": name,
		"spacing_m": spacing_m,
		"slope_min_deg": slope_min_deg,
		"slope_max_deg": slope_max_deg,
		"height_min_m": height_min_m,
		"height_max_m": height_max_m,
		"exclude_slots": slots,
		"blade_h_m": blade_h_m,
		"blade_w_m": blade_w_m,
		"scale_jitter": scale_jitter,
	}


static func from_dict(d: Dictionary) -> ScatterSpecies:
	var sp := ScatterSpecies.new()
	sp.name = str(d.get("name", "plants"))
	sp.spacing_m = clamp_spacing(float(d.get("spacing_m", DEFAULT_SPACING_M)))
	sp.slope_min_deg = float(d.get("slope_min_deg", 0.0))
	sp.slope_max_deg = float(d.get("slope_max_deg", 12.0))
	sp.height_min_m = float(d.get("height_min_m", -10000.0))
	sp.height_max_m = float(d.get("height_max_m", 10000.0))
	sp.blade_h_m = float(d.get("blade_h_m", 4.0))
	sp.blade_w_m = float(d.get("blade_w_m", 2.2))
	sp.scale_jitter = clampf(float(d.get("scale_jitter", 0.3)), 0.0, 0.95)
	var slots: Variant = d.get("exclude_slots", [])
	if typeof(slots) == TYPE_ARRAY:
		var out := PackedInt32Array()
		for s in (slots as Array):
			var v := int(s)
			if v >= 0 and v < 16 and not out.has(v):
				out.append(v)
		sp.exclude_slots = out
	return sp


static func list_to(species: Array) -> Array:
	var out: Array = []
	for sp in species:
		if sp is ScatterSpecies:
			out.append((sp as ScatterSpecies).to_dict())
	return out


static func list_from(raw: Variant) -> Array[ScatterSpecies]:
	var out: Array[ScatterSpecies] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for d in (raw as Array):
		if typeof(d) == TYPE_DICTIONARY:
			out.append(from_dict(d))
	return out
