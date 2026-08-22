extends Node
## Persisted user prefs: game root, recent files, view filters, layout.

signal prefs_changed

const PATH := "user://settings.cfg"
const RECENT_MAX := 8
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 2.0
const UI_SCALE_DEFAULT := 1.0
const UI_FONT_SIZE_MIN := 10
const UI_FONT_SIZE_MAX := 24
const UI_FONT_SIZE_DEFAULT := 13
const CAM_SPEED_MIN := 0.25
const CAM_SPEED_MAX := 4.0
const CAM_SPEED_DEFAULT := 1.0
const AUTOSAVE_DEFAULT_S := 30
const AUTOSAVE_CHOICES: Array[int] = [0, 15, 30, 60]
const LAYOUT_SPLIT_BODY_DEFAULT := 252
const LAYOUT_SPLIT_MID_DEFAULT := -280
const LAYOUT_SPLIT_RIGHT_DEFAULT := 180
const LAYOUT_SPLIT_UPPER_DEFAULT := 150
const LAYOUT_SPLIT_LOWER_DEFAULT := 260
const LAYOUT_SAVE_IDLE_S := 1.0
const BRUSH_RADIUS_MIN := 5.0
const BRUSH_RADIUS_MAX := 400.0
const BRUSH_RADIUS_DEFAULT := 40.0
const BRUSH_STRENGTH_DEFAULT := 0.45
const BRUSH_FALLOFF_DEFAULT := 0.65

var game_root: String = ""
var last_map_dir: String = ""
var last_save_dir: String = ""
## User-chosen default for Save / Save As when last_save_dir is empty.
var default_save_dir: String = ""
var walk_mode: bool = false
## Fly / pan multiplier. Clamped CAM_SPEED_MIN..CAM_SPEED_MAX.
var camera_speed_mul: float = CAM_SPEED_DEFAULT
## Flip vertical mouse look (RMB).
var invert_look: bool = false
## ObjectMarkers / team tint uses the colourblind table when true.
var colorblind_teams: bool = false
## Session persist interval in seconds. 0 = off. Allowed 15 / 30 / 60 / 0.
var autosave_interval_s: int = AUTOSAVE_DEFAULT_S
var last_cache_fingerprint: String = ""
## Keyboard scheme id: "godot" (number-row tools) or "gimp". Default godot.
var keymap_scheme: String = "godot"
## Last successfully opened map paths, most recent first, at most RECENT_MAX.
var recent_maps: Array[String] = []
## Viewport filters. Hidden categories are view-only (objects still save).
var view_geysers: bool = true
var view_scrap: bool = true
var view_spawns: bool = true
var view_buildings: bool = true
var view_units: bool = true
var view_props: bool = true
var view_water: bool = true
var view_plants: bool = true
var view_sky: bool = false
## View-menu items that used to be session-only.
var view_ghost_variants: bool = false
var view_balance: bool = false
var view_aipaths: bool = false
## Status-bar view aids (not in the View menu, but the same persistence).
var view_grid: bool = false
var view_slope: bool = false
## View → Labels: class / label billboards above object markers.
var view_labels: bool = false
## World → Fog: draw the map's fog in the viewport. Editor-side visibility
## only — the map's fog distances are saved either way.
##
## Off by default. Game fog closes in at 250 m on a 2560 m map, which is a
## preview of the player's view, not a surface you can sculpt on.
var view_fog: bool = false
## Object snap. 0 = off. Allowed grids 1/5/10/20 m; angles 15/45/90°.
var snap_grid_m: float = 0.0
var snap_angle: float = 0.0
## Sculpt brush, persisted so the editor reopens with the brush you left set.
## ToolState owns the live copies and debounce-writes them here on idle.
var brush_radius_m: float = BRUSH_RADIUS_DEFAULT
var brush_strength: float = BRUSH_STRENGTH_DEFAULT
var brush_falloff: float = BRUSH_FALLOFF_DEFAULT
var brush_shape: String = "circle"
var brush_symmetry: String = "off"
## Generated tip id, or "" for the analytic circle/square.
var brush_mask: String = ""
var brush_rotation_deg: float = 0.0
var brush_random_rotation: bool = false
var brush_spacing: float = 0.0
var brush_spacing_ms: int = 0
var brush_pressure_size: float = 0.0
var brush_pressure_opacity: float = 0.0
var limit_slope: bool = false
var slope_min_deg: float = 0.0
var slope_max_deg: float = 90.0
var slope_feather_deg: float = 5.0
var limit_height: bool = false
var height_min_m: float = 0.0
var height_max_m: float = 409.5
var height_feather_m: float = 2.0
var noise_frequency: float = 0.02
var noise_octaves: int = 3
var noise_amplitude_m: float = 6.0
## Seeds the noise field and the random-rotation stream (C6).
var brush_seed: int = 1
var erode_radius_m: float = 10.0
var erode_slack_m: float = 3.0
var set_height_m: float = 25.0
var angle_deg: float = 15.0
var angle_dir_deg: float = 0.0
## Root window content_scale_factor. Clamped 0.75–2.0. Default 1.0.
var ui_scale: float = UI_SCALE_DEFAULT
## Theme default_font_size. Separate from ui_scale on purpose: scale grows the
## whole chrome, this grows only the type, so small text is fixable on its own.
var ui_font_size: int = UI_FONT_SIZE_DEFAULT
## Split offsets, console, focus mode, panel collapse. Restored at boot.
var layout_split_body: int = LAYOUT_SPLIT_BODY_DEFAULT
var layout_split_mid: int = LAYOUT_SPLIT_MID_DEFAULT
var layout_split_right: int = LAYOUT_SPLIT_RIGHT_DEFAULT
var layout_split_upper: int = LAYOUT_SPLIT_UPPER_DEFAULT
var layout_split_lower: int = LAYOUT_SPLIT_LOWER_DEFAULT
## dock name → {"tabs": [panel names], "current": int}; empty = defaults.
var layout_docks: Dictionary = {}
var console_visible: bool = false
var focus_mode: bool = false
var collapse_palette: bool = false
var collapse_inspector: bool = false
var collapse_features: bool = false
var collapse_findings: bool = false
var collapse_history: bool = false
## True once any map has been recorded in recents (survives prune-to-empty).
var ever_had_recents: bool = false

