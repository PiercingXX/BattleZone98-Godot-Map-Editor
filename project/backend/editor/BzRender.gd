extends RefCounted
class_name BzRender
## Port of preview.py + thumbnail.py + debug_map.py + render_cmd.py.
##
## North-up is load-bearing (docs/02 §1): world +z is the TOP of every image,
## +x is right. The generator repo once shipped a vertical mirror; do not.
##
## PIL → Godot Image. PNGs go through Image.save_png. BMP is written by hand
## (Godot has no Image.save_bmp) as uncompressed 24-bit BI_RGB, matching the
## workshop container thumbnail.py emits.
##
## debug_map.py features that only served the generator (CLI main, TrueType
## legend glyphs) are not ported. Public functions the render verb and the
## debug overlay use are here.

const THUMBNAIL_SIZE: Vector2i = Vector2i(512, 512)

## Terrain colour ramp (preview.py _TERRAIN): deep → peak.
const _RAMP_R: Array[float] = [20.0, 40.0, 70.0, 150.0, 200.0, 235.0]
const _RAMP_G: Array[float] = [40.0, 90.0, 130.0, 170.0, 190.0, 235.0]
const _RAMP_B: Array[float] = [90.0, 140.0, 90.0, 90.0, 160.0, 235.0]
const _RAMP_X: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

## debug_map.py _CLASSES: prefix → [legend label, r, g, b]
const _CLASS_PREFIX: Array[String] = [
	"player", "avtank", "pspwn", "eggeizr", "npscr", "sscr", "blc-pell",
	"abhang", "absupp",
]
const _CLASS_LABEL: Array[String] = [
	"player / user", "player (avtank)", "spawn point", "geyser", "scrap",
	"scrap", "scrap", "hangar", "supply",
]
const _CLASS_R: Array[int] = [255, 255, 0, 255, 255, 255, 255, 255, 200]
const _CLASS_G: Array[int] = [255, 255, 220, 230, 140, 140, 140, 0, 0]
const _CLASS_B: Array[int] = [255, 255, 255, 0, 0, 0, 0, 200, 255]

static var _CM: PackedByteArray = PackedByteArray()


static func _colormap() -> PackedByteArray:
	if _CM.size() == 768:
		return _CM
	_CM.resize(768)
	for i in 256:
		var t: float = float(i) / 255.0
		_CM[i * 3] = int(_interp(t, _RAMP_X, _RAMP_R))
		_CM[i * 3 + 1] = int(_interp(t, _RAMP_X, _RAMP_G))
		_CM[i * 3 + 2] = int(_interp(t, _RAMP_X, _RAMP_B))
	return _CM


static func _interp(t: float, xs: Array[float], ys: Array[float]) -> float:
	## numpy.interp — linear, clamped to the xp ends.
	var n: int = xs.size()
	if t <= xs[0]:
		return ys[0]
	if t >= xs[n - 1]:
		return ys[n - 1]
	for i in range(1, n):
		if t <= xs[i]:
			var span: float = xs[i] - xs[i - 1]
			if span == 0.0:
				return ys[i]
			var u: float = (t - xs[i - 1]) / span
			return ys[i - 1] + u * (ys[i] - ys[i - 1])
	return ys[n - 1]


static func _as_size(size: Variant, fallback: Vector2i) -> Vector2i:
	if size == null:
		return fallback
	if size is Vector2i:
		return size
	if size is Vector2:
		return Vector2i(int((size as Vector2).x), int((size as Vector2).y))
	if size is Array or size is PackedInt32Array or size is PackedFloat32Array:
		if size.size() >= 2:
			return Vector2i(int(size[0]), int(size[1]))
	return fallback


static func _unwrap(heightmap: Variant) -> Variant:
	if typeof(heightmap) == TYPE_DICTIONARY:
		var d: Dictionary = heightmap
		if d.has("heightmap") and d.get("ok", true):
			return d.get("heightmap")
	return heightmap


static func _as_int32(values: Variant) -> PackedInt32Array:
	if values is PackedInt32Array:
		return values
	if values is PackedByteArray:
		var bytes: PackedByteArray = values
		var out := PackedInt32Array()
		out.resize(bytes.size() / 2)
		for i in out.size():
			out[i] = bytes.decode_u16(i * 2)
		return out
	if values is Array:
		var out2 := PackedInt32Array()
		for v in values:
			out2.append(int(v))
		return out2
	return PackedInt32Array()


