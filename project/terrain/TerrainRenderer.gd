extends Node3D
class_name TerrainRenderer
## Geometry-clipmap terrain. Rings of flat XZ meshes built once and re-snapped
## to the camera every frame; height, materials and every overlay come out of
## textures in project/shaders/terrain.gdshader.
##
## One ShaderMaterial for the whole terrain and RenderingServer instances
## rather than MeshInstance3D nodes — roughly ninety instances, all sharing
## five meshes, is not worth ninety nodes of scene-tree overhead.

## Camera distance is Chebyshev, not radial: the rings are squares, and a
## radial band would morph the corners of a ring before its edges.
const MORPH_BAND := Vector2(0.72, 0.92)
## One ring beyond the ring that first covers the map, so a camera flown off
## the edge still has the far corner in geometry.
const SPARE_RINGS := 1

var field: HeightField
## Chunked min/max over the heightfield. Sizes render AABBs; also the
## rejection structure a chunked raycast wants (see HeightRangeMap).
var ranges := HeightRangeMap.new()

var _clipmap := TerrainClipmap.new()
var _material: ShaderMaterial
var _shader: Shader
var _map_w: float = 0.0
var _map_d: float = 0.0
var _center: Vector2 = Vector2(INF, INF)
var _show_slope: bool = false
var _show_buildable: bool = false
var _show_ai_traversable: bool = false
var _show_water: bool = true
var _mask_on: bool = false
var _mask_tint: Color = Color(0.12, 0.32, 0.62)
var _mask_water_level: float = -1.0
var _sel_on: bool = false
var _atlas_tex: Texture2D
var _atlas_path: String = ""
var _lut_tex: ImageTexture
var _lut_world: String = ""
var _brush_on: bool = false
var _brush_center: Vector2 = Vector2.INF
var _brush_radius: float = -1.0
var _brush_falloff: float = -1.0
var _brush_square: bool = false
var _brush_count: int = 0
var _brush_noise_on: bool = false
var _brush_noise_scale: Vector2 = Vector2(-1.0, -1.0)
var _brush_noise_contrast: float = -1.0
var _brush_noise_seed: float = -1.0


func _ready() -> void:
	_shader = load("res://project/shaders/terrain.gdshader") as Shader
	MapState.water_changed.connect(set_water_level)
	set_process(true)


func _exit_tree() -> void:
	_clipmap.clear()
	_material = null


func _process(_delta: float) -> void:
	if field == null or _clipmap.instance_count() == 0:
		return
	var center := _view_center()
	if center.is_equal_approx(_center):
		return
	_center = center
	_material.set_shader_parameter("lod_center", center)
	_clipmap.update(center, ranges, _map_w, _map_d)


## Where the rings are centred. The camera's own XZ in both projections —
## in 2D map mode the orthographic camera sits directly over what it frames,
## so the same rule keeps the fine ring under the view centre.
func _view_center() -> Vector2:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector2(_map_w * 0.5, _map_d * 0.5)
	var p := cam.global_position
	return Vector2(p.x, p.z)


func instance_count() -> int:
	return _clipmap.instance_count()


func triangle_count() -> int:
	return _clipmap.triangle_count()


## Heights changed over an inclusive cell rect. Keeps the range map — and so
## the render AABBs — honest without a full rescan.
func note_height_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	if field == null:
		return
	ranges.update_rect(field, x0, z0, x1, z1)
	_clipmap.invalidate()
	_center = Vector2(INF, INF)


func note_height_rebuilt() -> void:
	if field == null:
		return
	ranges.rebuild(field)
	_clipmap.invalidate()
	_center = Vector2(INF, INF)


func set_slope_overlay(on: bool) -> void:
	_show_slope = on
	_set_all("show_slope", _show_slope)


func set_buildable_overlay(on: bool) -> void:
	_show_buildable = on
	_set_all("show_buildable", _show_buildable)


func set_ai_traversable_overlay(on: bool) -> void:
	_show_ai_traversable = on
	_set_all("show_ai_traversable", _show_ai_traversable)