var _cfg := ConfigFile.new()


func _ready() -> void:
	_load()


func _load() -> void:
	if _cfg.load(PATH) != OK:
		return
	game_root = _cfg.get_value("paths", "game_root", "")
	last_map_dir = _cfg.get_value("paths", "last_map_dir", "")
	last_save_dir = _cfg.get_value("paths", "last_save_dir", "")
	default_save_dir = str(_cfg.get_value("paths", "default_save_dir", ""))
	walk_mode = bool(_cfg.get_value("camera", "walk_mode", false))
	camera_speed_mul = coerce_camera_speed(_cfg.get_value("camera", "speed_mul", CAM_SPEED_DEFAULT))
	invert_look = bool(_cfg.get_value("camera", "invert_look", false))
	colorblind_teams = bool(_cfg.get_value("view", "colorblind_teams", false))
	autosave_interval_s = coerce_autosave_interval(
		_cfg.get_value("editor", "autosave_interval_s", AUTOSAVE_DEFAULT_S)
	)
	last_cache_fingerprint = str(_cfg.get_value("assets", "fingerprint", ""))
	keymap_scheme = _coerce_scheme(str(_cfg.get_value("input", "keymap_scheme", "godot")))
	recent_maps = _coerce_recent(_cfg.get_value("paths", "recent_maps", PackedStringArray()))
	view_geysers = bool(_cfg.get_value("view", "geysers", true))
	view_scrap = bool(_cfg.get_value("view", "scrap", true))
	view_spawns = bool(_cfg.get_value("view", "spawns", true))
	view_buildings = bool(_cfg.get_value("view", "buildings", true))
	view_units = bool(_cfg.get_value("view", "units", true))
	view_props = bool(_cfg.get_value("view", "props", true))
	view_water = bool(_cfg.get_value("view", "water", true))
	view_plants = bool(_cfg.get_value("view", "plants", true))
	view_sky = bool(_cfg.get_value("view", "sky", false))
	view_ghost_variants = bool(_cfg.get_value("view", "ghost_variants", false))
	view_balance = bool(_cfg.get_value("view", "balance", false))
	view_aipaths = bool(_cfg.get_value("view", "aipaths", false))
	view_grid = bool(_cfg.get_value("view", "grid", false))
	view_slope = bool(_cfg.get_value("view", "slope", false))
	view_labels = bool(_cfg.get_value("view", "labels", false))
	view_fog = bool(_cfg.get_value("view", "fog", false))
	_load_brush()
	snap_grid_m = coerce_snap_grid(_cfg.get_value("snap", "grid_m", 0.0))
	snap_angle = coerce_snap_angle(_cfg.get_value("snap", "angle", 0.0))
	ui_scale = coerce_ui_scale(_cfg.get_value("ui", "ui_scale", UI_SCALE_DEFAULT))
	ui_font_size = coerce_ui_font_size(
		_cfg.get_value("ui", "font_size", UI_FONT_SIZE_DEFAULT)
	)
	layout_split_body = coerce_split(
		_cfg.get_value("layout", "split_body", LAYOUT_SPLIT_BODY_DEFAULT),
		LAYOUT_SPLIT_BODY_DEFAULT,
	)
	layout_split_mid = coerce_split(
		_cfg.get_value("layout", "split_mid", LAYOUT_SPLIT_MID_DEFAULT),
		LAYOUT_SPLIT_MID_DEFAULT,
	)
	layout_split_right = coerce_split(
		_cfg.get_value("layout", "split_dock_top", LAYOUT_SPLIT_RIGHT_DEFAULT),
		LAYOUT_SPLIT_RIGHT_DEFAULT,
	)
	layout_split_upper = coerce_split(
		_cfg.get_value("layout", "split_dock_mid", LAYOUT_SPLIT_UPPER_DEFAULT),
		LAYOUT_SPLIT_UPPER_DEFAULT,
	)
	layout_split_lower = coerce_split(
		_cfg.get_value("layout", "split_dock_low", LAYOUT_SPLIT_LOWER_DEFAULT),
		LAYOUT_SPLIT_LOWER_DEFAULT,
	)
	var docks_v: Variant = _cfg.get_value("layout", "docks", {})
	layout_docks = docks_v if typeof(docks_v) == TYPE_DICTIONARY else {}
	console_visible = bool(_cfg.get_value("layout", "console_visible", false))
	focus_mode = bool(_cfg.get_value("layout", "focus_mode", false))
	collapse_palette = bool(_cfg.get_value("layout", "collapse_palette", false))
	collapse_inspector = bool(_cfg.get_value("layout", "collapse_inspector", false))
	collapse_features = bool(_cfg.get_value("layout", "collapse_features", false))
	collapse_findings = bool(_cfg.get_value("layout", "collapse_findings", false))
	collapse_history = bool(_cfg.get_value("layout", "collapse_history", false))
	ever_had_recents = bool(_cfg.get_value("paths", "ever_had_recents", false))
	if not recent_maps.is_empty():
		ever_had_recents = true
	apply_runtime_view()


