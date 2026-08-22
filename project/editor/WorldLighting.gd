extends RefCounted
class_name WorldLighting
## The `.trn` `[NormalView]` block as the editor understands it: the `Time=`
## sun clock and the fog distances (F3 §1).
##
## Pure functions, no scene access, so the mapping from a TRN value to a light
## direction is testable headlessly and lives in one place.

## `Time=900` — 09:00, the value stock Elysium ships and the editor's default.
const TIME_DEFAULT := 900
const MINUTES_PER_DAY := 1440

## Fog distances are metres and the UI clamps to this range.
const FOG_MIN_M := 0.0
const FOG_MAX_M := 1000.0
## VisibilityRange is always FogEnd + this. The engine culls at VisibilityRange,
## so anything less would pop terrain in front of the fog wall.
const VISIBILITY_MARGIN_M := 50.0

const FOG_START_DEFAULT := 80.0
const FOG_END_DEFAULT := 250.0
const FOG_BREAK_DEFAULT := 40.0

## Sunrise / sunset in minutes. The arc runs east at dawn, overhead at noon,
## west at dusk — the only reading of a bare "Time" the format offers.
const DAWN_MIN := 360   # 06:00
const DUSK_MIN := 1080  # 18:00

## Below this the sun is under the horizon; the editor pins it here and dims
## it instead, so a night-time map is still something you can sculpt in.
const MIN_ELEVATION_DEG := 6.0
const DAY_ENERGY := 1.15
const NIGHT_ENERGY := 0.45


static func minutes_from_time(value: Variant) -> int:
	## `900` / `"900"` / `"0900"` → 540. Out-of-range minutes wrap the hour,
	## which is what a hand-edited `Time = 1290` means.
	var raw: int = 0
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		var text: String = str(value).strip_edges()
		if text.is_empty():
			return minutes_from_time(TIME_DEFAULT)
		raw = int(text.to_float())
	else:
		raw = int(value)
	var minutes: int = (raw / 100) * 60 + (raw % 100)
	return posmod(minutes, MINUTES_PER_DAY)


static func time_from_minutes(minutes: int) -> int:
	var m: int = posmod(minutes, MINUTES_PER_DAY)
	return (m / 60) * 100 + (m % 60)


static func format_clock(minutes: int) -> String:
	var m: int = posmod(minutes, MINUTES_PER_DAY)
	return "%02d:%02d" % [m / 60, m % 60]


static func sun_elevation_deg(minutes: int) -> float:
	## −90° at midnight, 0° at dawn, +90° at noon, 0° at dusk. Unclamped: this
	## is the astronomical value, not the one the viewport light uses.
	var span: float = float(DUSK_MIN - DAWN_MIN)
	var t: float = (float(posmod(minutes, MINUTES_PER_DAY)) - float(DAWN_MIN)) / span
	return rad_to_deg(asin(clampf(sin(t * PI), -1.0, 1.0)))


static func sun_to_light_direction(minutes: int) -> Vector3:
	## Unit vector FROM the sun toward the ground — what a DirectionalLight3D
	## points along. East is +X, so dawn light travels west (−X).
	var span: float = float(DUSK_MIN - DAWN_MIN)
	var t: float = (float(posmod(minutes, MINUTES_PER_DAY)) - float(DAWN_MIN)) / span
	var theta: float = t * PI
	var to_sun := Vector3(cos(theta), sin(theta), 0.0)
	var floor_y: float = sin(deg_to_rad(MIN_ELEVATION_DEG))
	if to_sun.y < floor_y:
		# Pinned to the horizon so night keeps a usable key light. The azimuth
		# still tracks the clock, so a 21:00 map is lit from the west.
		var flat := Vector2(to_sun.x, to_sun.z)
		if flat.length() < 0.0001:
			flat = Vector2(1.0, 0.0)
		flat = flat.normalized() * cos(deg_to_rad(MIN_ELEVATION_DEG))
		to_sun = Vector3(flat.x, floor_y, flat.y)
	return -to_sun.normalized()


static func sun_energy(minutes: int) -> float:
	var span: float = float(DUSK_MIN - DAWN_MIN)
	var t: float = (float(posmod(minutes, MINUTES_PER_DAY)) - float(DAWN_MIN)) / span
	var height: float = sin(t * PI)
	if height <= 0.0:
		return NIGHT_ENERGY
	return lerpf(NIGHT_ENERGY, DAY_ENERGY, clampf(height * 1.6, 0.0, 1.0))


static func clamp_fog(start_m: float, end_m: float) -> Vector2:
	## FogStart may never exceed FogEnd; both stay inside 0..1000 m.
	var e: float = clampf(end_m, FOG_MIN_M, FOG_MAX_M)
	var s: float = clampf(start_m, FOG_MIN_M, FOG_MAX_M)
	return Vector2(minf(s, e), e)


static func visibility_range(end_m: float) -> float:
	return clampf(end_m, FOG_MIN_M, FOG_MAX_M) + VISIBILITY_MARGIN_M


static func defaults() -> Dictionary:
	return {
		"time": TIME_DEFAULT,
		"fog_enabled": true,
		"fog_start_m": FOG_START_DEFAULT,
		"fog_end_m": FOG_END_DEFAULT,
		"fog_break_m": FOG_BREAK_DEFAULT,
		"fog_color": "#8a97a8",
	}