static func _coerce(heightmap: Variant) -> Dictionary:
	## Normalise a BzHg2.HeightMap / dict / duck-typed object to a grid dict.
	heightmap = _unwrap(heightmap)
	if typeof(heightmap) == TYPE_DICTIONARY:
		var d: Dictionary = heightmap
		if d.has("data") and d.has("grid_x"):
			var gx: int = int(d.get("grid_x", 0))
			var gz: int = int(d.get("grid_z", 0))
			return {
				"data": _as_int32(d.get("data")),
				"grid_x": gx,
				"grid_z": gz,
				"width_m": float(d.get("width_m", float(gx) * BzHg2.GRID_M)),
				"depth_m": float(d.get("depth_m", float(gz) * BzHg2.GRID_M)),
			}
	if heightmap is Object:
		var o: Object = heightmap
		var data_v: Variant = o.get("data")
		var gx2: int = int(o.get("grid_x"))
		var gz2: int = int(o.get("grid_z"))
		var width_m: float = float(gx2) * BzHg2.GRID_M
		var depth_m: float = float(gz2) * BzHg2.GRID_M
		if o.get("width_m") != null:
			width_m = float(o.get("width_m"))
		if o.get("depth_m") != null:
			depth_m = float(o.get("depth_m"))
		return {
			"data": _as_int32(data_v),
			"grid_x": gx2,
			"grid_z": gz2,
			"width_m": width_m,
			"depth_m": depth_m,
		}
	return {
		"data": PackedInt32Array(),
		"grid_x": 0,
		"grid_z": 0,
		"width_m": 0.0,
		"depth_m": 0.0,
	}


static func _gradient_hypot(metres: PackedFloat64Array, gx: int, gz: int) -> PackedFloat64Array:
	## numpy.gradient(raw, GRID_M, GRID_M) then hypot(dx, dz). Same as BzHg2.slope.
	var n: int = gx * gz
	var d_ax0 := PackedFloat64Array()
	var d_ax1 := PackedFloat64Array()
	d_ax0.resize(n)
	d_ax1.resize(n)
	var spacing: float = BzHg2.GRID_M
	if gz == 1:
		for x in gx:
			d_ax0[x] = 0.0
	else:
		for x in gx:
			d_ax0[x] = (metres[gx + x] - metres[x]) / spacing
			d_ax0[(gz - 1) * gx + x] = (
				metres[(gz - 1) * gx + x] - metres[(gz - 2) * gx + x]
			) / spacing
		for z in range(1, gz - 1):
			var row: int = z * gx
			for x2 in gx:
				d_ax0[row + x2] = (
					metres[(z + 1) * gx + x2] - metres[(z - 1) * gx + x2]
				) / (2.0 * spacing)
	if gx == 1:
		for z2 in gz:
			d_ax1[z2] = 0.0
	else:
		for z3 in gz:
			var row2: int = z3 * gx
			d_ax1[row2] = (metres[row2 + 1] - metres[row2]) / spacing
			d_ax1[row2 + gx - 1] = (
				metres[row2 + gx - 1] - metres[row2 + gx - 2]
			) / spacing
			for x3 in range(1, gx - 1):
				d_ax1[row2 + x3] = (
					metres[row2 + x3 + 1] - metres[row2 + x3 - 1]
				) / (2.0 * spacing)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = sqrt(d_ax1[i] * d_ax1[i] + d_ax0[i] * d_ax0[i])
	return out


static func render_heightmap(heightmap: Variant, size: Variant = null) -> Image:
	## Hillshaded, height-coloured top-down RGB image. North-up: +z is TOP.
	var hm: Dictionary = _coerce(heightmap)
	var gx: int = int(hm["grid_x"])
	var gz: int = int(hm["grid_z"])
	var target: Vector2i = _as_size(size, Vector2i(gx, gz))
	if target.x < 1:
		target.x = 1
	if target.y < 1:
		target.y = 1
	if gx < 1 or gz < 1:
		return Image.create_empty(target.x, target.y, false, Image.FORMAT_RGB8)
	var data: PackedInt32Array = hm["data"]
	var n: int = gx * gz
	var metres := PackedFloat64Array()
	metres.resize(n)
	var limit: int = mini(n, data.size())
	for i in limit:
		metres[i] = float(data[i]) * BzHg2.HEIGHT_SCALE
	var grad: PackedFloat64Array = _gradient_hypot(metres, gx, gz)
	var cm: PackedByteArray = _colormap()
	var rgb := PackedByteArray()
	rgb.resize(n * 3)
	for z in gz:
		var dst_z: int = gz - 1 - z
		var src_row: int = z * gx
		var dst_row: int = dst_z * gx
		for x in gx:
			var i2: int = src_row + x
			var shade: float = 1.0 / (1.0 + grad[i2])
			# preview.py: ((metres / 4095) * 255).astype(np.uint8) — wraps, no clamp.
			var idx: int = int((metres[i2] / 4095.0) * 255.0) & 0xFF
			var di: int = (dst_row + x) * 3
			var ci: int = idx * 3
			rgb[di] = int(float(cm[ci]) * shade)
			rgb[di + 1] = int(float(cm[ci + 1]) * shade)
			rgb[di + 2] = int(float(cm[ci + 2]) * shade)
	var img: Image = Image.create_from_data(gx, gz, false, Image.FORMAT_RGB8, rgb)
	if target.x != gx or target.y != gz:
		img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	return img