## Remember a successfully opened map. Deduped, most recent first, capped.
func record_recent_map(path: String) -> void:
	var cleaned := _norm_map_path(path)
	if cleaned.is_empty():
		return
	ever_had_recents = true
	var next: Array[String] = [cleaned]
	for existing in recent_maps:
		if _same_map_path(existing, cleaned):
			continue
		next.append(existing)
		if next.size() >= RECENT_MAX:
			break
	recent_maps = next


func save() -> void:
	_prune_missing_recents()
	_cfg.set_value("paths", "game_root", game_root)
	_cfg.set_value("paths", "last_map_dir", last_map_dir)
	_cfg.set_value("paths", "last_save_dir", last_save_dir)
	_cfg.set_value("paths", "default_save_dir", default_save_dir)
	_cfg.set_value("paths", "recent_maps", PackedStringArray(recent_maps))
	_cfg.set_value("camera", "walk_mode", walk_mode)
	camera_speed_mul = coerce_camera_speed(camera_speed_mul)
	_cfg.set_value("camera", "speed_mul", camera_speed_mul)
	_cfg.set_value("camera", "invert_look", invert_look)
	_cfg.set_value("view", "colorblind_teams", colorblind_teams)
	autosave_interval_s = coerce_autosave_interval(autosave_interval_s)
	_cfg.set_value("editor", "autosave_interval_s", autosave_interval_s)
	_cfg.set_value("assets", "fingerprint", last_cache_fingerprint)
	keymap_scheme = _coerce_scheme(keymap_scheme)
	_cfg.set_value("input", "keymap_scheme", keymap_scheme)
	_cfg.set_value("view", "geysers", view_geysers)
	_cfg.set_value("view", "scrap", view_scrap)
	_cfg.set_value("view", "spawns", view_spawns)
	_cfg.set_value("view", "buildings", view_buildings)
	_cfg.set_value("view", "units", view_units)
	_cfg.set_value("view", "props", view_props)
	_cfg.set_value("view", "water", view_water)
	_cfg.set_value("view", "plants", view_plants)
	_cfg.set_value("view", "sky", view_sky)
	_cfg.set_value("view", "ghost_variants", view_ghost_variants)
	_cfg.set_value("view", "balance", view_balance)
	_cfg.set_value("view", "aipaths", view_aipaths)
	_cfg.set_value("view", "grid", view_grid)
	_cfg.set_value("view", "slope", view_slope)
	_cfg.set_value("view", "labels", view_labels)
	_cfg.set_value("view", "fog", view_fog)
	_save_brush()
	snap_grid_m = coerce_snap_grid(snap_grid_m)
	snap_angle = coerce_snap_angle(snap_angle)
	_cfg.set_value("snap", "grid_m", snap_grid_m)
	_cfg.set_value("snap", "angle", snap_angle)
	ui_scale = coerce_ui_scale(ui_scale)
	_cfg.set_value("ui", "ui_scale", ui_scale)
	ui_font_size = coerce_ui_font_size(ui_font_size)
	_cfg.set_value("ui", "font_size", ui_font_size)
	layout_split_body = coerce_split(layout_split_body, LAYOUT_SPLIT_BODY_DEFAULT)
	layout_split_mid = coerce_split(layout_split_mid, LAYOUT_SPLIT_MID_DEFAULT)
	layout_split_right = coerce_split(layout_split_right, LAYOUT_SPLIT_RIGHT_DEFAULT)
	layout_split_upper = coerce_split(layout_split_upper, LAYOUT_SPLIT_UPPER_DEFAULT)
	layout_split_lower = coerce_split(layout_split_lower, LAYOUT_SPLIT_LOWER_DEFAULT)
	_cfg.set_value("layout", "split_body", layout_split_body)
	_cfg.set_value("layout", "split_mid", layout_split_mid)
	_cfg.set_value("layout", "split_dock_top", layout_split_right)
	_cfg.set_value("layout", "split_dock_mid", layout_split_upper)
	_cfg.set_value("layout", "split_dock_low", layout_split_lower)
	_cfg.set_value("layout", "docks", layout_docks)
	_cfg.set_value("layout", "console_visible", console_visible)
	_cfg.set_value("layout", "focus_mode", focus_mode)
	_cfg.set_value("layout", "collapse_palette", collapse_palette)
	_cfg.set_value("layout", "collapse_inspector", collapse_inspector)
	_cfg.set_value("layout", "collapse_features", collapse_features)
	_cfg.set_value("layout", "collapse_findings", collapse_findings)
	_cfg.set_value("layout", "collapse_history", collapse_history)
	if not recent_maps.is_empty():
		ever_had_recents = true
	_cfg.set_value("paths", "ever_had_recents", ever_had_recents)
	_cfg.save(PATH)


