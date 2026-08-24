extends Node
## Live tool / brush / armed-class state. Panels and the sculpt tool subscribe.

signal tool_changed(name: String)
signal brush_changed()
signal armed_changed()
signal mask_target_changed()
signal mask_paint_changed()
signal symmetry_changed()
signal snap_changed()

const SYMMETRY_OFF := "off"
const SYMMETRY_MIRROR_X := "mirror_x"
const SYMMETRY_MIRROR_Z := "mirror_z"
const SYMMETRY_ROT180 := "rot180"
const SYMMETRY_QUAD := "quad"

## Selector rows: id is stored on ToolState.symmetry, label is the OptionButton text.
const SYMMETRY_ITEMS: Array = [
	{"id": SYMMETRY_OFF, "label": "Off"},
	{"id": SYMMETRY_MIRROR_X, "label": "Mirror X (east-west)"},
	{"id": SYMMETRY_MIRROR_Z, "label": "Mirror Z (north-south)"},
	{"id": SYMMETRY_ROT180, "label": "Rotate 180"},
	{"id": SYMMETRY_QUAD, "label": "Quad (4-fold rotation)"},
]

var tool: String = "fly"
var radius_m: float = 40.0
var strength: float = 0.45
var falloff: float = 0.65
var shape: String = "circle"
var paint_material: int = 0
## The mapmaker assigns the tile word. "solid" / "cap" / "diag".
var paint_kind: String = "solid"
var paint_transition: int = 0
var paint_flip: int = 0
var paint_rot: int = 0
var paint_variant: int = 0
## Optional helper: recode a painted halo from neighbours. Off = stamp the word as-is.
var paint_match_edges: bool = false
var armed: Dictionary = {}
## Active mask target: "water" / "plants" and its stem. Empty = none.
var mask_kind: String = ""
var mask_stem: String = ""
var mask_paint: bool = false
## Persisted with the rest of the brush; survives map open/close and relaunch.
var symmetry: String = SYMMETRY_OFF
## Magic-wand height tolerance in metres (tool state, not persisted).
var wand_tolerance_m: float = 5.0
## Feather radius in metres for the selection panel.
var feather_radius_m: float = 10.0
## Grow/shrink cell count for the selection panel.
var grow_cells: int = 1
## Clone-stamp source in world XZ. Non-finite = unset.
var clone_source_m: Vector2 = Vector2.INF
var clone_materials: bool = false
## When true, clone stamps the sampled absolute height. When false, relative delta.
var clone_match_height: bool = true
## Last Place-tool yaw in degrees, reused until the user drag-aims again.
var place_yaw_deg: float = 0.0
## World-XZ grid snap in metres. 0 = off. Allowed: 0 / 1 / 5 / 10 / 20.
var snap_grid_m: float = 0.0
## Yaw snap in degrees. 0 = off. Allowed: 0 / 15 / 45 / 90.
var snap_angle: float = 0.0

## Generated tip id (BrushMask.IDS) or "" for the analytic circle/square.
var brush_mask: String = ""
## Tip rotation in degrees, and whether each dab gets a random turn on top.
var brush_rotation_deg: float = 0.0
var brush_random_rotation: bool = false
## Dab gates: fraction of radius, and milliseconds. 0 disables either.
var brush_spacing: float = 0.0
var brush_spacing_ms: int = 0
## How much pen pressure reaches dab size and dab opacity, 0..1 each.
var brush_pressure_size: float = 0.0
var brush_pressure_opacity: float = 0.0
## Slope band in degrees against up. Armed by limit_slope.
var limit_slope: bool = false
var slope_min_deg: float = 0.0
var slope_max_deg: float = 90.0
var slope_feather_deg: float = 5.0
## Height band in metres. Armed by limit_height.
var limit_height: bool = false
var height_min_m: float = 0.0
var height_max_m: float = 409.5
var height_feather_m: float = 2.0
## Noise brush. Frequency is per world metre; amplitude is metres.
var noise_frequency: float = 0.02
var noise_octaves: int = 3
var noise_amplitude_m: float = 6.0
var noise_scale: float = 10.0
var noise_contrast: float = 1.0
## Seeds the noise field and the random-rotation stream. Fixed = reproducible.
var brush_seed: int = 1
## Morphological erode / dilate disc, and its height slack per excess cell.
var erode_radius_m: float = 10.0
var erode_slack_m: float = 3.0
## Set-height target in metres.
var set_height_m: float = 25.0
## Set-angle plane: slope in degrees and the compass bearing of the ascent.
var angle_deg: float = 15.0
var angle_dir_deg: float = 0.0
## Set-angle origin in world XZ. Non-finite = use the stroke start.
var angle_origin_m: Vector2 = Vector2.INF

