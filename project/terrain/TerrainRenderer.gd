extends Node3D
class_name TerrainRenderer
## Chunked GPU-displaced planes. Shared mesh; per-chunk UV offset.

const CHUNK_CELLS := 128

var field: HeightField
var _chunk_mesh: ArrayMesh
var _shader: Shader
var _show_slope: bool = true


func _ready() -> void:
	_shader = load("res://project/shaders/terrain.gdshader") as Shader


func set_slope_overlay(on: bool) -> void:
	_show_slope = on
	_set_all("show_slope", _show_slope)


func set_brush(on: bool, center: Vector2, radius: float, falloff: float, square: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat == null:
				continue
			mat.set_shader_parameter("brush_on", on)
			mat.set_shader_parameter("brush_center", center)
			mat.set_shader_parameter("brush_radius", radius)
			mat.set_shader_parameter("brush_falloff", falloff)
			mat.set_shader_parameter("brush_shape", 1 if square else 0)


func set_water_level(level: float) -> void:
	_set_all("water_level", level)


func set_show_grid(on: bool) -> void:
	_set_all("show_grid", on)


func refresh_materials() -> void:
	var colors := _palette_colors()
	var atlas := _load_atlas()
	var uvs := _atlas_uvs()
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


func _load_atlas() -> Texture2D:
	for world in MapState.worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		if str(world.get("id", "")).to_lower() != MapState.world.to_lower():
			continue
		var path := str(world.get("atlas_image", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			return null
		var img := Image.load_from_file(path)
		if img == null:
			return null
		return ImageTexture.create_from_image(img)
	return null


func _atlas_uvs() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(16)
	for i in 16:
		out[i] = Vector4(0.0, 0.0, 0.125, 0.125)
	for world in MapState.worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		if str(world.get("id", "")).to_lower() != MapState.world.to_lower():
			continue
		var uvs: Array = world.get("tile_uvs", [])
		for i in mini(16, uvs.size()):
			var r: Array = uvs[i]
			if r.size() >= 4:
				out[i] = Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return out


func _set_all(name: String, value: Variant) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter(name, value)


func _palette_colors() -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(16)
	var defaults := [
		Color(0.55, 0.42, 0.28), Color(0.45, 0.48, 0.30), Color(0.40, 0.40, 0.40),
		Color(0.62, 0.55, 0.38), Color(0.30, 0.35, 0.22), Color(0.70, 0.68, 0.60),
		Color(0.50, 0.32, 0.22), Color(0.28, 0.30, 0.38),
	]
	for i in 16:
		colors[i] = defaults[i % defaults.size()]
	for world in MapState.worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		if str(world.get("id", "")).to_lower() != MapState.world.to_lower():
			continue
		var types: Array = world.get("texture_types", [])
		for t in types:
			if typeof(t) != TYPE_DICTIONARY:
				continue
			var idx := int(t.get("index", 0))
			var rgb: Array = t.get("flat_color", [128, 128, 128])
			if idx >= 0 and idx < 16 and rgb.size() >= 3:
				colors[idx] = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	return colors


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
	mat.set_shader_parameter("mat_colors", _palette_colors())
	mat.set_shader_parameter("show_materials", MapState.mat_grid_x > 0)
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
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	return st.commit()