## Brush prefs are read and written as a block: the section is wide, and a
## coerce per field keeps a hand-edited settings.cfg from arming a brush that
## paints the whole map or divides by zero.
func _load_brush() -> void:
	brush_radius_m = clampf(
		_cfg_float("brush", "radius_m", BRUSH_RADIUS_DEFAULT),
		BRUSH_RADIUS_MIN, BRUSH_RADIUS_MAX
	)
	brush_strength = clampf(_cfg_float("brush", "strength", BRUSH_STRENGTH_DEFAULT), 0.0, 1.0)
	brush_falloff = clampf(_cfg_float("brush", "falloff", BRUSH_FALLOFF_DEFAULT), 0.0, 1.0)
	var shp := str(_cfg.get_value("brush", "shape", "circle"))
	brush_shape = "square" if shp == "square" else "circle"
	brush_symmetry = _coerce_symmetry(str(_cfg.get_value("brush", "symmetry", "off")))
	var mask := str(_cfg.get_value("brush", "mask", ""))
	brush_mask = mask if BrushMaskLibrary.has(mask) else ""
	brush_rotation_deg = fposmod(_cfg_float("brush", "rotation_deg", 0.0), 360.0)
	brush_random_rotation = bool(_cfg.get_value("brush", "random_rotation", false))
	brush_spacing = clampf(_cfg_float("brush", "spacing", 0.0), 0.0, 4.0)
	brush_spacing_ms = clampi(int(_cfg_float("brush", "spacing_ms", 0.0)), 0, 2000)
	brush_pressure_size = clampf(_cfg_float("brush", "pressure_size", 0.0), 0.0, 1.0)
	brush_pressure_opacity = clampf(_cfg_float("brush", "pressure_opacity", 0.0), 0.0, 1.0)
	limit_slope = bool(_cfg.get_value("brush", "limit_slope", false))
	slope_min_deg = clampf(_cfg_float("brush", "slope_min_deg", 0.0), 0.0, 90.0)
	slope_max_deg = clampf(_cfg_float("brush", "slope_max_deg", 90.0), 0.0, 90.0)
	slope_feather_deg = clampf(_cfg_float("brush", "slope_feather_deg", 5.0), 0.0, 45.0)
	limit_height = bool(_cfg.get_value("brush", "limit_height", false))
	height_min_m = _cfg_float("brush", "height_min_m", 0.0)
	height_max_m = _cfg_float("brush", "height_max_m", 409.5)
	height_feather_m = maxf(_cfg_float("brush", "height_feather_m", 2.0), 0.0)
	noise_frequency = clampf(_cfg_float("brush", "noise_frequency", 0.02), 0.00001, 1.0)
	noise_octaves = clampi(int(_cfg_float("brush", "noise_octaves", 3.0)), 1, 8)
	noise_amplitude_m = maxf(_cfg_float("brush", "noise_amplitude_m", 6.0), 0.0)
	brush_seed = int(_cfg_float("brush", "seed", 1.0))
	erode_radius_m = clampf(_cfg_float("brush", "erode_radius_m", 10.0), 5.0, 20.0)
	erode_slack_m = maxf(_cfg_float("brush", "erode_slack_m", 3.0), 0.0)
	set_height_m = _cfg_float("brush", "set_height_m", 25.0)
	angle_deg = clampf(_cfg_float("brush", "angle_deg", 15.0), -89.0, 89.0)
	angle_dir_deg = fposmod(_cfg_float("brush", "angle_dir_deg", 0.0), 360.0)


