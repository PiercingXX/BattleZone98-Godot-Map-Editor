extends RefCounted
class_name HeightField
## CPU height array + GPU FORMAT_RF texture. All height writes go through here.
##
## GPU uploads are coalesced: upload_rect() unions a dirty rect; flush_upload()
## re-encodes only that rect, blits it into the image and pushes the texture
## once per frame (or immediately from write_rect / load). Never Image.set_pixel.
##
## Godot 4.7 has no partial 2D texture upload: RenderingServer only exposes
## texture_2d_update() for a whole image, and the RD texture behind an
## ImageTexture is created without CAN_COPY_TO, so texture_copy() into it is
## refused. The driver still gets the whole grid. What the rect does buy is the
## CPU side — handing a whole-grid buffer to Image.set_data() aliases it into
## the image, which made every following encode copy-on-write the whole grid.

## Emitted after upload_rect() unions a dirty cell rect, with the clamped
## INCLUSIVE cell bounds. Derived caches (the min/max range map) rebuild only
## the blocks the rect touches instead of rescanning the grid.
signal rect_dirty(x0: int, z0: int, x1: int, z1: int)
## Emitted when the whole field is re-encoded (load or resize), so derived
## caches drop everything rather than trying to patch.
signal rebuilt()

const CELL_M := 5.0
const HEIGHT_SCALE := 0.1

var grid_x: int = 0
var grid_z: int = 0
var heights: PackedInt32Array = PackedInt32Array()
var image: Image
var texture: ImageTexture
## Bytes uploaded by the last flush_upload(); 0 if the GPU was already current.
var last_uploaded: int = 0

## Dirty-rect staging. Grows to the largest rect seen and is then reused, so a
## steady brush stamp allocates nothing per frame.
var _patch: Image
var _patch_rf: PackedByteArray = PackedByteArray()
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
	if not _image_matches_grid():
		_rebuild_texture()
		return
	x0 = clampi(x0, 0, grid_x - 1)
	z0 = clampi(z0, 0, grid_z - 1)
	var x1 := mini(grid_x - 1, x0 + w - 1)
	var z1 := mini(grid_z - 1, z0 + d - 1)
	if x1 < x0 or z1 < z0:
		return
	_union_dirty(x0, z0, x1, z1)
	_gpu_dirty = true
	rect_dirty.emit(x0, z0, x1, z1)


func flush_upload() -> int:
	last_uploaded = 0
	if grid_x < 1 or grid_z < 1:
		return 0
	if not _image_matches_grid():
		_rebuild_texture()
		last_uploaded = grid_x * grid_z * 4
		return last_uploaded
	if not _gpu_dirty or _dirty_x1 < _dirty_x0:
		_clear_dirty()
		return 0
	var w := _dirty_x1 - _dirty_x0 + 1
	var d := _dirty_z1 - _dirty_z0 + 1
	_blit_rect(_dirty_x0, _dirty_z0, w, d)
	if texture == null or texture.get_width() != grid_x or texture.get_height() != grid_z:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	last_uploaded = w * d * 4
	_clear_dirty()
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


func _image_matches_grid() -> bool:
	return image != null and image.get_width() == grid_x and image.get_height() == grid_z


func _rebuild_texture() -> void:
	var n := grid_x * grid_z
	if n < 1:
		image = null
		texture = null
		_patch = null
		_patch_rf = PackedByteArray()
		_clear_dirty()
		rebuilt.emit()
		return
	# Only load and resize get here, so the full encode is not a per-frame cost.
	# rf is local so the image owns its bytes outright once we return; sharing
	# a member buffer would make the next blit copy-on-write the whole grid.
	var rf := PackedByteArray()
	rf.resize(n * 4)
	for i in n:
		rf.encode_float(i * 4, float(heights[i]) * HEIGHT_SCALE)
	image = Image.create_from_data(grid_x, grid_z, false, Image.FORMAT_RF, rf)
	if texture == null or texture.get_width() != grid_x or texture.get_height() != grid_z:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	_clear_dirty()
	rebuilt.emit()


func _blit_rect(x0: int, z0: int, w: int, d: int) -> void:
	var need := w * d * 4
	if _patch_rf.size() != need:
		_patch_rf.resize(need)
	var i := 0
	for z in range(z0, z0 + d):
		var row := z * grid_x
		for x in range(x0, x0 + w):
			_patch_rf.encode_float(i, float(heights[row + x]) * HEIGHT_SCALE)
			i += 4
	if _patch == null:
		_patch = Image.create_from_data(w, d, false, Image.FORMAT_RF, _patch_rf)
	else:
		_patch.set_data(w, d, false, Image.FORMAT_RF, _patch_rf)
	image.blit_rect(_patch, Rect2i(0, 0, w, d), Vector2i(x0, z0))


func _clear_dirty() -> void:
	_gpu_dirty = false
	_dirty_x0 = 0
	_dirty_z0 = 0
	_dirty_x1 = -1
	_dirty_z1 = -1


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