static func _world_to_px(hm: Dictionary, size: Vector2i, x: float, z: float) -> Vector2i:
	## North-up: z = 0 is the BOTTOM row, matching render_heightmap.
	var w: int = size.x
	var h: int = size.y
	var width_m: float = float(hm.get("width_m", 0.0))
	var depth_m: float = float(hm.get("depth_m", 0.0))
	var col: float = 0.0
	if width_m != 0.0:
		col = x / width_m * float(w - 1)
	var row: float = 0.0
	if depth_m != 0.0:
		row = (1.0 - z / depth_m) * float(h - 1)
	return Vector2i(int(round(col)), int(round(row)))


static func _as_color(color: Variant, fallback: Color) -> Color:
	if color is Color:
		return color
	if color is Array or color is PackedInt32Array or color is PackedByteArray:
		var r: int = 0
		var g: int = 0
		var b: int = 0
		if color.size() > 0:
			r = int(color[0])
		if color.size() > 1:
			g = int(color[1])
		if color.size() > 2:
			b = int(color[2])
		return Color8(clampi(r, 0, 255), clampi(g, 0, 255), clampi(b, 0, 255))
	return fallback


static func _xz_of(point: Variant) -> Vector2:
	if point is Vector2:
		return point
	if point is Vector3:
		return Vector2((point as Vector3).x, (point as Vector3).z)
	if point is Array or point is PackedFloat32Array or point is PackedFloat64Array:
		var x: float = 0.0
		var z: float = 0.0
		if point.size() > 0:
			x = float(point[0])
		if point.size() > 1:
			z = float(point[1])
		return Vector2(x, z)
	if typeof(point) == TYPE_DICTIONARY:
		var d: Dictionary = point
		return Vector2(float(d.get("x", 0.0)), float(d.get("z", 0.0)))
	return Vector2.ZERO


static func _ensure_parent(path: String) -> void:
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)


static func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return path.simplify_path()
	return cwd.get_current_dir().path_join(path).simplify_path()


static func _resized(img: Image, size: Vector2i, interp: Image.Interpolation) -> Image:
	if img == null:
		return Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGB8)
	if img.get_width() == size.x and img.get_height() == size.y:
		return img
	var copy: Image = img.duplicate()
	copy.resize(maxi(size.x, 1), maxi(size.y, 1), interp)
	return copy


static func _save_png_raw(img: Image, path: String) -> Dictionary:
	if img == null:
		return BzErrors.err("write_failed", "no image to write: %s" % path, "", path)
	_ensure_parent(path)
	var err: Error = img.save_png(path)
	if err != OK:
		return BzErrors.err(
			"write_failed",
			"cannot write PNG %s (%s)" % [path, error_string(err)],
			"",
			path
		)
	return {"ok": true, "path": path}


static func _image_to_bmp(img: Image) -> PackedByteArray:
	## Uncompressed 24-bit BMP (thumbnail.py format="BMP"). Bottom-up BGR.
	var work: Image = img
	if work.get_format() != Image.FORMAT_RGB8:
		work = img.duplicate()
		work.convert(Image.FORMAT_RGB8)
	var w: int = work.get_width()
	var h: int = work.get_height()
	var row_stride: int = (w * 3 + 3) & ~3
	var pixel_size: int = row_stride * h
	var file_size: int = 14 + 40 + pixel_size
	var out := PackedByteArray()
	out.resize(file_size)
	out[0] = 0x42
	out[1] = 0x4D
	out.encode_u32(2, file_size)
	out.encode_u32(6, 0)
	out.encode_u32(10, 54)
	out.encode_u32(14, 40)
	out.encode_s32(18, w)
	out.encode_s32(22, h)
	out.encode_u16(26, 1)
	out.encode_u16(28, 24)
	out.encode_u32(30, 0)
	out.encode_u32(34, pixel_size)
	out.encode_s32(38, 0)
	out.encode_s32(42, 0)
	out.encode_u32(46, 0)
	out.encode_u32(50, 0)
	var src: PackedByteArray = work.get_data()
	for row in h:
		var img_row: int = h - 1 - row
		var dst: int = 54 + row * row_stride
		var src_row: int = img_row * w * 3
		for x in w:
			var si: int = src_row + x * 3
			var di: int = dst + x * 3
			out[di] = src[si + 2]
			out[di + 1] = src[si + 1]
			out[di + 2] = src[si]
	return out


static func write_png(img: Image, path: String, size: Variant = null) -> Dictionary:
	## Resize to size (default THUMBNAIL_SIZE) and write PNG.
	var sz: Vector2i = _as_size(size, THUMBNAIL_SIZE)
	var out: Image = _resized(img, sz, Image.INTERPOLATE_LANCZOS)
	return _save_png_raw(out, path)


static func write_bmp(img: Image, path: String, size: Variant = null) -> Dictionary:
	## Resize to size (default THUMBNAIL_SIZE) and write BMP.
	var sz: Vector2i = _as_size(size, THUMBNAIL_SIZE)
	var out: Image = _resized(img, sz, Image.INTERPOLATE_LANCZOS)
	_ensure_parent(path)
	var bytes: PackedByteArray = _image_to_bmp(out)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return BzErrors.err(
			"write_failed",
			"cannot write BMP %s (%s)" % [path, error_string(FileAccess.get_open_error())],
			"",
			path
		)
	file.store_buffer(bytes)
	file.close()
	return {"ok": true, "path": path}