func _save_brush() -> void:
	_cfg.set_value("brush", "radius_m", brush_radius_m)
	_cfg.set_value("brush", "strength", brush_strength)
	_cfg.set_value("brush", "falloff", brush_falloff)
	_cfg.set_value("brush", "shape", brush_shape)
	_cfg.set_value("brush", "symmetry", brush_symmetry)
	_cfg.set_value("brush", "mask", brush_mask)
	_cfg.set_value("brush", "rotation_deg", brush_rotation_deg)
	_cfg.set_value("brush", "random_rotation", brush_random_rotation)
	_cfg.set_value("brush", "spacing", brush_spacing)
	_cfg.set_value("brush", "spacing_ms", brush_spacing_ms)
	_cfg.set_value("brush", "pressure_size", brush_pressure_size)
	_cfg.set_value("brush", "pressure_opacity", brush_pressure_opacity)
	_cfg.set_value("brush", "limit_slope", limit_slope)
	_cfg.set_value("brush", "slope_min_deg", slope_min_deg)
	_cfg.set_value("brush", "slope_max_deg", slope_max_deg)
	_cfg.set_value("brush", "slope_feather_deg", slope_feather_deg)
	_cfg.set_value("brush", "limit_height", limit_height)
	_cfg.set_value("brush", "height_min_m", height_min_m)
	_cfg.set_value("brush", "height_max_m", height_max_m)
	_cfg.set_value("brush", "height_feather_m", height_feather_m)
	_cfg.set_value("brush", "noise_frequency", noise_frequency)
	_cfg.set_value("brush", "noise_octaves", noise_octaves)
	_cfg.set_value("brush", "noise_amplitude_m", noise_amplitude_m)
	_cfg.set_value("brush", "seed", brush_seed)
	_cfg.set_value("brush", "erode_radius_m", erode_radius_m)
	_cfg.set_value("brush", "erode_slack_m", erode_slack_m)
	_cfg.set_value("brush", "set_height_m", set_height_m)
	_cfg.set_value("brush", "angle_deg", angle_deg)
	_cfg.set_value("brush", "angle_dir_deg", angle_dir_deg)


