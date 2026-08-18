extends Node3D
class_name TerrainRenderer
## Chunked GPU-displaced planes. Shared mesh; per-chunk UV offset.

const CHUNK_CELLS := 128

var field: HeightField
var _chunk_mesh: ArrayMesh
var _shader: Shader
var _show_slope: bool = false
var _show_water: bool = true
var _mask_on: bool = false
var _mask_tint: Color = Color(0.12, 0.32, 0.62)
var _mask_water_level: float = -1.0
var _sel_on: bool = false


func _ready() -> void:
	_shader = load("res://project/shaders/terrain.gdshader") as Shader
	MapState.water_changed.connect(set_water_level)


func set_slope_overlay(on: bool) -> void:
	_show_slope = on
	_set_all("show_slope", _show_slope)


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
	for child in get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat == null:
				continue
			mat.set_shader_parameter("brush_on", on)
			mat.set_shader_parameter("brush_center", center)
			mat.set_shader_parameter("brush_centers", packed)
			mat.set_shader_parameter("brush_count", count)
			mat.set_shader_parameter("brush_radius", radius)
			mat.set_shader_parameter("brush_falloff", falloff)
			mat.set_shader_parameter("brush_shape", 1 if square else 0)


func set_water_level(level: float) -> void:
	_set_all("water_level", level if _show_water else -1.0)


func set_water_visible(on: bool) -> void:
	if _show_water == on:
		return
	_show_water = on
	set_water_level(MapState.water_level())


func is_water_visible() -> bool:
	return _show_water


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
	var colors := MaterialPalette.colors()
	var atlas := _load_atlas()
	var uvs := MaterialPalette.atlas_uvs()
	var lut := _build_tile_lut()
	for child in get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat == null:
				continue
			if MapState.mat_texture:
				mat.set_shader_parameter("mat_tex", MapState.mat_texture)
			mat.set_shader_parameter("mat_colors", colors)
			mat.set_shader_parameter("show_materials", MapState.mat_grid_x > 0)
			if atlas:
				mat.set_shader_parameter("atlas_tex", atlas)
				mat.set_shader_parameter("use_atlas", true)
				mat.set_shader_parameter("mat_uvs", uvs)
			else:
				mat.set_shader_parameter("use_atlas", false)
			if atlas != null and lut != null:
				mat.set_shader_parameter("tile_lut", lut)
				mat.set_shader_parameter("use_tile_lut", true)
			else:
				mat.set_shader_parameter("use_tile_lut", false)


const _LUT_VARIANTS := 11  # variant nibble 0..10 → 'A'..'K' (F2 §2)


## Bake the world's atlas tile table (F2 §4) into a 256×33 RGBA32F lookup:
## x = base * 16 + transition, y = kind * 11 + variant, texel = (u, v, w, h).
## kind: 0 solid, 1 cap, 2 diagonal. w == 0 marks "no such tile" and the
## shader falls back to the solid tile / flat colour.
func _build_tile_lut() -> ImageTexture:
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
	return ImageTexture.create_from_image(img)


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
		var img := Image.load_from_file(path)
		if img == null:
			return null
		return ImageTexture.create_from_image(img)
	return null


func _set_all(name: String, value: Variant) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter(name, value)


func rebuild(p_field: HeightField) -> void:
	field = p_field
	for child in get_children():
		child.queue_free()
	if field == null or field.grid_x < 2:
		return
	if _shader == null:
		_shader = load("res://project/shaders/terrain.gdshader") as Shader
	_chunk_mesh = _make_chunk_mesh(CHUNK_CELLS, HeightField.CELL_M)
	var chunks_x := int(ceil(float(field.grid_x) / float(CHUNK_CELLS)))
	var chunks_z := int(ceil(float(field.grid_z) / float(CHUNK_CELLS)))
	for cz in chunks_z:
		for cx in chunks_x:
			_add_chunk(cx, cz)
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


func _add_chunk(cx: int, cz: int) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = _chunk_mesh
	inst.position = Vector3(
		float(cx * CHUNK_CELLS) * HeightField.CELL_M,
		0.0,
		float(cz * CHUNK_CELLS) * HeightField.CELL_M
	)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("height_tex", field.texture)
	mat.set_shader_parameter("map_cells", Vector2(field.grid_x, field.grid_z))
	mat.set_shader_parameter("cell_m", HeightField.CELL_M)
	mat.set_shader_parameter("uv_origin", Vector2(
		float(cx * CHUNK_CELLS) / float(field.grid_x),
		float(cz * CHUNK_CELLS) / float(field.grid_z)
	))
	mat.set_shader_parameter("uv_scale", Vector2(
		float(CHUNK_CELLS) / float(field.grid_x),
		float(CHUNK_CELLS) / float(field.grid_z)
	))
	mat.set_shader_parameter("show_slope", _show_slope)
	if MapState.mat_texture:
		mat.set_shader_parameter("mat_tex", MapState.mat_texture)
	mat.set_shader_parameter("mat_colors", MaterialPalette.colors())
	mat.set_shader_parameter("show_materials", MapState.mat_grid_x > 0)
	mat.set_shader_parameter("water_level", MapState.water_level() if _show_water else -1.0)
	mat.set_shader_parameter("show_mask", _mask_on)
	if MapState.mask_texture:
		mat.set_shader_parameter("mask_tex", MapState.mask_texture)
	mat.set_shader_parameter("mask_tint", Vector3(_mask_tint.r, _mask_tint.g, _mask_tint.b))
	mat.set_shader_parameter("mask_water_level", _mask_water_level)
	mat.set_shader_parameter("show_selection", _sel_on)
	if MapState.selection_texture:
		mat.set_shader_parameter("selection_tex", MapState.selection_texture)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func _make_chunk_mesh(cells: int, cell_m: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := cells + 1
	for z in verts:
		for x in verts:
			var u := float(x) / float(cells)
			var v := float(z) / float(cells)
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(float(x) * cell_m, 0.0, float(z) * cell_m))
	for z in cells:
		for x in cells:
			var i0 := z * verts + x
			var i1 := i0 + 1
			var i2 := i0 + verts
			var i3 := i2 + 1
			# Godot front faces wind clockwise; seen from +Y this order keeps
			# the top surface front-facing (the reversed order culled the
			# entire terrain from above).
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)
	return st.commit()