static func write_thumbnail(
	img: Image, png_path: String, bmp_path: String, size: Variant = null
) -> Dictionary:
	## Write both the PNG and BMP thumbnails from img at size.
	var sz: Vector2i = _as_size(size, THUMBNAIL_SIZE)
	var resized: Image = _resized(img, sz, Image.INTERPOLATE_LANCZOS)
	var png: Dictionary = _save_png_raw(resized, png_path)
	if BzErrors.is_err(png):
		return png
	var bmp: Dictionary = write_bmp(resized, bmp_path, sz)
	if BzErrors.is_err(bmp):
		return bmp
	return {"ok": true, "png": png_path, "bmp": bmp_path}


class Preview:
	extends RefCounted
	## Shaded heightmap image plus overlay drawing helpers (preview.py Preview).

	var heightmap: Variant
	var size: Vector2i = Vector2i(1, 1)
	var image: Image
	var _grid: Dictionary = {}

	func _init(p_heightmap: Variant = null, p_size: Variant = null) -> void:
		if p_heightmap == null:
			heightmap = null
			image = Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
			return
		heightmap = p_heightmap
		_grid = BzRender._coerce(p_heightmap)
		size = BzRender._as_size(
			p_size, Vector2i(int(_grid.get("grid_x", 1)), int(_grid.get("grid_z", 1)))
		)
		image = BzRender.render_heightmap(_grid, size)

	func _px(x: float, z: float) -> Vector2i:
		return BzRender._world_to_px(_grid, size, x, z)

	func _fill_disk(cx: int, cy: int, radius: int, color: Color) -> void:
		if image == null:
			return
		var w: int = image.get_width()
		var h: int = image.get_height()
		var r2: int = radius * radius
		for py in range(cy - radius, cy + radius + 1):
			if py < 0 or py >= h:
				continue
			for px in range(cx - radius, cx + radius + 1):
				if px < 0 or px >= w:
					continue
				var dx: int = px - cx
				var dy: int = py - cy
				if dx * dx + dy * dy <= r2:
					image.set_pixel(px, py, color)

	func draw_points(points: Array, color: Variant = null, radius: int = 3) -> void:
		## Filled circles at world (x, z) points.
		var col: Color = BzRender._as_color(color, Color8(255, 0, 0))
		for p in points:
			var xz: Vector2 = BzRender._xz_of(p)
			var px: Vector2i = _px(xz.x, xz.y)
			_fill_disk(px.x, px.y, radius, col)

	func draw_routes(routes: Array, color: Variant = null, width: int = 2) -> void:
		## Polylines; routes is a list of [(x, z), ...] point lists.
		var col: Color = BzRender._as_color(color, Color8(255, 255, 0))
		var rad: int = maxi(1, width / 2)
		for pts in routes:
			if not (pts is Array) or (pts as Array).size() < 2:
				continue
			var px_list: Array = []
			for p in pts:
				var xz: Vector2 = BzRender._xz_of(p)
				px_list.append(_px(xz.x, xz.y))
			for i in range(px_list.size() - 1):
				var a: Vector2i = px_list[i]
				var b: Vector2i = px_list[i + 1]
				var dx: int = b.x - a.x
				var dy: int = b.y - a.y
				var steps: int = maxi(absi(dx), absi(dy))
				if steps == 0:
					_fill_disk(a.x, a.y, rad, col)
					continue
				for s in range(steps + 1):
					var t: float = float(s) / float(steps)
					var x: int = int(round(float(a.x) + t * float(dx)))
					var y: int = int(round(float(a.y) + t * float(dy)))
					_fill_disk(x, y, rad, col)

	func draw_regions(regions: Array, color: Variant = null, alpha: int = 60) -> void:
		## Tint grid-shaped boolean masks over the image.
		if image == null or regions.is_empty():
			return
		var tint: Color = BzRender._as_color(color, Color8(0, 255, 0))
		var tr: int = tint.r8
		var tg: int = tint.g8
		var tb: int = tint.b8
		var gx: int = int(_grid.get("grid_x", 0))
		var gz: int = int(_grid.get("grid_z", 0))
		if gx < 1 or gz < 1:
			return
		if image.get_format() != Image.FORMAT_RGB8:
			image.convert(Image.FORMAT_RGB8)
		var base: PackedByteArray = image.get_data()
		var iw: int = image.get_width()
		var ih: int = image.get_height()
		var keep: int = 255 - clampi(alpha, 0, 255)
		var a: int = clampi(alpha, 0, 255)
		for mask_v in regions:
			var m: PackedByteArray = BzRender._as_mask(mask_v, gx, gz)
			if m.size() != gx * gz:
				# Python raises ValueError on shape mismatch; no exceptions here.
				continue
			var flipped := PackedByteArray()
			flipped.resize(gx * gz)
			for z in gz:
				var src_row: int = (gz - 1 - z) * gx
				var dst_row: int = z * gx
				for x in gx:
					flipped[dst_row + x] = 255 if m[src_row + x] != 0 else 0
			var mi: Image = Image.create_from_data(gx, gz, false, Image.FORMAT_L8, flipped)
			if iw != gx or ih != gz:
				mi.resize(iw, ih, Image.INTERPOLATE_NEAREST)
			var mpx: PackedByteArray = mi.get_data()
			var pix: int = iw * ih
			for i in pix:
				if mpx[i] > 127:
					var di: int = i * 3
					base[di] = (int(base[di]) * keep + tr * a) / 255
					base[di + 1] = (int(base[di + 1]) * keep + tg * a) / 255
					base[di + 2] = (int(base[di + 2]) * keep + tb * a) / 255
		image = Image.create_from_data(iw, ih, false, Image.FORMAT_RGB8, base)

	func save(path: String) -> Dictionary:
		## Write the preview to path as PNG.
		return BzRender._save_png_raw(image, path)