## Duplicated rather than delegated to ToolState.normalize_symmetry: Settings
## is the first autoload, so ToolState does not exist yet when this runs.
func _coerce_symmetry(raw: String) -> String:
	match raw:
		"mirror_x", "mirror_z", "rot180", "quad":
			return raw
		_:
			return "off"


func _cfg_float(section: String, key: String, default: float) -> float:
	var raw: Variant = _cfg.get_value(section, key, default)
	match typeof(raw):
		TYPE_FLOAT, TYPE_INT, TYPE_BOOL:
			var v := float(raw)
			return v if is_finite(v) else default
		TYPE_STRING:
			var t := str(raw).strip_edges()
			return float(t) if t.is_valid_float() else default
		_:
			return default


func apply_runtime_view() -> void:
	ObjectMarkers.ghost_other_variants = view_ghost_variants
	BalanceOverlay.enabled = view_balance
	AiPathOverlay.enabled = view_aipaths


func notify_prefs() -> void:
	prefs_changed.emit()


func apply_ui_scale(win: Window = null) -> void:
	ui_scale = coerce_ui_scale(ui_scale)
	var target := win
	if target == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			target = tree.root
	if target != null:
		target.content_scale_factor = ui_scale


func effective_save_dir() -> String:
	if not last_save_dir.is_empty():
		return last_save_dir
	return default_save_dir


func is_first_run() -> bool:
	return (not ever_had_recents) and recent_maps.is_empty()


