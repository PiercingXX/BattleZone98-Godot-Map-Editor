extends RefCounted
class_name HeightField
## CPU height array + GPU FORMAT_RF texture. All height writes go through here.

const CELL_M := 5.0
const HEIGHT_SCALE := 0.1

var grid_x: int = 0
var grid_z: int = 0
var heights: PackedInt32Array = PackedInt32Array()
var image: Image
var texture: ImageTexture


func load_r16(path: String, p_grid_x: int, p_grid_z: int) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	grid_x = p_grid_x
	grid_z = p_grid_z
	var n := grid_x * grid_z
	if file.get_length() < n * 2:
		return ERR_FILE_CORRUPT
	heights.resize(n)
	for i in n:
		heights[i] = file.get_16()
	_rebuild_texture()
	return OK


func height_raw(x: int, z: int) -> int:
	x = clampi(x, 0, grid_x - 1)
	z = clampi(z, 0, grid_z - 1)
	return heights[z * grid_x + x]


func height_m(x: int, z: int) -> float:
	return float(height_raw(x, z)) * HEIGHT_SCALE


func height_at(x_m: float, z_m: float) -> float:
	if grid_x < 2 or grid_z < 2:
		return 0.0
	var gx := x_m / CELL_M
	var gz := z_m / CELL_M
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var h00 := height_m(x0, z0)
	var h10 := height_m(x0 + 1, z0)
	var h01 := height_m(x0, z0 + 1)
	var h11 := height_m(x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _rebuild_texture() -> void:
	var floats := PackedFloat32Array()
	var n := grid_x * grid_z
	floats.resize(n)
	for i in n:
		floats[i] = float(heights[i]) * HEIGHT_SCALE
	image = Image.create_from_data(grid_x, grid_z, false, Image.FORMAT_RF, floats.to_byte_array())
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