## Height kernels the sculpt tool can run. The shell routes these strings.
const HEIGHT_BRUSHES: PackedStringArray = [
	"raise", "lower", "flatten", "smooth", "noise",
	"erode", "dilate", "setheight", "setangle",
]

## Brush settings are dragged, not clicked. Coalesce the writes the way the
## layout splits do rather than hitting the config file per slider frame.
const BRUSH_SAVE_IDLE_S := 1.0

var _brush_save: Timer


func _ready() -> void:
	snap_grid_m = Settings.snap_grid_m
	snap_angle = Settings.snap_angle
	load_brush_settings()
	BrushMaskLibrary.prewarm()
	_brush_save = Timer.new()
	_brush_save.name = "BrushSave"
	_brush_save.one_shot = true
	_brush_save.wait_time = BRUSH_SAVE_IDLE_S
	_brush_save.timeout.connect(save_brush_settings)
	add_child(_brush_save)
	MapState.session_changed.connect(_on_session_changed)


## Adopt the persisted brush. Called at boot; safe to call again in a test.
func load_brush_settings() -> void:
	radius_m = Settings.brush_radius_m
	strength = Settings.brush_strength
	falloff = Settings.brush_falloff
	shape = Settings.brush_shape
	symmetry = normalize_symmetry(Settings.brush_symmetry)
	brush_mask = Settings.brush_mask
	brush_rotation_deg = Settings.brush_rotation_deg
	brush_random_rotation = Settings.brush_random_rotation
	brush_spacing = Settings.brush_spacing
	brush_spacing_ms = Settings.brush_spacing_ms
	brush_pressure_size = Settings.brush_pressure_size
	brush_pressure_opacity = Settings.brush_pressure_opacity
	limit_slope = Settings.limit_slope
	slope_min_deg = Settings.slope_min_deg
	slope_max_deg = Settings.slope_max_deg
	slope_feather_deg = Settings.slope_feather_deg
	limit_height = Settings.limit_height
	height_min_m = Settings.height_min_m
	height_max_m = Settings.height_max_m
	height_feather_m = Settings.height_feather_m
	noise_frequency = Settings.noise_frequency
	noise_octaves = Settings.noise_octaves
	noise_amplitude_m = Settings.noise_amplitude_m
	noise_scale = Settings.noise_scale
	noise_contrast = Settings.noise_contrast
	brush_seed = Settings.brush_seed
	erode_radius_m = Settings.erode_radius_m
	erode_slack_m = Settings.erode_slack_m
	set_height_m = Settings.set_height_m
	angle_deg = Settings.angle_deg
	angle_dir_deg = Settings.angle_dir_deg
	brush_changed.emit()


## Write the live brush straight through. The idle timer routes here.
func save_brush_settings() -> void:
	Settings.brush_radius_m = radius_m
	Settings.brush_strength = strength
	Settings.brush_falloff = falloff
	Settings.brush_shape = shape
	Settings.brush_symmetry = symmetry
	Settings.brush_mask = brush_mask
	Settings.brush_rotation_deg = brush_rotation_deg
	Settings.brush_random_rotation = brush_random_rotation
	Settings.brush_spacing = brush_spacing
	Settings.brush_spacing_ms = brush_spacing_ms
	Settings.brush_pressure_size = brush_pressure_size
	Settings.brush_pressure_opacity = brush_pressure_opacity
	Settings.limit_slope = limit_slope
	Settings.slope_min_deg = slope_min_deg
	Settings.slope_max_deg = slope_max_deg
	Settings.slope_feather_deg = slope_feather_deg
	Settings.limit_height = limit_height
	Settings.height_min_m = height_min_m
	Settings.height_max_m = height_max_m
	Settings.height_feather_m = height_feather_m
	Settings.noise_frequency = noise_frequency
	Settings.noise_octaves = noise_octaves
	Settings.noise_amplitude_m = noise_amplitude_m
	Settings.noise_scale = noise_scale
	Settings.noise_contrast = noise_contrast
	Settings.brush_seed = brush_seed
	Settings.erode_radius_m = erode_radius_m
	Settings.erode_slack_m = erode_slack_m
	Settings.set_height_m = set_height_m
	Settings.angle_deg = angle_deg
	Settings.angle_dir_deg = angle_dir_deg
	Settings.save()


