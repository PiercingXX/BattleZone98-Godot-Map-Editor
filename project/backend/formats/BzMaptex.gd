extends RefCounted
class_name BzMaptex
## ``.map`` / ``.act`` texture decode (docs/formats/F6). Port of formats/maptex.py.

# bytes per pixel by pixel_format. Python: _BPP.
const BPP := {0: 1, 1: 2, 2: 2, 3: 4, 4: 4}

const FMT_INDEXED := 0
const FMT_ARGB4444 := 1
const FMT_RGB565 := 2
const FMT_ARGB8888 := 3
const FMT_XRGB8888 := 4


static func read_act(path: String) -> Dictionary:
	var loaded := _read_file(path)
	if not bool(loaded.get("ok", false)):
		return loaded
	var data: PackedByteArray = loaded["data"]
	if data.size() != 768:
		return BzErrors.err(
			"bad_act",
			"%s: .act must be 768 bytes, got %s" % [path, data.size()],
			"An .act palette is 256 RGB triplets and nothing else."
		)
	var palette: Array = []
	for i in range(0, 768, 3):
		palette.append(Vector3i(int(data[i]), int(data[i + 1]), int(data[i + 2])))
	return {"ok": true, "palette": palette}


static func read_map(path: String, palette: Variant = null) -> Dictionary:
	var loaded := _read_file(path)
	if not bool(loaded.get("ok", false)):
		return loaded
	return _decode_map(loaded["data"], palette, path)


static func _decode_map(data: PackedByteArray, palette: Variant, path: String) -> Dictionary:
	if data.size() < 8:
		return BzErrors.err("too_short", "%s: too short" % path, "A .map header is 8 bytes.")
	var row_b: int = data.decode_u16(0)
	var fmt: int = data.decode_u16(2)
	var height: int = data.decode_u16(4)
	# F8 preserve-verbatim: header unknown. This module is read-only in
	# Python (the field is unpacked as _unk and discarded). Returned here
	# so a later writer can put it back.
	var unknown: int = data.decode_u16(6)
	var bpp: int = int(BPP.get(fmt, 0))
	if bpp == 0 or row_b == 0:
		return BzErrors.err(
			"bad_format",
			"%s: bad format %s row_b %s" % [path, fmt, row_b],
			"pixel_format must be 0..4 and row_byte_size must be non-zero."
		)
	var width: int = int(row_b / bpp)
	var need: int = 8 + row_b * height
	if data.size() < need:
		return BzErrors.err(
			"truncated",
			"%s: truncated (%s < %s)" % [path, data.size(), need],
			"Pixel payload is row_byte_size × height bytes after the header."
		)
	var pal: Array = _normalize_palette(palette)
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)
	var src: int = 8
	var di: int = 0
	for _y in height:
		var row_end: int = src + row_b
		if fmt == FMT_INDEXED:
			# Python: for i in row — one palette index per byte.
			var x: int = 0
			var i: int = src
			while i < row_end and x < width:
				var idx: int = int(data[i])
				var rgb: Vector3i = pal[idx] if idx < pal.size() else Vector3i(idx, idx, idx)
				pixels[di] = rgb.x
				pixels[di + 1] = rgb.y
				pixels[di + 2] = rgb.z
				pixels[di + 3] = 255
				di += 4
				x += 1
				i += 1
		elif fmt == FMT_ARGB4444:
			# 4-bit fields expanded with *17, which is exact n*255/15 (F6).
			var i: int = src
			var x: int = 0
			while i + 1 < row_end and x < width:
				var w: int = int(data[i]) | (int(data[i + 1]) << 8)
				var a: int = ((w >> 12) & 15) * 17
				var r: int = ((w >> 8) & 15) * 17
				var g: int = ((w >> 4) & 15) * 17
				var b: int = (w & 15) * 17
				pixels[di] = r
				pixels[di + 1] = g
				pixels[di + 2] = b
				pixels[di + 3] = a
				di += 4
				x += 1
				i += 2
		elif fmt == FMT_RGB565:
			# Python: int(n * 255 / field_max) with true division, then
			# trunc toward 0. GDScript `/` on ints is integer division, so
			# the 255.0 is required to match.
			var i: int = src
			var x: int = 0
			while i + 1 < row_end and x < width:
				var w: int = int(data[i]) | (int(data[i + 1]) << 8)
				var r: int = int(float((w >> 11) & 31) * 255.0 / 31.0)
				var g: int = int(float((w >> 5) & 63) * 255.0 / 63.0)
				var b: int = int(float(w & 31) * 255.0 / 31.0)
				pixels[di] = r
				pixels[di + 1] = g
				pixels[di + 2] = b
				pixels[di + 3] = 255
				di += 4
				x += 1
				i += 2
		else:
			# Formats 3 and 4: BGRA on disk despite the ARGB name (F6 §2).
			var i: int = src
			var x: int = 0
			while i + 3 < row_end and x < width:
				var b: int = int(data[i])
				var g: int = int(data[i + 1])
				var r: int = int(data[i + 2])
				var a: int = int(data[i + 3])
				if fmt == FMT_XRGB8888:
					a = 255
				pixels[di] = r
				pixels[di + 1] = g
				pixels[di + 2] = b
				pixels[di + 3] = a
				di += 4
				x += 1
				i += 4
		src = row_end
	if width <= 0 or height <= 0:
		return BzErrors.err(
			"bad_format",
			"%s: bad format %s row_b %s" % [path, fmt, row_b],
			"Decoded width and height must be positive."
		)
	var image: Image = Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, pixels
	)
	if image == null or image.is_empty():
		return BzErrors.err("bad_format", "%s: could not build image" % path)
	return {
		"ok": true,
		"image": image,
		"width": width,
		"height": height,
		"pixel_format": fmt,
		"row_byte_size": row_b,
		"unknown": unknown,
	}


static func _normalize_palette(palette: Variant) -> Array:
	# Python: palette or [(i, i, i) for i in range(256)] — empty is falsy.
	var out: Array = []
	if palette == null:
		for i in 256:
			out.append(Vector3i(i, i, i))
		return out
	if palette is PackedByteArray:
		var raw: PackedByteArray = palette
		if raw.size() != 768:
			for i in 256:
				out.append(Vector3i(i, i, i))
			return out
		for i in range(0, 768, 3):
			out.append(Vector3i(int(raw[i]), int(raw[i + 1]), int(raw[i + 2])))
		return out
	if palette is Array:
		var arr: Array = palette
		if arr.is_empty():
			for i in 256:
				out.append(Vector3i(i, i, i))
			return out
		for item in arr:
			out.append(_rgb_item(item))
		return out
	for i in 256:
		out.append(Vector3i(i, i, i))
	return out


static func _rgb_item(item: Variant) -> Vector3i:
	if item is Vector3i:
		return item
	if item is Vector3:
		var v: Vector3 = item
		return Vector3i(int(v.x), int(v.y), int(v.z))
	if item is Color:
		var c: Color = item
		return Vector3i(
			clampi(int(round(c.r * 255.0)), 0, 255),
			clampi(int(round(c.g * 255.0)), 0, 255),
			clampi(int(round(c.b * 255.0)), 0, 255)
		)
	if item is Array or item is PackedByteArray or item is PackedInt32Array:
		return Vector3i(int(item[0]), int(item[1]), int(item[2]))
	return Vector3i.ZERO


static func _read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return BzErrors.err(
			"io",
			"%s: cannot read" % path,
			error_string(FileAccess.get_open_error())
		)
	return {"ok": true, "data": f.get_buffer(f.get_length())}