func set_brush(on: bool, center: Vector2, radius: float, falloff: float, square: bool) -> void:
	var pts: Array[Vector2] = []
	if on:
		pts = ToolState.world_image_points(center.x, center.y)
		if pts.is_empty():
			pts = [center]
	var packed := PackedVector2Array()
	packed.resize(4)
	for i in mini(4, pts.size()):
		packed[i] = pts[i]
	var count := mini(4, pts.size())
	var noise_on := on and ToolState.tool == "noise"
	var sc := Settings.coerce_noise_param(ToolState.noise_scale, Settings.NOISE_SCALE_DEFAULT)
	var nscale := Vector2(sc, sc)
	var ncontrast := Settings.coerce_noise_param(ToolState.noise_contrast, Settings.NOISE_CONTRAST_DEFAULT)
	var nseed := float(ToolState.brush_seed)
	if (
		on == _brush_on
		and center == _brush_center
		and is_equal_approx(radius, _brush_radius)
		and is_equal_approx(falloff, _brush_falloff)
		and square == _brush_square
		and count == _brush_count
		and noise_on == _brush_noise_on
		and nscale.is_equal_approx(_brush_noise_scale)
		and is_equal_approx(ncontrast, _brush_noise_contrast)
		and is_equal_approx(nseed, _brush_noise_seed)
	):
		return
	if on and _brush_on and radius > 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# A live stroke rewrites the height texture directly; refresh the range
		# map under the brush so the AABBs do not lag the terrain they bound.
		# Hovering does not, so the scan is gated on the button being down.
		_refresh_brush_range(pts, radius)
	_brush_on = on
	_brush_center = center
	_brush_radius = radius
	_brush_falloff = falloff
	_brush_square = square
	_brush_count = count
	_brush_noise_on = noise_on
	_brush_noise_scale = nscale
	_brush_noise_contrast = ncontrast
	_brush_noise_seed = nseed
	if _material == null:
		return
	_material.set_shader_parameter("brush_on", on)
	_material.set_shader_parameter("brush_center", center)
	_material.set_shader_parameter("brush_centers", packed)
	_material.set_shader_parameter("brush_count", count)
	_material.set_shader_parameter("brush_radius", radius)
	_material.set_shader_parameter("brush_falloff", falloff)
	_material.set_shader_parameter("brush_shape", 1 if square else 0)
	_apply_brush_noise_params()


func set_brush_noise(scale: float, contrast: float, p_seed: int) -> void:
	var on := _brush_on and scale > 0.0 and ToolState.tool == "noise"
	var sc := Settings.coerce_noise_param(scale, Settings.NOISE_SCALE_DEFAULT)
	_brush_noise_on = on
	_brush_noise_scale = Vector2(sc, sc)
	_brush_noise_contrast = Settings.coerce_noise_param(contrast, Settings.NOISE_CONTRAST_DEFAULT)
	_brush_noise_seed = float(p_seed)
	_apply_brush_noise_params()


func _apply_brush_noise_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("show_brush_noise", _brush_noise_on)
	_material.set_shader_parameter("brush_noise_scale", _brush_noise_scale)
	_material.set_shader_parameter("brush_noise_contrast", _brush_noise_contrast)
	_material.set_shader_parameter("brush_noise_seed", _brush_noise_seed)


func _refresh_brush_range(pts: Array[Vector2], radius: float) -> void:
	if field == null or not ranges.valid():
		return
	var cell := HeightField.CELL_M
	for p in pts:
		var pad := radius + cell
		ranges.update_rect(
			field,
			int(floor((p.x - pad) / cell)), int(floor((p.y - pad) / cell)),
			int(ceil((p.x + pad) / cell)), int(ceil((p.y + pad) / cell))
		)


func set_water_level(level: float) -> void:
	_set_all("water_level", level if _show_water else -1.0)


func set_water_visible(on: bool) -> void:
	if _show_water == on:
		return
	_show_water = on
	set_water_level(MapState.water_level())


