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
## Paint stamps recode the 1-tile halo as caps / diagonals (F2 §5). Default on.
var paint_match_edges: bool = true
var armed: Dictionary = {}
## Active mask target: "water" / "plants" and its stem. Empty = none.
var mask_kind: String = ""
var mask_stem: String = ""
var mask_paint: bool = false
## Editor-session only (not Settings). Survives map open/close in this run.
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
## World-XZ grid snap in metres. 0 = off. Allowed: 0 / 1 / 5 / 10 / 20.
var snap_grid_m: float = 0.0
## Yaw snap in degrees. 0 = off. Allowed: 0 / 15 / 45 / 90.
var snap_angle: float = 0.0


func _ready() -> void:
	snap_grid_m = Settings.snap_grid_m
	snap_angle = Settings.snap_angle
	MapState.session_changed.connect(_on_session_changed)


func _on_session_changed() -> void:
	if not armed.is_empty():
		clear_armed()
		EditorFeedback.log("disarmed (map changed)")
	if mask_paint or not mask_stem.is_empty():
		clear_mask_target()
	if clone_source_m.is_finite():
		clone_source_m = Vector2.INF


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
	brush_changed.emit()


func set_strength(v: float) -> void:
	if is_equal_approx(strength, v):
		return
	strength = v
	brush_changed.emit()


func set_falloff(v: float) -> void:
	if is_equal_approx(falloff, v):
		return
	falloff = v
	brush_changed.emit()


func set_shape(v: String) -> void:
	if shape == v:
		return
	shape = v
	brush_changed.emit()


func set_paint_material(id: int) -> void:
	id = clampi(id, 0, 15)
	if paint_material == id:
		return
	paint_material = id
	brush_changed.emit()


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
