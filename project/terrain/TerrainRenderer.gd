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
	for child in get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("show_slope", _show_slope)


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