static func _as_mask(mask: Variant, gx: int, gz: int) -> PackedByteArray:
	var n: int = gx * gz
	var out := PackedByteArray()
	if mask is PackedByteArray:
		var pb: PackedByteArray = mask
		if pb.size() == n:
			return pb
	if mask is PackedInt32Array:
		var pi: PackedInt32Array = mask
		out.resize(n)
		var lim: int = mini(n, pi.size())
		for i in lim:
			out[i] = 1 if pi[i] != 0 else 0
		return out
	if mask is Array:
		var arr: Array = mask
		out.resize(n)
		if arr.is_empty():
			return out
		if typeof(arr[0]) == TYPE_ARRAY or arr[0] is PackedByteArray or arr[0] is PackedInt32Array:
			var i2: int = 0
			for row in arr:
				for v in row:
					if i2 >= n:
						return out
					out[i2] = 1 if int(v) != 0 else 0
					i2 += 1
			return out
		var lim2: int = mini(n, arr.size())
		for i3 in lim2:
			out[i3] = 1 if int(arr[i3]) != 0 else 0
		return out
	return out


static func render_preview(
	heightmap: Variant,
	objects: Variant = null,
	routes: Variant = null,
	regions: Variant = null,
	size: Variant = null
) -> Preview:
	## Shaded terrain plus optional overlays. Returns a Preview.
	var pv := Preview.new(heightmap, size)
	if regions is Array and not (regions as Array).is_empty():
		pv.draw_regions(regions)
	if routes is Array and not (routes as Array).is_empty():
		pv.draw_routes(routes)
	if objects is Array and not (objects as Array).is_empty():
		pv.draw_points(objects)
	return pv


static func _mask_any(mask: PackedByteArray) -> bool:
	for i in mask.size():
		if mask[i] != 0:
			return true
	return false


static func render_map_image(
	heightmap: Variant, water_mask: Variant = null, size: Variant = null
) -> Image:
	## Clean top-down map (shaded terrain + blue water tint), no dots/legend.
	var hm: Dictionary = _coerce(heightmap)
	var gx: int = int(hm.get("grid_x", 0))
	var gz: int = int(hm.get("grid_z", 0))
	var sz: Variant = size
	if sz == null:
		sz = Vector2i(gx, gz)
	var pv := Preview.new(heightmap, sz)
	if water_mask != null:
		var m: PackedByteArray = _as_mask(water_mask, gx, gz)
		if _mask_any(m):
			pv.draw_regions([m], [40, 120, 255], 150)
	return pv.image


static func _find(directory: String, filename: String) -> String:
	var da := DirAccess.open(directory)
	if da == null:
		return ""
	var target: String = filename.to_lower()
	for name in da.get_files():
		if str(name).to_lower() == target:
			return directory.path_join(str(name))
	return ""


static func _class_of(prjid: String) -> Dictionary:
	var low: String = prjid.to_lower()
	for i in _CLASS_PREFIX.size():
		if low.begins_with(_CLASS_PREFIX[i]):
			return {
				"label": _CLASS_LABEL[i],
				"color": Color8(_CLASS_R[i], _CLASS_G[i], _CLASS_B[i]),
			}
	return {"label": "other/mesh", "color": Color8(140, 140, 140)}


static func _bzn_objects(path: String) -> Array:
	## Yield-like array of {prjid, x, z, team} for every ASCII [GameObject].
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var text: String = FileAccess.get_file_as_string(path).replace("\r", "")
	var re_pid := RegEx.new()
	var re_x := RegEx.new()
	var re_z := RegEx.new()
	var re_tm := RegEx.new()
	re_pid.compile("(?m)^PrjID \\[1\\] =\\n(.*)$")
	re_x.compile("(?m)^  x \\[1\\] =\\n(\\S+)")
	re_z.compile("(?m)^  z \\[1\\] =\\n(\\S+)")
	re_tm.compile("(?m)^team \\[1\\] =\\n(\\d+)")
	var parts: PackedStringArray = text.split("[GameObject]")
	for i in range(1, parts.size()):
		var block: String = parts[i]
		var pid_m: RegExMatch = re_pid.search(block)
		if pid_m == null:
			continue
		var xm: RegExMatch = re_x.search(block)
		var zm: RegExMatch = re_z.search(block)
		if xm == null or zm == null:
			continue
		var team: int = 0
		var tm: RegExMatch = re_tm.search(block)
		if tm != null:
			team = int(tm.get_string(1))
		out.append({
			"prjid": pid_m.get_string(1),
			"x": float(xm.get_string(1)),
			"z": float(zm.get_string(1)),
			"team": team,
		})
	return out


