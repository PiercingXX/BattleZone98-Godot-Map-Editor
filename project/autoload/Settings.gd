extends Node
## Persisted user prefs: backend path, game root, recent files.

signal prefs_changed

const PATH := "user://settings.cfg"
const RECENT_MAX := 8
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 2.0
const UI_SCALE_DEFAULT := 1.0
const CAM_SPEED_MIN := 0.25
const CAM_SPEED_MAX := 4.0
const CAM_SPEED_DEFAULT := 1.0
const AUTOSAVE_DEFAULT_S := 30
const AUTOSAVE_CHOICES: Array[int] = [0, 15, 30, 60]
const LAYOUT_SPLIT_BODY_DEFAULT := 252
const LAYOUT_SPLIT_MID_DEFAULT := -280
const LAYOUT_SPLIT_RIGHT_DEFAULT := 440
const LAYOUT_SPLIT_UPPER_DEFAULT := 240
const LAYOUT_SPLIT_LOWER_DEFAULT := 160
const LAYOUT_SAVE_IDLE_S := 1.0

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
## Object snap. 0 = off. Allowed grids 1/5/10/20 m; angles 15/45/90°.
var snap_grid_m: float = 0.0
var snap_angle: float = 0.0
const VIEW_LABELS_ID := 20
## Root window content_scale_factor. Clamped 0.75–2.0. Default 1.0.
var ui_scale: float = UI_SCALE_DEFAULT
## Split offsets, console, focus mode, panel collapse. Restored at boot.
var layout_split_body: int = LAYOUT_SPLIT_BODY_DEFAULT
var layout_split_mid: int = LAYOUT_SPLIT_MID_DEFAULT
var layout_split_right: int = LAYOUT_SPLIT_RIGHT_DEFAULT
var layout_split_upper: int = LAYOUT_SPLIT_UPPER_DEFAULT
var layout_split_lower: int = LAYOUT_SPLIT_LOWER_DEFAULT
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
	snap_grid_m = coerce_snap_grid(_cfg.get_value("snap", "grid_m", 0.0))
	snap_angle = coerce_snap_angle(_cfg.get_value("snap", "angle", 0.0))
	ui_scale = coerce_ui_scale(_cfg.get_value("ui", "ui_scale", UI_SCALE_DEFAULT))
	layout_split_body = coerce_split(
		_cfg.get_value("layout", "split_body", LAYOUT_SPLIT_BODY_DEFAULT),
		LAYOUT_SPLIT_BODY_DEFAULT,
	)
	layout_split_mid = coerce_split(
		_cfg.get_value("layout", "split_mid", LAYOUT_SPLIT_MID_DEFAULT),
		LAYOUT_SPLIT_MID_DEFAULT,
	)
	layout_split_right = coerce_split(
		_cfg.get_value("layout", "split_right", LAYOUT_SPLIT_RIGHT_DEFAULT),
		LAYOUT_SPLIT_RIGHT_DEFAULT,
	)
	layout_split_upper = coerce_split(
		_cfg.get_value("layout", "split_upper", LAYOUT_SPLIT_UPPER_DEFAULT),
		LAYOUT_SPLIT_UPPER_DEFAULT,
	)
	layout_split_lower = coerce_split(
		_cfg.get_value("layout", "split_lower", LAYOUT_SPLIT_LOWER_DEFAULT),
		LAYOUT_SPLIT_LOWER_DEFAULT,
	)
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
	snap_grid_m = coerce_snap_grid(snap_grid_m)
	snap_angle = coerce_snap_angle(snap_angle)
	_cfg.set_value("snap", "grid_m", snap_grid_m)
	_cfg.set_value("snap", "angle", snap_angle)
	ui_scale = coerce_ui_scale(ui_scale)
	_cfg.set_value("ui", "ui_scale", ui_scale)
	layout_split_body = coerce_split(layout_split_body, LAYOUT_SPLIT_BODY_DEFAULT)
	layout_split_mid = coerce_split(layout_split_mid, LAYOUT_SPLIT_MID_DEFAULT)
	layout_split_right = coerce_split(layout_split_right, LAYOUT_SPLIT_RIGHT_DEFAULT)
	layout_split_upper = coerce_split(layout_split_upper, LAYOUT_SPLIT_UPPER_DEFAULT)
	layout_split_lower = coerce_split(layout_split_lower, LAYOUT_SPLIT_LOWER_DEFAULT)
	_cfg.set_value("layout", "split_body", layout_split_body)
	_cfg.set_value("layout", "split_mid", layout_split_mid)
	_cfg.set_value("layout", "split_right", layout_split_right)
	_cfg.set_value("layout", "split_upper", layout_split_upper)
	_cfg.set_value("layout", "split_lower", layout_split_lower)
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


func attach_labels_view_item(menu: PopupMenu) -> void:
	if menu == null:
		return
	if menu.get_item_index(VIEW_LABELS_ID) >= 0:
		return
	menu.add_separator()
	menu.add_check_item("Labels", VIEW_LABELS_ID)
	sync_labels_view_item(menu)


func sync_labels_view_item(menu: PopupMenu) -> void:
	if menu == null:
		return
	var idx := menu.get_item_index(VIEW_LABELS_ID)
	if idx < 0:
		return
	menu.set_item_checked(idx, view_labels)
	menu.set_item_tooltip(idx, "Class (and label) above objects within 400 m")


func toggle_view_labels() -> bool:
	view_labels = not view_labels
	save()
	return view_labels


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