func set_feature_mask(on: bool, tex: Texture2D = null, tint: Color = Color(0.12, 0.32, 0.62), water_m: float = -1.0) -> void:
	_mask_on = on and tex != null
	_mask_tint = tint
	_mask_water_level = water_m
	_set_all("show_mask", _mask_on)
	if tex != null:
		_set_all("mask_tex", tex)
	_set_all("mask_tint", Vector3(tint.r, tint.g, tint.b))
	_set_all("mask_water_level", water_m)


func set_selection_mask(on: bool, tex: Texture2D = null) -> void:
	_sel_on = on and tex != null
	_set_all("show_selection", _sel_on)
	if tex != null:
		_set_all("selection_tex", tex)


func set_show_grid(on: bool) -> void:
	_set_all("show_grid", on)


func refresh_materials() -> void:
	if _material == null:
		return
	var colors := MaterialPalette.colors()
	var atlas := _load_atlas()
	var uvs := MaterialPalette.atlas_uvs()
	var lut := _build_tile_lut()
	if MapState.mat_texture:
		_material.set_shader_parameter("mat_tex", MapState.mat_texture)
	_material.set_shader_parameter("mat_colors", colors)
	_material.set_shader_parameter("show_materials", MapState.mat_grid_x > 0)
	if atlas:
		_material.set_shader_parameter("atlas_tex", atlas)
		_material.set_shader_parameter("use_atlas", true)
		_material.set_shader_parameter("mat_uvs", uvs)
	else:
		_material.set_shader_parameter("use_atlas", false)
	if atlas != null and lut != null:
		_material.set_shader_parameter("tile_lut", lut)
		_material.set_shader_parameter("use_tile_lut", true)
	else:
		_material.set_shader_parameter("use_tile_lut", false)


const _LUT_VARIANTS := 11  # variant nibble 0..10 → 'A'..'K' (F2 §2)


## Bake the world's atlas tile table (F2 §4) into a 256×33 RGBA32F lookup:
## x = base * 16 + transition, y = kind * 11 + variant, texel = (u, v, w, h).
## kind: 0 solid, 1 cap, 2 diagonal. w == 0 marks "no such tile" and the
## shader falls back to the solid tile / flat colour.
func _build_tile_lut() -> ImageTexture:
	if _lut_tex != null and _lut_world == MapState.world:
		return _lut_tex
	var tiles: Dictionary = {}
	for world in MapState.worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		if str(world.get("id", "")).to_lower() == MapState.world.to_lower():
			tiles = world.get("atlas_tiles", {})
			break
	if tiles.is_empty():
		return null
	# Parse "EL01CA0.MAP" → base 0, trans 1, kind C, variant A.
	var table := {}  # [base, trans, kind, variant] → [u, v, w, h]
	for key in tiles.keys():
		var stem := str(key).get_basename()
		if stem.length() < 6 or not stem.ends_with("0"):
			continue
		var core := stem.substr(stem.length() - 5, 4)
		var base := core.substr(0, 1).hex_to_int()
		var trans := core.substr(1, 1).hex_to_int()
		var kind := ["S", "C", "D"].find(core.substr(2, 1))
		var variant := core.unicode_at(3) - "A".unicode_at(0)
		if kind < 0 or base < 0 or trans < 0 \
				or variant < 0 or variant >= _LUT_VARIANTS:
			continue
		table[[base, trans, kind, variant]] = tiles[key]
	if table.is_empty():
		return null
	var img := Image.create_empty(256, 3 * _LUT_VARIANTS, false, Image.FORMAT_RGBAF)
	for base in 16:
		for trans in 16:
			for kind in 3:
				for variant in _LUT_VARIANTS:
					var rect: Variant = table.get([base, trans, kind, variant])
					if rect == null:
						rect = table.get([base, trans, kind, 0])  # variant A
					if rect == null and kind == 0 and base != trans:
						rect = table.get([base, base, 0, 0])  # solid fallback
					var c := Color(0, 0, 0, 0)
					if rect != null and (rect as Array).size() >= 4:
						c = Color(rect[0], rect[1], rect[2], rect[3])
					img.set_pixel(base * 16 + trans, kind * _LUT_VARIANTS + variant, c)
	_lut_tex = ImageTexture.create_from_image(img)
	_lut_world = MapState.world
	return _lut_tex