func layout_dict() -> Dictionary:
	return {
		"split_body": layout_split_body,
		"split_mid": layout_split_mid,
		"split_right": layout_split_right,
		"split_upper": layout_split_upper,
		"split_lower": layout_split_lower,
		"console_visible": console_visible,
		"focus_mode": focus_mode,
		"collapse_palette": collapse_palette,
		"collapse_inspector": collapse_inspector,
		"collapse_features": collapse_features,
		"collapse_findings": collapse_findings,
		"collapse_history": collapse_history,
		"view_grid": view_grid,
		"view_slope": view_slope,
		"view_ghost_variants": view_ghost_variants,
		"view_balance": view_balance,
		"view_aipaths": view_aipaths,
	}


func apply_layout_dict(data: Dictionary) -> void:
	layout_split_body = coerce_split(data.get("split_body", layout_split_body), LAYOUT_SPLIT_BODY_DEFAULT)
	layout_split_mid = coerce_split(data.get("split_mid", layout_split_mid), LAYOUT_SPLIT_MID_DEFAULT)
	layout_split_right = coerce_split(data.get("split_right", layout_split_right), LAYOUT_SPLIT_RIGHT_DEFAULT)
	layout_split_upper = coerce_split(data.get("split_upper", layout_split_upper), LAYOUT_SPLIT_UPPER_DEFAULT)
	layout_split_lower = coerce_split(data.get("split_lower", layout_split_lower), LAYOUT_SPLIT_LOWER_DEFAULT)
	console_visible = bool(data.get("console_visible", console_visible))
	focus_mode = bool(data.get("focus_mode", focus_mode))
	collapse_palette = bool(data.get("collapse_palette", collapse_palette))
	collapse_inspector = bool(data.get("collapse_inspector", collapse_inspector))
	collapse_features = bool(data.get("collapse_features", collapse_features))
	collapse_findings = bool(data.get("collapse_findings", collapse_findings))
	collapse_history = bool(data.get("collapse_history", collapse_history))
	view_grid = bool(data.get("view_grid", view_grid))
	view_slope = bool(data.get("view_slope", view_slope))
	view_ghost_variants = bool(data.get("view_ghost_variants", view_ghost_variants))
	view_balance = bool(data.get("view_balance", view_balance))
	view_aipaths = bool(data.get("view_aipaths", view_aipaths))
	apply_runtime_view()


func coerce_split(raw: Variant, default: int) -> int:
	match typeof(raw):
		TYPE_INT:
			return int(raw)
		TYPE_FLOAT:
			if not is_finite(float(raw)):
				return default
			return int(raw)
		TYPE_STRING:
			var s := str(raw).strip_edges()
			if s.is_valid_int():
				return int(s)
			if s.is_valid_float():
				return int(float(s))
			return default
		_:
			return default


func coerce_snap_grid(raw: Variant) -> float:
	return SelectionGizmo.coerce_snap_grid(raw)


func coerce_snap_angle(raw: Variant) -> float:
	return SelectionGizmo.coerce_snap_angle(raw)


func coerce_camera_speed(raw: Variant) -> float:
	var v := CAM_SPEED_DEFAULT
	match typeof(raw):
		TYPE_FLOAT, TYPE_INT:
			v = float(raw)
		TYPE_STRING:
			if str(raw).is_valid_float():
				v = float(str(raw))
		_:
			return CAM_SPEED_DEFAULT
	if not is_finite(v):
		return CAM_SPEED_DEFAULT
	return clampf(v, CAM_SPEED_MIN, CAM_SPEED_MAX)