## The idle timer coalesces, it is not the source of truth: quitting inside
## its window still has to keep the brush the mapmaker left set.
func _notification(what: int) -> void:
	if what != NOTIFICATION_EXIT_TREE or _brush_save == null:
		return
	if not _brush_save.is_stopped():
		save_brush_settings()


## Note a brush edit: tell the panels now, hit the disk once the drag stops.
func _brush_dirty() -> void:
	brush_changed.emit()
	if _brush_save != null:
		_brush_save.start(BRUSH_SAVE_IDLE_S)


static func is_height_brush(tool_name: String) -> bool:
	return HEIGHT_BRUSHES.has(tool_name)


## Tools that open a SculptTool stroke on mouse-down.
static func is_stroke_tool(tool_name: String) -> bool:
	return tool_name == "paint" or tool_name == "clone" or is_height_brush(tool_name)


## Tools that should show the brush ring under the cursor.
static func is_brush_tool(tool_name: String) -> bool:
	return tool_name == "ramp" or tool_name == "qsel" or is_stroke_tool(tool_name)


## March distance the shell should use between dabs of a drag.
func stroke_spacing_m() -> float:
	if brush_spacing > 0.0:
		return maxf(HeightField.CELL_M, radius_m * brush_spacing)
	return maxf(HeightField.CELL_M, radius_m * 0.15)


## New brush settings, in one place so a panel can drive them generically.
## Every setter emits brush_changed and arms the idle save.
func set_brush_mask(id: String) -> void:
	if not id.is_empty() and not BrushMaskLibrary.has(id):
		id = ""
	if brush_mask == id:
		return
	brush_mask = id
	_brush_dirty()


func set_brush_rotation(deg: float) -> void:
	deg = fposmod(deg, 360.0)
	if is_equal_approx(brush_rotation_deg, deg):
		return
	brush_rotation_deg = deg
	_brush_dirty()


func set_brush_random_rotation(on: bool) -> void:
	if brush_random_rotation == on:
		return
	brush_random_rotation = on
	_brush_dirty()


func set_brush_spacing(frac: float, ms: int = -1) -> void:
	frac = clampf(frac, 0.0, 4.0)
	if ms >= 0:
		brush_spacing_ms = clampi(ms, 0, 2000)
	if is_equal_approx(brush_spacing, frac) and ms < 0:
		return
	brush_spacing = frac
	_brush_dirty()


func set_brush_pressure(size_factor: float, opacity_factor: float) -> void:
	size_factor = clampf(size_factor, 0.0, 1.0)
	opacity_factor = clampf(opacity_factor, 0.0, 1.0)
	if is_equal_approx(brush_pressure_size, size_factor) \
			and is_equal_approx(brush_pressure_opacity, opacity_factor):
		return
	brush_pressure_size = size_factor
	brush_pressure_opacity = opacity_factor
	_brush_dirty()


func set_slope_limit(on: bool, lo: float = NAN, hi: float = NAN) -> void:
	limit_slope = on
	if is_finite(lo):
		slope_min_deg = clampf(lo, 0.0, 90.0)
	if is_finite(hi):
		slope_max_deg = clampf(hi, 0.0, 90.0)
	_brush_dirty()


func set_height_limit(on: bool, lo: float = NAN, hi: float = NAN) -> void:
	limit_height = on
	if is_finite(lo):
		height_min_m = lo
	if is_finite(hi):
		height_max_m = hi
	_brush_dirty()