static func _is_water_mesh(mesh: String) -> bool:
	var mat: String = mesh.get_basename() + ".material"
	if not FileAccess.file_exists(mat):
		return false
	return FileAccess.get_file_as_string(mat).contains("thecavew")


static func _water_footprint(mesh_path: String, hm: Dictionary) -> Variant:
	## Boolean grid of the water mesh XZ footprint, or null. debug_map.py walk.
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(mesh_path)
	if raw.size() < 16:
		return null
	var nl: int = -1
	for i in range(2, raw.size()):
		if raw[i] == 0x0A:
			nl = i + 1
			break
	if nl < 0 or nl + 6 > raw.size():
		return null
	if raw.decode_u16(nl) != 0x3000:
		return null
	var p: int = nl + 6 + 1
	if p + 6 > raw.size():
		return null
	if raw.decode_u16(p) != 0x4000:
		return null
	var b: int = -1
	for j in range(p + 6, raw.size()):
		if raw[j] == 0x0A:
			b = j + 1
			break
	if b < 0 or b + 5 > raw.size():
		return null
	b += 1
	var icount: int = raw.decode_u32(b)
	b += 4 + 1 + icount * 2
	if b + 10 > raw.size():
		return null
	var cid: int = raw.decode_u16(b)
	var gsize: int = raw.decode_u32(b + 2)
	if cid != 0x5000:
		return null
	var vcount: int = raw.decode_u32(b + 6)
	var di: int = -1
	var search_end: int = mini(raw.size() - 1, b + gsize)
	for k in range(b + 10, search_end):
		if raw.decode_u16(k) == 0x5210:
			di = k + 6
			break
	if di < 0:
		return null
	var gz: int = int(hm.get("grid_z", 0))
	var gx: int = int(hm.get("grid_x", 0))
	if gx < 1 or gz < 1:
		return null
	var mask := PackedByteArray()
	mask.resize(gz * gx)
	var cell: float = 5.0
	for v in vcount:
		var off: int = di + v * 32
		if off + 12 > raw.size():
			break
		# Mesh-local vertices are the transpose of world (x<->z) — debug_map.py.
		var pz: float = raw.decode_float(off)
		var px: float = raw.decode_float(off + 8)
		var ix: int = int(px / cell)
		var iz: int = int(pz / cell)
		if iz >= 0 and iz < gz and ix >= 0 and ix < gx:
			mask[iz * gx + ix] = 1
	return mask


static func water_mask_for_dir(
	map_dir: String, heightmap: Variant, stem: String = ""
) -> Variant:
	## Combined water footprint, or null when there is no water.
	var hm: Dictionary = _coerce(heightmap)
	var placed := {}
	if not stem.is_empty():
		var bzn: String = map_dir.path_join("%s_S.bzn" % stem)
		if not FileAccess.file_exists(bzn):
			bzn = map_dir.path_join("%s.bzn" % stem)
		if FileAccess.file_exists(bzn):
			for rec in _bzn_objects(bzn):
				placed[str(rec.get("prjid", "")).to_lower()] = true
	var combined: PackedByteArray = PackedByteArray()
	var have: bool = false
	var da := DirAccess.open(map_dir)
	if da == null:
		return null
	for name in da.get_files():
		if str(name).get_extension().to_lower() != "mesh":
			continue
		var mesh: String = map_dir.path_join(str(name))
		if not _is_water_mesh(mesh):
			continue
		if not stem.is_empty() and not placed.has(str(name).get_basename().to_lower()):
			continue
		var m: Variant = _water_footprint(mesh, hm)
		if m == null:
			continue
		var mb: PackedByteArray = m
		if not have:
			combined = mb
			have = true
		else:
			for i in mini(combined.size(), mb.size()):
				if mb[i] != 0:
					combined[i] = 1
	if have:
		return combined
	return null