func coerce_autosave_interval(raw: Variant) -> int:
	var v := AUTOSAVE_DEFAULT_S
	match typeof(raw):
		TYPE_INT:
			v = int(raw)
		TYPE_FLOAT:
			if not is_finite(float(raw)):
				return AUTOSAVE_DEFAULT_S
			v = int(raw)
		TYPE_STRING:
			var s := str(raw).strip_edges().to_lower()
			if s == "off" or s == "none":
				return 0
			if s.ends_with("s"):
				s = s.substr(0, s.length() - 1)
			if s.is_valid_int():
				v = int(s)
			elif s.is_valid_float():
				v = int(float(s))
			else:
				return AUTOSAVE_DEFAULT_S
		_:
			return AUTOSAVE_DEFAULT_S
	if v in AUTOSAVE_CHOICES:
		return v
	return AUTOSAVE_DEFAULT_S


func coerce_ui_scale(raw: Variant) -> float:
	var v := UI_SCALE_DEFAULT
	match typeof(raw):
		TYPE_FLOAT, TYPE_INT:
			v = float(raw)
		TYPE_STRING:
			if str(raw).is_valid_float():
				v = float(str(raw))
		_:
			return UI_SCALE_DEFAULT
	if not is_finite(v):
		return UI_SCALE_DEFAULT
	return clampf(v, UI_SCALE_MIN, UI_SCALE_MAX)


func coerce_ui_font_size(raw: Variant) -> int:
	var v := UI_FONT_SIZE_DEFAULT
	match typeof(raw):
		TYPE_INT:
			v = int(raw)
		TYPE_FLOAT:
			if not is_finite(float(raw)):
				return UI_FONT_SIZE_DEFAULT
			v = int(round(float(raw)))
		TYPE_STRING:
			var s := str(raw).strip_edges()
			if s.is_valid_int():
				v = int(s)
			elif s.is_valid_float():
				v = int(round(float(s)))
			else:
				return UI_FONT_SIZE_DEFAULT
		_:
			return UI_FONT_SIZE_DEFAULT
	return clampi(v, UI_FONT_SIZE_MIN, UI_FONT_SIZE_MAX)


func view_flag(key: String) -> bool:
	match key:
		"geysers":
			return view_geysers
		"scrap":
			return view_scrap
		"spawns":
			return view_spawns
		"buildings":
			return view_buildings
		"units":
			return view_units
		"props":
			return view_props
		"water":
			return view_water
		"plants":
			return view_plants
		"sky":
			return view_sky
		_:
			return true


func view_group_visible(group: String) -> bool:
	return view_flag(group)


func set_view_group(group: String, on: bool) -> void:
	match group:
		"geysers":
			view_geysers = on
		"scrap":
			view_scrap = on
		"spawns":
			view_spawns = on
		"buildings":
			view_buildings = on
		"units":
			view_units = on
		"props":
			view_props = on
		"water":
			view_water = on
		"plants":
			view_plants = on
		"sky":
			view_sky = on


func _prune_missing_recents() -> void:
	var kept: Array[String] = []
	for path in recent_maps:
		if FileAccess.file_exists(path):
			kept.append(path)
	recent_maps = kept


func _coerce_recent(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is PackedStringArray:
		for path in raw:
			var cleaned := _norm_map_path(str(path))
			if cleaned.is_empty():
				continue
			var dup := false
			for existing in out:
				if _same_map_path(existing, cleaned):
					dup = true
					break
			if dup:
				continue
			out.append(cleaned)
			if out.size() >= RECENT_MAX:
				break
	elif raw is Array:
		for path in raw:
			var cleaned := _norm_map_path(str(path))
			if cleaned.is_empty():
				continue
			var dup := false
			for existing in out:
				if _same_map_path(existing, cleaned):
					dup = true
					break
			if dup:
				continue
			out.append(cleaned)
			if out.size() >= RECENT_MAX:
				break
	return out


func _coerce_scheme(name: String) -> String:
	var cleaned := name.strip_edges().to_lower()
	if cleaned == "gimp":
		return "gimp"
	return "godot"


func _norm_map_path(path: String) -> String:
	return path.strip_edges().simplify_path()


func _same_map_path(a: String, b: String) -> bool:
	if OS.get_name() == "Windows":
		return a.to_lower() == b.to_lower()
	return a == b