func set_noise_params(freq: float, octaves: int, amplitude_m: float, p_seed: int) -> void:
	noise_frequency = clampf(freq, 0.00001, 1.0)
	noise_octaves = clampi(octaves, 1, 8)
	noise_amplitude_m = maxf(amplitude_m, 0.0)
	brush_seed = p_seed
	_brush_dirty()


func set_noise_scale(scale: float) -> void:
	noise_scale = Settings.coerce_noise_param(scale, Settings.NOISE_SCALE_DEFAULT)
	_brush_dirty()


func set_noise_contrast(contrast: float) -> void:
	noise_contrast = Settings.coerce_noise_param(contrast, Settings.NOISE_CONTRAST_DEFAULT)
	_brush_dirty()


func set_clone_match_height(on: bool) -> void:
	clone_match_height = on


func set_erode_params(radius: float, slack_m: float) -> void:
	erode_radius_m = clampf(radius, HeightField.CELL_M, 4.0 * HeightField.CELL_M)
	erode_slack_m = maxf(slack_m, 0.0)
	_brush_dirty()


func set_target_height(h_m: float) -> void:
	if is_equal_approx(set_height_m, h_m):
		return
	set_height_m = h_m
	_brush_dirty()


func set_target_angle(deg: float, bearing_deg: float) -> void:
	deg = clampf(deg, -89.0, 89.0)
	bearing_deg = fposmod(bearing_deg, 360.0)
	if is_equal_approx(angle_deg, deg) and is_equal_approx(angle_dir_deg, bearing_deg):
		return
	angle_deg = deg
	angle_dir_deg = bearing_deg
	_brush_dirty()


func set_angle_origin(x_m: float, z_m: float) -> void:
	angle_origin_m = Vector2(x_m, z_m)


func clear_angle_origin() -> void:
	angle_origin_m = Vector2.INF


func has_angle_origin() -> bool:
	return angle_origin_m.is_finite()


func _on_session_changed() -> void:
	if not armed.is_empty():
		clear_armed()
		EditorFeedback.log("disarmed (map changed)")
	if mask_paint or not mask_stem.is_empty():
		clear_mask_target()
	if clone_source_m.is_finite():
		clone_source_m = Vector2.INF
	if angle_origin_m.is_finite():
		angle_origin_m = Vector2.INF


func set_tool(name: String) -> void:
	if tool == name:
		return
	tool = name
	if name != "place":
		clear_armed()
	tool_changed.emit(name)


func set_radius(v: float) -> void:
	if is_equal_approx(radius_m, v):
		return
	radius_m = v
	_brush_dirty()


func set_strength(v: float) -> void:
	if is_equal_approx(strength, v):
		return
	strength = v
	_brush_dirty()


func set_falloff(v: float) -> void:
	if is_equal_approx(falloff, v):
		return
	falloff = v
	_brush_dirty()


func set_shape(v: String) -> void:
	if shape == v:
		return
	shape = v
	_brush_dirty()


func set_paint_material(id: int) -> void:
	id = clampi(id, 0, 15)
	if paint_material == id:
		return
	paint_material = id
	_clamp_paint_pair()
	brush_changed.emit()


func set_paint_kind(kind: String) -> void:
	if kind != "solid" and kind != "cap" and kind != "diag":
		kind = "solid"
	if kind != "solid" and not MaterialPalette.has_kind_for(paint_material, kind):
		kind = "solid"
	if paint_kind == kind:
		return
	if kind == "diag":
		# Identity D tile faces left (F2 orientation 14 → flip=1, rot=2).
		paint_flip = 1
		paint_rot = 2
	paint_kind = kind
	_clamp_paint_pair()
	brush_changed.emit()


func set_paint_transition(id: int) -> void:
	id = clampi(id, 0, 15)
	if paint_transition == id:
		return
	paint_transition = id
	_clamp_paint_pair()
	brush_changed.emit()


func set_paint_flip(on: bool) -> void:
	var v := 1 if on else 0
	if paint_flip == v:
		return
	paint_flip = v
	brush_changed.emit()


func cycle_paint_rot() -> void:
	if paint_kind == "diag":
		# Left → Up → Right → Down, staying on the unmirrored identity quartet.
		paint_flip = 1
		match paint_rot:
			2:
				paint_rot = 1
			1:
				paint_rot = 0
			0:
				paint_rot = 3
			_:
				paint_rot = 2
	else:
		paint_rot = (paint_rot + 1) & 0x3
	brush_changed.emit()