static func render_debug(
	map_dir: String, out_path: String = "", px: int = 900, stem: String = ""
) -> Dictionary:
	## Annotated top-down PNG. Returns {ok, path}. docs/03: keep what render emits;
	## this is the public counterpart of debug_map.render_debug (no TTF legend).
	if stem.is_empty():
		stem = map_dir.get_file()
		if stem.is_empty():
			stem = map_dir.get_base_dir().get_file()
	var hg2: String = _find(map_dir, "%s.hg2" % stem)
	if hg2.is_empty():
		hg2 = _find(map_dir, "%s.HG2" % stem)
	if hg2.is_empty():
		var da := DirAccess.open(map_dir)
		if da != null:
			for name in da.get_files():
				if str(name).get_extension().to_lower() == "hg2":
					hg2 = map_dir.path_join(str(name))
					break
	if hg2.is_empty():
		return BzErrors.err(
			"not_found",
			"no .hg2 for %s in %s" % [stem, map_dir],
			"",
			map_dir
		)
	var read: Dictionary = BzHg2.read_hg2(hg2)
	if BzErrors.is_err(read) or not read.get("ok", false):
		if BzErrors.is_err(read):
			return read
		return BzErrors.err("no_terrain", "failed to read %s" % hg2, "", hg2)
	var heightmap: Variant = read.get("heightmap")
	var bzn: String = map_dir.path_join("%s_S.bzn" % stem)
	if not FileAccess.file_exists(bzn):
		bzn = map_dir.path_join("%s.bzn" % stem)
	var pv := Preview.new(heightmap, Vector2i(px, px))
	var mask: Variant = water_mask_for_dir(map_dir, heightmap, stem)
	if mask is PackedByteArray and _mask_any(mask):
		pv.draw_regions([mask], [40, 120, 255], 120)
	var counts := {}
	var dots := {}
	for rec in _bzn_objects(bzn):
		var info: Dictionary = _class_of(str(rec.get("prjid", "")))
		var label: String = str(info["label"])
		counts[label] = int(counts.get(label, 0)) + 1
		var col: Color = info["color"]
		var key: String = "%d,%d,%d" % [col.r8, col.g8, col.b8]
		if not dots.has(key):
			dots[key] = {"color": col, "pts": []}
		(dots[key]["pts"] as Array).append([float(rec.get("x", 0.0)), float(rec.get("z", 0.0))])
	var order: Array = [
		Color8(255, 140, 0),
		Color8(255, 230, 0),
		Color8(0, 220, 255),
		Color8(255, 0, 200),
		Color8(200, 0, 255),
		Color8(140, 140, 140),
		Color8(255, 255, 255),
	]
	for col2 in order:
		var key2: String = "%d,%d,%d" % [col2.r8, col2.g8, col2.b8]
		if dots.has(key2):
			var r: int = 6 if col2 == Color8(255, 255, 255) else 3
			pv.draw_points(dots[key2]["pts"], col2, r)
	# Legend box (swatches only — Godot Image has no PIL ImageDraw.text).
	var nlines: int = 1
	for lab in counts.keys():
		nlines += 1
	var box_h: int = 12 * nlines + 8
	if pv.image != null:
		pv.image.fill_rect(Rect2i(4, 4, 316, box_h), Color8(0, 0, 0))
		var y: int = 20
		for i in _CLASS_PREFIX.size():
			var lab2: String = _CLASS_LABEL[i]
			if counts.has(lab2):
				pv.image.fill_rect(
					Rect2i(8, y, 10, 10),
					Color8(_CLASS_R[i], _CLASS_G[i], _CLASS_B[i])
				)
				y += 12
		if counts.has("other/mesh"):
			pv.image.fill_rect(Rect2i(8, y, 10, 10), Color8(140, 140, 140))
	var dest: String = out_path
	if dest.is_empty():
		dest = map_dir.path_join("%s.debug.png" % stem)
	var wr: Dictionary = pv.save(dest)
	if BzErrors.is_err(wr):
		return wr
	return {"ok": true, "path": dest}


static func _session_paths(session_dir: String) -> Dictionary:
	## Private copy of BzSession.session_paths. BzSession.gd does not compile
	## in Godot 4.7 (String.is_absolute); do not call it from this file.
	var residue: String = session_dir.path_join("residue")
	return {
		"root": session_dir,
		"manifest": session_dir.path_join("manifest.json"),
		"terrain": session_dir.path_join("terrain.r16"),
		"materials": session_dir.path_join("materials.u16"),
		"objects": session_dir.path_join("objects.json"),
		"features": session_dir.path_join("features.json"),
		"meta": session_dir.path_join("meta.json"),
		"dirty": session_dir.path_join("dirty.json"),
		"report": session_dir.path_join("report.json"),
		"masks": session_dir.path_join("masks"),
		"residue": residue,
		"source": residue.path_join("source"),
		"hg2_header": residue.path_join("hg2_header.json"),
		"hg2_flags": residue.path_join("hg2_flags.u8"),
	}


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return BzErrors.err("invalid_json", "failed to parse JSON: %s" % path, "", path)
	return parsed


static func _read_u16_grid(path: String, grid_z: int, grid_x: int) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() % 2 != 0:
		return BzErrors.err(
			"terrain_size_mismatch",
			"%s has %d bytes (not a whole number of uint16 samples)" % [path, bytes.size()],
			"",
			path
		)
	var samples := PackedInt32Array()
	samples.resize(bytes.size() / 2)
	for i in samples.size():
		samples[i] = bytes.decode_u16(i * 2)
	var expected: int = grid_z * grid_x
	if samples.size() != expected:
		return BzErrors.err(
			"terrain_size_mismatch",
			"terrain.r16 has %d samples, expected %d (%dx%d)"
			% [samples.size(), expected, grid_z, grid_x],
			"",
			path
		)
	return samples