func _load_atlas() -> Texture2D:
	for world in MapState.worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		if str(world.get("id", "")).to_lower() != MapState.world.to_lower():
			continue
		var path := str(world.get("atlas_image", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			return null
		# DDS ice atlases blow out to white in the viewport. PNG only.
		if not path.to_lower().ends_with(".png"):
			return null
		if path == _atlas_path and _atlas_tex != null:
			return _atlas_tex
		var img := Image.load_from_file(path)
		if img == null:
			return null
		_atlas_tex = ImageTexture.create_from_image(img)
		_atlas_path = path
		return _atlas_tex
	return null


func _set_all(name: String, value: Variant) -> void:
	if _material != null:
		_material.set_shader_parameter(name, value)


func rebuild(p_field: HeightField) -> void:
	if field != null and field != p_field:
		if field.rect_dirty.is_connected(note_height_rect):
			field.rect_dirty.disconnect(note_height_rect)
		if field.rebuilt.is_connected(note_height_rebuilt):
			field.rebuilt.disconnect(note_height_rebuilt)
	field = p_field
	_lut_tex = null
	_lut_world = ""
	_brush_on = false
	_brush_center = Vector2.INF
	_brush_noise_on = false
	_center = Vector2(INF, INF)
	_clipmap.clear()
	for child in get_children():
		child.queue_free()
	if field == null or field.grid_x < 2 or not is_inside_tree():
		return
	if _shader == null:
		_shader = load("res://project/shaders/terrain.gdshader") as Shader
	_map_w = float(field.grid_x) * HeightField.CELL_M
	_map_d = float(field.grid_z) * HeightField.CELL_M
	# HeightField owns the truth about which cells moved. Without these the
	# range map only refreshes under a live brush, and goes stale on undo,
	# redo and heightmap import.
	if not field.rect_dirty.is_connected(note_height_rect):
		field.rect_dirty.connect(note_height_rect)
	if not field.rebuilt.is_connected(note_height_rebuilt):
		field.rebuilt.connect(note_height_rebuilt)
	ranges.rebuild(field)
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.set_shader_parameter("height_tex", field.texture)
	_material.set_shader_parameter("map_cells", Vector2(field.grid_x, field.grid_z))
	_material.set_shader_parameter("cell_m", HeightField.CELL_M)
	_material.set_shader_parameter("lod_span_quads", float(TerrainClipmap.HALF_SPAN))
	_material.set_shader_parameter("lod_morph", MORPH_BAND)
	_material.set_shader_parameter("lod_center", Vector2.ZERO)
	_material.set_shader_parameter("show_slope", _show_slope)
	_material.set_shader_parameter("show_buildable", _show_buildable)
	_material.set_shader_parameter("show_ai_traversable", _show_ai_traversable)
	_material.set_shader_parameter("show_brush_noise", false)
	_clipmap.setup(get_world_3d().scenario, _material.get_rid(), _ring_count())
	refresh_materials()
	set_water_level(MapState.water_level() if _show_water else -1.0)
	if _mask_on and MapState.mask_texture:
		set_feature_mask(true, MapState.mask_texture, _mask_tint, _mask_water_level)
	else:
		set_feature_mask(false)
	if not MapState.selection_empty() and MapState.selection_texture:
		set_selection_mask(true, MapState.selection_texture)
	else:
		set_selection_mask(false)
	_process(0.0)


## Enough rings that the outermost one reaches across the whole map from any
## point on it — each ring doubles its predecessor's reach.
func _ring_count() -> int:
	var reach := float(TerrainClipmap.HALF_SPAN) * HeightField.CELL_M
	var need := maxf(_map_w, _map_d)
	var n := 1
	while reach < need and n < 12:
		reach *= 2.0
		n += 1
	return n + SPARE_RINGS