func paint_diag_facing() -> String:
	match paint_rot:
		2:
			return "Left"
		1:
			return "Up"
		0:
			return "Right"
		_:
			return "Down"


func set_paint_rot(v: int) -> void:
	v = v & 0x3
	if paint_rot == v:
		return
	paint_rot = v
	brush_changed.emit()


func set_paint_variant(v: int) -> void:
	v = clampi(v, 0, 3)
	if paint_variant == v:
		return
	paint_variant = v
	brush_changed.emit()


func paint_word() -> int:
	if paint_kind == "solid":
		return BzMat.encode_entry(paint_material, paint_material)
	var other := paint_transition
	if other == paint_material or not MaterialPalette.has_transition(
		paint_material, other, paint_kind
	):
		return BzMat.encode_entry(paint_material, paint_material)
	var cap := 1 if paint_kind == "diag" else 0
	return BzMat.encode_entry(
		paint_material, other, cap, paint_flip, paint_rot, paint_variant
	)


func _clamp_paint_pair() -> void:
	if paint_kind == "solid":
		return
	if not MaterialPalette.has_kind_for(paint_material, paint_kind):
		paint_kind = "solid"
		return
	var partners: PackedInt32Array = MaterialPalette.transition_partners(
		paint_material, paint_kind
	)
	if partners.is_empty():
		paint_kind = "solid"
		return
	if not partners.has(paint_transition):
		paint_transition = partners[0]
	var vars: PackedInt32Array = MaterialPalette.variants_for(
		paint_material, paint_transition, paint_kind
	)
	if not vars.is_empty() and not vars.has(paint_variant):
		paint_variant = vars[0]


func set_paint_from_word(word: int) -> void:
	var d: Dictionary = BzMat.decode_entry(word)
	paint_material = int(d["mat_a"])
	paint_transition = int(d["mat_b"])
	paint_flip = int(d["flip"])
	paint_rot = int(d["rot"])
	paint_variant = int(d["variant"])
	paint_kind = BzMat.kind_of_entry(word)
	brush_changed.emit()


func paint_describe() -> String:
	var a := "%s" % MaterialPalette.type_name(paint_material)
	if paint_kind == "solid":
		return "solid %d (%s)" % [paint_material, a]
	var b := "%s" % MaterialPalette.type_name(paint_transition)
	var kind := "corner" if paint_kind == "diag" else "cap"
	if paint_kind == "diag":
		return "%s %d→%d (%s / %s)  %s" % [
			kind, paint_material, paint_transition, a, b, paint_diag_facing(),
		]
	return "%s %d→%d (%s / %s)  rot %d%s" % [
		kind, paint_material, paint_transition, a, b, paint_rot * 90,
		"  mirror" if paint_flip != 0 else "",
	]


func set_paint_match_edges(on: bool) -> void:
	if paint_match_edges == on:
		return
	paint_match_edges = on
	brush_changed.emit()


func set_armed(rec: Dictionary) -> void:
	armed = rec
	if not rec.is_empty() and tool != "place":
		tool = "place"
		tool_changed.emit("place")
	armed_changed.emit()


func clear_armed() -> void:
	if armed.is_empty():
		return
	armed = {}
	armed_changed.emit()


func set_mask_target(kind: String, feat_stem: String) -> void:
	if kind == mask_kind and feat_stem == mask_stem:
		return
	mask_kind = kind
	mask_stem = feat_stem
	if feat_stem.is_empty():
		mask_kind = ""
		if mask_paint:
			mask_paint = false
			mask_paint_changed.emit()
	mask_target_changed.emit()


func clear_mask_target() -> void:
	if mask_kind.is_empty() and mask_stem.is_empty() and not mask_paint:
		return
	mask_kind = ""
	mask_stem = ""
	var was_paint := mask_paint
	mask_paint = false
	mask_target_changed.emit()
	if was_paint:
		mask_paint_changed.emit()


func set_mask_paint(on: bool) -> void:
	if on and mask_stem.is_empty():
		on = false
	if mask_paint == on:
		return
	mask_paint = on
	mask_paint_changed.emit()


