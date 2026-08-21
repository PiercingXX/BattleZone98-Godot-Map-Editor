extends RefCounted
class_name HeightField
## CPU height array + GPU FORMAT_RF texture. All height writes go through here.
##
## GPU uploads are coalesced: upload_rect() writes FORMAT_RF bytes for the
## dirty cells; flush_upload() pushes the image to the GPU once per frame
## (or immediately from write_rect / load). Never Image.set_pixel.

const CELL_M := 5.0
const HEIGHT_SCALE := 0.1

var grid_x: int = 0
var grid_z: int = 0
var heights: PackedInt32Array = PackedInt32Array()
var image: Image
var texture: ImageTexture
## Bytes uploaded by the last flush_upload(); 0 if the GPU was already current.
var last_uploaded: int = 0

var _rf: PackedByteArray = PackedByteArray()
var _gpu_dirty: bool = false
var _dirty_x0: int = 0
var _dirty_z0: int = 0
var _dirty_x1: int = -1
var _dirty_z1: int = -1


func load_r16(path: String, p_grid_x: int, p_grid_z: int) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	grid_x = p_grid_x
	grid_z = p_grid_z
	var n := grid_x * grid_z
	if file.get_length() < n * 2:
		return ERR_FILE_CORRUPT
	var buf := file.get_buffer(n * 2)
	heights.resize(n)
	for i in n:
		heights[i] = buf.decode_u16(i * 2)
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


func write_rect(x0: int, z0: int, w: int, d: int, values: PackedInt32Array) -> void:
	if grid_x < 1:
		return
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if x < 0 or z < 0 or x >= grid_x or z >= grid_z:
				i += 1
				continue
			heights[z * grid_x + x] = values[i]
			i += 1
	upload_rect(x0, z0, w, d)
	flush_upload()


func upload_rect(x0: int, z0: int, w: int, d: int) -> void:
	if grid_x < 1 or grid_z < 1 or w < 1 or d < 1:
		return
	if image == null or _rf.size() != grid_x * grid_z * 4:
		_rebuild_texture()
		return
	x0 = clampi(x0, 0, grid_x - 1)
	z0 = clampi(z0, 0, grid_z - 1)
	var x1 := mini(grid_x - 1, x0 + w - 1)
	var z1 := mini(grid_z - 1, z0 + d - 1)
	if x1 < x0 or z1 < z0:
		return
	_sync_rf_rect(x0, z0, x1, z1)
	_union_dirty(x0, z0, x1, z1)
	_gpu_dirty = true


func flush_upload() -> int:
	last_uploaded = 0
	if grid_x < 1 or grid_z < 1:
		return 0
	if image == null or _rf.size() != grid_x * grid_z * 4:
		_rebuild_texture()
		last_uploaded = grid_x * grid_z * 4
		return last_uploaded
	if not _gpu_dirty:
		return 0
	image.set_data(grid_x, grid_z, false, Image.FORMAT_RF, _rf)
	if texture == null or texture.get_width() != grid_x or texture.get_height() != grid_z:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	var bytes := (_dirty_x1 - _dirty_x0 + 1) * (_dirty_z1 - _dirty_z0 + 1) * 4
	last_uploaded = maxi(bytes, 0)
	_gpu_dirty = false
	_dirty_x0 = 0
	_dirty_z0 = 0
	_dirty_x1 = -1
	_dirty_z1 = -1
	return last_uploaded


func write_r16(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var n := heights.size()
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		buf.encode_u16(i * 2, heights[i] & 0xFFFF)
	file.store_buffer(buf)
	return OK


func _rebuild_texture() -> void:
	var n := grid_x * grid_z
	if n < 1:
		image = null
		texture = null
		_rf = PackedByteArray()
		_gpu_dirty = false
		return
	_rf.resize(n * 4)
	for i in n:
		_rf.encode_float(i * 4, float(heights[i]) * HEIGHT_SCALE)
	image = Image.create_from_data(grid_x, grid_z, false, Image.FORMAT_RF, _rf)
	if texture == null or texture.get_width() != grid_x or texture.get_height() != grid_z:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	_gpu_dirty = false
	_dirty_x0 = 0
	_dirty_z0 = 0
	_dirty_x1 = -1
	_dirty_z1 = -1


func _sync_rf_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	var gx := grid_x
	for z in range(z0, z1 + 1):
		var row := z * gx
		for x in range(x0, x1 + 1):
			_rf.encode_float((row + x) * 4, float(heights[row + x]) * HEIGHT_SCALE)


func _union_dirty(x0: int, z0: int, x1: int, z1: int) -> void:
	if _dirty_x1 < _dirty_x0:
		_dirty_x0 = x0
		_dirty_z0 = z0
		_dirty_x1 = x1
		_dirty_z1 = z1
		return
	_dirty_x0 = mini(_dirty_x0, x0)
	_dirty_z0 = mini(_dirty_z0, z0)
	_dirty_x1 = maxi(_dirty_x1, x1)
	_dirty_z1 = maxi(_dirty_z1, z1)