static func _reconstruct_heightmap(paths: Dictionary, header: Dictionary) -> Variant:
	## Private copy of BzSession.reconstruct_heightmap.
	var zones_x: int = int(header.get("zonesX", 0))
	var zones_z: int = int(header.get("zonesZ", 0))
	var grid_x: int = zones_x * BzHg2.ZONE_SIZE
	var grid_z: int = zones_z * BzHg2.ZONE_SIZE
	var heights_v: Variant = _read_u16_grid(str(paths.get("terrain", "")), grid_z, grid_x)
	if BzErrors.is_err(heights_v):
		return heights_v
	var heights: PackedInt32Array = heights_v
	var flags := PackedByteArray()
	flags.resize(grid_z * grid_x)
	var flags_path: String = str(paths.get("hg2_flags", ""))
	if FileAccess.file_exists(flags_path):
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(flags_path)
		if raw.size() != grid_z * grid_x:
			return BzErrors.err(
				"flags_size_mismatch",
				"hg2_flags.u8 has %d samples, expected %d" % [raw.size(), grid_z * grid_x],
				"",
				flags_path
			)
		flags = raw
	var words := PackedInt32Array()
	words.resize(heights.size())
	for i in heights.size():
		var fl: int = flags[i] if i < flags.size() else 0
		words[i] = ((fl << 13) | (heights[i] & 0x1FFF)) & 0xFFFF
	return BzHg2.HeightMap.new(
		zones_x,
		zones_z,
		words,
		int(header.get("version", 1)),
		int(header.get("depth", 8)),
		int(header.get("unknownA", 10)),
		int(header.get("unknownB", 0))
	)


static func render_session(
	session_dir: String, out_dir: String, debug: bool = false
) -> Dictionary:
	## Write <stem>.png / <stem>.BMP and preview.png. Payload: docs/02 §3 render.
	var _unused_debug: bool = debug
	var paths: Dictionary = _session_paths(session_dir)
	if not FileAccess.file_exists(str(paths["manifest"])):
		return BzErrors.err(
			"no_session",
			"no manifest.json in %s" % session_dir,
			"",
			session_dir
		)
	var manifest_v: Variant = _read_json(str(paths["manifest"]))
	if BzErrors.is_err(manifest_v):
		return manifest_v
	if typeof(manifest_v) != TYPE_DICTIONARY:
		return BzErrors.err("no_session", "manifest.json is not an object", "", str(paths["manifest"]))
	var manifest: Dictionary = manifest_v
	if not FileAccess.file_exists(str(paths["hg2_header"])):
		return BzErrors.err("no_terrain", "session has no residue hg2 header")
	var header_v: Variant = _read_json(str(paths["hg2_header"]))
	if BzErrors.is_err(header_v):
		return header_v
	if typeof(header_v) != TYPE_DICTIONARY:
		return BzErrors.err("no_terrain", "session has no residue hg2 header")
	var heightmap: Variant = _reconstruct_heightmap(paths, header_v)
	if BzErrors.is_err(heightmap):
		return heightmap
	var preview := Preview.new(heightmap, Vector2i(512, 512))
	if FileAccess.file_exists(str(paths["objects"])):
		var objects_v: Variant = _read_json(str(paths["objects"]))
		if not BzErrors.is_err(objects_v) and typeof(objects_v) == TYPE_DICTIONARY:
			var points: Array = []
			for key in (objects_v as Dictionary).keys():
				var records: Variant = objects_v[key]
				if not (records is Array):
					continue
				for rec in records:
					if typeof(rec) == TYPE_DICTIONARY:
						points.append([
							float((rec as Dictionary).get("x", 0.0)),
							float((rec as Dictionary).get("z", 0.0)),
						])
			if not points.is_empty():
				preview.draw_points(points, [255, 220, 40], 2)
	var err: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK and not DirAccess.dir_exists_absolute(out_dir):
		return BzErrors.err(
			"write_failed",
			"cannot create output dir: %s" % out_dir,
			"",
			out_dir
		)
	var stem: String = str(manifest.get("stem", ""))
	if stem.is_empty():
		stem = "map"
	var png: String = out_dir.path_join("%s.png" % stem)
	var bmp: String = out_dir.path_join("%s.BMP" % stem)
	var thumb: Dictionary = write_thumbnail(preview.image, png, bmp, Vector2i(512, 512))
	if BzErrors.is_err(thumb):
		return thumb
	var overview: String = out_dir.path_join("preview.png")
	var ov: Dictionary = _save_png_raw(preview.image, overview)
	if BzErrors.is_err(ov):
		return ov
	return {
		"ok": true,
		"png": _abs(png),
		"bmp": _abs(bmp),
		"preview": _abs(overview),
		"north_up": true,
	}