func is_mask_painting() -> bool:
	return mask_paint and not mask_stem.is_empty()


func set_wand_tolerance(v: float) -> void:
	wand_tolerance_m = maxf(0.0, v)


func set_feather_radius(v: float) -> void:
	feather_radius_m = maxf(0.0, v)


func set_grow_cells(v: int) -> void:
	grow_cells = maxi(0, v)


func set_clone_source(x_m: float, z_m: float) -> void:
	clone_source_m = Vector2(x_m, z_m)


func clear_clone_source() -> void:
	clone_source_m = Vector2.INF


func has_clone_source() -> bool:
	return clone_source_m.is_finite()


func set_clone_materials(on: bool) -> void:
	clone_materials = on


func set_snap_grid(v: float) -> void:
	v = SelectionGizmo.coerce_snap_grid(v)
	if is_equal_approx(snap_grid_m, v):
		return
	snap_grid_m = v
	Settings.snap_grid_m = v
	Settings.save()
	snap_changed.emit()


func set_snap_angle(v: float) -> void:
	v = SelectionGizmo.coerce_snap_angle(v)
	if is_equal_approx(snap_angle, v):
		return
	snap_angle = v
	Settings.snap_angle = v
	Settings.save()
	snap_changed.emit()


func is_terrain_select_tool() -> bool:
	return tool == "qsel" or tool == "rsel" or tool == "wand"


func set_symmetry(mode: String) -> void:
	mode = normalize_symmetry(mode)
	if symmetry == mode:
		return
	symmetry = mode
	symmetry_changed.emit()
	if _brush_save != null:
		_brush_save.start(BRUSH_SAVE_IDLE_S)


static func normalize_symmetry(mode: String) -> String:
	match mode:
		SYMMETRY_OFF, SYMMETRY_MIRROR_X, SYMMETRY_MIRROR_Z, SYMMETRY_ROT180, SYMMETRY_QUAD:
			return mode
		_:
			return SYMMETRY_OFF


static func mode_arity(mode: String) -> int:
	match normalize_symmetry(mode):
		SYMMETRY_MIRROR_X, SYMMETRY_MIRROR_Z, SYMMETRY_ROT180:
			return 2
		SYMMETRY_QUAD:
			return 4
		_:
			return 1


static func symmetry_log_name(mode: String) -> String:
	match normalize_symmetry(mode):
		SYMMETRY_MIRROR_X:
			return "mirror x"
		SYMMETRY_MIRROR_Z:
			return "mirror z"
		SYMMETRY_ROT180:
			return "rot180"
		SYMMETRY_QUAD:
			return "quad"
		_:
			return "off"


func map_size_m() -> Vector2:
	var w := float(MapState.width_m)
	var d := float(MapState.depth_m)
	if MapState.field != null:
		if w <= 0.0 and MapState.field.grid_x > 0:
			w = float(MapState.field.grid_x) * HeightField.CELL_M
		if d <= 0.0 and MapState.field.grid_z > 0:
			d = float(MapState.field.grid_z) * HeightField.CELL_M
	return Vector2(w, d)


func map_center_m() -> Vector2:
	return map_size_m() * 0.5


func is_square_map() -> bool:
	var sz := map_size_m()
	return sz.x > 0.0 and is_equal_approx(sz.x, sz.y)


func can_use_quad() -> bool:
	return is_square_map()


func effective_symmetry() -> String:
	var mode := normalize_symmetry(symmetry)
	if mode == SYMMETRY_QUAD and not can_use_quad():
		return SYMMETRY_OFF
	return mode


## Image of (x, z) under the live mode and the open map's center.
func world_image_points(x: float, z: float) -> Array[Vector2]:
	var c := map_center_m()
	return image_points_xz(effective_symmetry(), x, z, c.x, c.y)


func world_image_poses(x: float, z: float, yaw_deg: float) -> Array[Dictionary]:
	var c := map_center_m()
	return image_poses(effective_symmetry(), x, z, yaw_deg, c.x, c.y)


static func wrap_yaw_deg(deg: float) -> float:
	var y := fposmod(deg + 180.0, 360.0) - 180.0
	if is_equal_approx(y, -180.0):
		return 180.0
	return y


## k is the image index: 0 = identity, then the mode's other copies.
## Mirror X flips X across the map-center YZ plane. Mirror Z flips Z.
## Rot180 is a point reflection. Quad is 90° clockwise copies (yaw += 90k).
static func transform_xz(mode: String, x: float, z: float, cx: float, cz: float, k: int) -> Vector2:
	var dx := x - cx
	var dz := z - cz
	match normalize_symmetry(mode):
		SYMMETRY_MIRROR_X:
			if k == 1:
				return Vector2(cx - dx, z)
		SYMMETRY_MIRROR_Z:
			if k == 1:
				return Vector2(x, cz - dz)
		SYMMETRY_ROT180:
			if k == 1:
				return Vector2(cx - dx, cz - dz)
		SYMMETRY_QUAD:
			match k:
				1:
					return Vector2(cx + dz, cz - dx)
				2:
					return Vector2(cx - dx, cz - dz)
				3:
					return Vector2(cx - dz, cz + dx)
	return Vector2(x, z)


static func transform_yaw_deg(mode: String, yaw_deg: float, k: int) -> float:
	var yaw := yaw_deg
	match normalize_symmetry(mode):
		SYMMETRY_MIRROR_X:
			if k == 1:
				yaw = -yaw_deg
		SYMMETRY_MIRROR_Z:
			if k == 1:
				yaw = 180.0 - yaw_deg
		SYMMETRY_ROT180:
			if k == 1:
				yaw = yaw_deg + 180.0
		SYMMETRY_QUAD:
			yaw = yaw_deg + 90.0 * float(k)
	return wrap_yaw_deg(yaw)


static func transform_cell(mode: String, x: int, z: int, grid_x: int, grid_z: int, k: int) -> Vector2i:
	mode = normalize_symmetry(mode)
	if mode == SYMMETRY_QUAD and grid_x != grid_z:
		return Vector2i(x, z)
	match mode:
		SYMMETRY_MIRROR_X:
			if k == 1:
				return Vector2i(grid_x - 1 - x, z)
		SYMMETRY_MIRROR_Z:
			if k == 1:
				return Vector2i(x, grid_z - 1 - z)
		SYMMETRY_ROT180:
			if k == 1:
				return Vector2i(grid_x - 1 - x, grid_z - 1 - z)
		SYMMETRY_QUAD:
			var n := grid_x
			match k:
				1:
					return Vector2i(z, n - 1 - x)
				2:
					return Vector2i(n - 1 - x, n - 1 - z)
				3:
					return Vector2i(n - 1 - z, x)
	return Vector2i(x, z)


static func image_points_xz(mode: String, x: float, z: float, cx: float, cz: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := mode_arity(mode)
	for k in n:
		var p := transform_xz(mode, x, z, cx, cz, k)
		if _has_xz(out, p):
			continue
		out.append(p)
	return out


static func image_points_cell(mode: String, x: int, z: int, grid_x: int, grid_z: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := mode_arity(mode)
	if mode == SYMMETRY_QUAD and grid_x != grid_z:
		n = 1
	for k in n:
		var p := transform_cell(mode, x, z, grid_x, grid_z, k)
		var dup := false
		for e in out:
			if e == p:
				dup = true
				break
		if not dup:
			out.append(p)
	return out


static func image_poses(
	mode: String, x: float, z: float, yaw_deg: float, cx: float, cz: float
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := mode_arity(mode)
	for k in n:
		var p := transform_xz(mode, x, z, cx, cz, k)
		if _has_pose_xz(out, p):
			continue
		out.append({
			"x": p.x,
			"z": p.y,
			"yaw_deg": transform_yaw_deg(mode, yaw_deg, k),
			"k": k,
		})
	return out


static func _has_xz(pts: Array[Vector2], p: Vector2) -> bool:
	for e in pts:
		if is_equal_approx(e.x, p.x) and is_equal_approx(e.y, p.y):
			return true
	return false


static func _has_pose_xz(poses: Array[Dictionary], p: Vector2) -> bool:
	for rec in poses:
		if is_equal_approx(float(rec.get("x", 0.0)), p.x) \
				and is_equal_approx(float(rec.get("z", 0.0)), p.y):
			return true
	return false
