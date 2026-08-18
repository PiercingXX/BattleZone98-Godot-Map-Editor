extends RefCounted
class_name HeightmapIO
## Real 16-bit grayscale PNG I/O for external GIMP edits.
##
## Mapping (documented in the sidecar too):
##   export: raw 0..4095 → PNG sample 0..65520 via `raw << 4`
##   import: sample >> 4, then clamp to 1..4095
## 8-bit gray is expanded to 16-bit as `(v << 8) | v` before the same >> 4.
##
## Godot Image.save_png / load_png_from_buffer are 8-bit only. On Godot 4.7.1
## a 16-bit gray PNG loads as FORMAT_L8 (high byte only) — verified empirically.
## Export is hand-encoded (IHDR/IDAT/IEND). 16-bit import parses the PNG.

const RAW_MIN := 1
const RAW_MAX := 4095
## raw << 4 → 16-bit sample; sample >> 4 → raw.
const SAMPLE_SHIFT := 4

const _PNG_SIG: PackedByteArray = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

static var _crc_table: PackedInt32Array = PackedInt32Array()


static func raw_to_sample16(raw: int) -> int:
	return (clampi(raw, 0, RAW_MAX) << SAMPLE_SHIFT) & 0xFFFF


static func sample16_to_raw(sample: int) -> int:
	return clampi((sample & 0xFFFF) >> SAMPLE_SHIFT, RAW_MIN, RAW_MAX)


static func sample8_to_raw(v: int) -> int:
	var u := clampi(v, 0, 255)
	return sample16_to_raw((u << 8) | u)


static func crc32(data: PackedByteArray) -> int:
	_ensure_crc_table()
	var c := 0xFFFFFFFF
	for i in data.size():
		var idx := (c ^ int(data[i])) & 0xFF
		var tbl: int = _crc_table[idx] & 0xFFFFFFFF
		c = (tbl ^ (c >> 8)) & 0xFFFFFFFF
	return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func adler32(data: PackedByteArray) -> int:
	var a := 1
	var b := 0
	const MOD := 65521
	var i := 0
	var n := data.size()
	while i < n:
		var end := i + mini(n - i, 5552)
		while i < end:
			a += int(data[i])
			b += a
			i += 1
		a %= MOD
		b %= MOD
	return ((b << 16) | a) & 0xFFFFFFFF


static func sidecar_text(grid_x: int, grid_z: int) -> String:
	return "\n".join(PackedStringArray([
		"BattleZone 98 heightmap",
		"grid_x=%d" % grid_x,
		"grid_z=%d" % grid_z,
		"bit_depth=16",
		"color_type=0",
		"mapping=raw << 4",
		"raw_range=0..4095",
		"png_sample=raw << 4  (0..65520; 4095 → 65520, not 65535)",
		"import=png_sample >> 4, clamp 1..4095",
		"row_major=z * grid_x + x; +z north",
		"note=Godot Image.save_png is 8-bit only; this file is a real 16-bit grayscale PNG (IHDR bit depth 16, color type 0) so GIMP can edit it losslessly.",
		"",
	]))


static func encode_gray16_png(grid_x: int, grid_z: int, heights: PackedInt32Array, filter: int = 0) -> PackedByteArray:
	if grid_x < 1 or grid_z < 1:
		return PackedByteArray()
	var filt := filter if filter >= 0 and filter <= 4 else 0
	var bpp := 2
	var stride := grid_x * bpp
	var scan := PackedByteArray()
	scan.resize(grid_z * (1 + stride))
	var prev := PackedByteArray()
	prev.resize(stride)
	prev.fill(0)
	var n := heights.size()
	var o := 0
	for z in grid_z:
		var orig := PackedByteArray()
		orig.resize(stride)
		for x in grid_x:
			var raw := 0
			var idx := z * grid_x + x
			if idx < n:
				raw = int(heights[idx])
			var sample := raw_to_sample16(raw)
			orig[x * 2] = (sample >> 8) & 0xFF
			orig[x * 2 + 1] = sample & 0xFF
		scan[o] = filt
		o += 1
		for i in stride:
			var left := int(orig[i - bpp]) if i >= bpp else 0
			var up := int(prev[i])
			var up_left := int(prev[i - bpp]) if i >= bpp else 0
			var src := int(orig[i])
			var out_b := src
			match filt:
				1:
					out_b = (src - left) & 0xFF
				2:
					out_b = (src - up) & 0xFF
				3:
					out_b = (src - ((left + up) >> 1)) & 0xFF
				4:
					out_b = (src - _paeth(left, up, up_left)) & 0xFF
			scan[o + i] = out_b
		o += stride
		prev = orig
	return _png_wrap(grid_x, grid_z, 16, 0, scan)


static func decode_png(bytes: PackedByteArray) -> Dictionary:
	var img := Image.new()
	var godot_err: Error = img.load_png_from_buffer(bytes)
	var parsed := _parse_png(bytes)
	if not bool(parsed.get("ok", false)):
		return parsed
	var bit_depth := int(parsed["bit_depth"])
	var color_type := int(parsed["color_type"])
	var width := int(parsed["grid_x"])
	var height := int(parsed["grid_z"])
	# 16-bit gray loads as FORMAT_L8 on Godot 4.7.1 (high byte only) — lossy.
	if (
		godot_err == OK
		and bit_depth == 8
		and color_type == 0
		and img.get_format() == Image.FORMAT_L8
		and img.get_width() == width
		and img.get_height() == height
	):
		return _heights_from_l8(img, bit_depth, color_type)
	var pixels: PackedByteArray = parsed["pixels"]
	var bpp := int(parsed["bpp"])
	return _heights_from_pixels(pixels, width, height, bit_depth, color_type, bpp)


static func import_png_file(path: String, expect_x: int = -1, expect_z: int = -1) -> Dictionary:
	var cleaned := path.strip_edges()
	if cleaned.is_empty():
		return _fail("no heightmap path")
	if not FileAccess.file_exists(cleaned):
		return _fail("file moved — %s" % cleaned)
	var bytes := FileAccess.get_file_as_bytes(cleaned)
	if bytes.is_empty():
		return _fail("empty file — %s" % cleaned)
	var decoded := decode_png(bytes)
	if not bool(decoded.get("ok", false)):
		return decoded
	if expect_x > 0 and expect_z > 0:
		var dw := int(decoded["grid_x"])
		var dh := int(decoded["grid_z"])
		if dw != expect_x or dh != expect_z:
			return _fail("heightmap is %dx%d, map is %dx%d" % [dw, dh, expect_x, expect_z])
	return decoded


static func export_to_dir(dir: String, stem: String, field: HeightField) -> Dictionary:
	if field == null or field.grid_x < 1 or field.grid_z < 1:
		return _fail("map has no heightmap")
	var dest := dir.strip_edges()
	if dest.is_empty():
		return _fail("no export directory")
	var clean := stem.strip_edges()
	if clean.is_empty():
		clean = "map"
	var png_path := dest.path_join("%s-heightmap.png" % clean)
	var txt_path := dest.path_join("%s-heightmap.txt" % clean)
	var png := encode_gray16_png(field.grid_x, field.grid_z, field.heights)
	if png.is_empty():
		return _fail("failed to encode heightmap PNG")
	var pf := FileAccess.open(png_path, FileAccess.WRITE)
	if pf == null:
		return _fail("cannot write %s" % png_path)
	pf.store_buffer(png)
	pf.close()
	var tf := FileAccess.open(txt_path, FileAccess.WRITE)
	if tf == null:
		return _fail("cannot write %s" % txt_path)
	tf.store_string(sidecar_text(field.grid_x, field.grid_z))
	tf.close()
	return {"ok": true, "png": png_path, "txt": txt_path}


static func _heights_from_l8(img: Image, bit_depth: int, color_type: int) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var heights := PackedInt32Array()
	heights.resize(w * h)
	var i := 0
	for z in h:
		for x in w:
			heights[i] = sample8_to_raw(img.get_pixel(x, z).r8)
			i += 1
	return {
		"ok": true,
		"grid_x": w,
		"grid_z": h,
		"bit_depth": bit_depth,
		"color_type": color_type,
		"heights": heights,
	}


static func _heights_from_pixels(
	pixels: PackedByteArray,
	width: int,
	height: int,
	bit_depth: int,
	color_type: int,
	bpp: int
) -> Dictionary:
	var n := width * height
	var heights := PackedInt32Array()
	heights.resize(n)
	var i := 0
	for z in height:
		for x in width:
			var off := (z * width + x) * bpp
			if off >= pixels.size():
				return _fail("PNG pixel data truncated")
			if bit_depth == 16:
				if off + 1 >= pixels.size():
					return _fail("PNG pixel data truncated")
				var sample := (int(pixels[off]) << 8) | int(pixels[off + 1])
				heights[i] = sample16_to_raw(sample)
			else:
				heights[i] = sample8_to_raw(int(pixels[off]))
			i += 1
	return {
		"ok": true,
		"grid_x": width,
		"grid_z": height,
		"bit_depth": bit_depth,
		"color_type": color_type,
		"heights": heights,
	}


static func _parse_png(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8 or not _has_png_sig(bytes):
		return _fail("not a PNG")
	var pos := 8
	var width := 0
	var height := 0
	var bit_depth := 0
	var color_type := 0
	var seen_ihdr := false
	var seen_idat := false
	var idat := PackedByteArray()
	while pos + 12 <= bytes.size():
		var length := _u32_be(bytes, pos)
		if length < 0 or pos + 12 + length > bytes.size():
			return _fail("truncated PNG chunk")
		var typ := bytes.slice(pos + 4, pos + 8).get_string_from_ascii()
		var data := bytes.slice(pos + 8, pos + 8 + length)
		var crc_got := _u32_be(bytes, pos + 8 + length)
		var crc_src := bytes.slice(pos + 4, pos + 8 + length)
		if crc32(crc_src) != crc_got:
			return _fail("PNG chunk CRC mismatch (%s)" % typ)
		if typ == "IHDR":
			if seen_ihdr or pos != 8:
				return _fail("invalid PNG IHDR")
			if data.size() != 13:
				return _fail("invalid PNG IHDR")
			width = _u32_be(data, 0)
			height = _u32_be(data, 4)
			bit_depth = int(data[8])
			color_type = int(data[9])
			var compression := int(data[10])
			var filter_method := int(data[11])
			var interlace := int(data[12])
			if compression != 0:
				return _fail("unsupported PNG compression method")
			if filter_method != 0:
				return _fail("unsupported PNG filter method")
			if interlace != 0:
				return _fail("interlaced PNG is not supported")
			if width < 1 or height < 1:
				return _fail("PNG has empty dimensions")
			if color_type != 0 and color_type != 4:
				return _fail("expected grayscale PNG (color type 0), got color type %d" % color_type)
			if bit_depth != 8 and bit_depth != 16:
				return _fail("expected 8- or 16-bit grayscale, got bit depth %d" % bit_depth)
			seen_ihdr = true
		elif typ == "IDAT":
			if not seen_ihdr:
				return _fail("PNG IDAT before IHDR")
			idat.append_array(data)
			seen_idat = true
		elif typ == "IEND":
			if not seen_ihdr:
				return _fail("PNG IEND before IHDR")
			break
		elif typ.length() == 4 and (typ.unicode_at(0) & 0x20) == 0:
			# Unknown critical chunk.
			return _fail("unsupported PNG chunk %s" % typ)
		pos += 12 + length
	if not seen_ihdr:
		return _fail("PNG missing IHDR")
	if not seen_idat or idat.is_empty():
		return _fail("PNG missing IDAT")
	var ch := 1 if color_type == 0 else 2
	var sample_bytes := 2 if bit_depth == 16 else 1
	var bpp: int = ch * sample_bytes
	var expected := height * (1 + width * bpp)
	var inflated := _inflate_zlib(idat, expected)
	if inflated.size() < expected:
		return _fail("PNG IDAT inflate failed")
	var pixels := _reconstruct(inflated, width, height, bpp)
	if pixels.size() != width * height * bpp:
		return _fail("PNG filter reconstruction failed")
	return {
		"ok": true,
		"grid_x": width,
		"grid_z": height,
		"bit_depth": bit_depth,
		"color_type": color_type,
		"bpp": bpp,
		"pixels": pixels,
	}


static func _inflate_zlib(idat: PackedByteArray, expected: int) -> PackedByteArray:
	var want := maxi(expected, 1)
	var inflated: PackedByteArray = idat.decompress(want, FileAccess.COMPRESSION_DEFLATE)
	if inflated.size() >= expected:
		return inflated
	inflated = idat.decompress_dynamic(want, FileAccess.COMPRESSION_DEFLATE)
	if inflated.size() >= expected:
		return inflated
	# Last resort: Godot 4.7 COMPRESSION_DEFLATE expects a zlib stream.
	if idat.size() >= 6 and idat[0] == 0x78:
		return inflated
	var wrapped := PackedByteArray()
	wrapped.append(0x78)
	wrapped.append(0x9C)
	wrapped.append_array(idat)
	inflated = wrapped.decompress(want, FileAccess.COMPRESSION_DEFLATE)
	return inflated


static func _reconstruct(scan: PackedByteArray, width: int, height: int, bpp: int) -> PackedByteArray:
	var stride := width * bpp
	var out := PackedByteArray()
	out.resize(height * stride)
	var src := 0
	for y in height:
		if src >= scan.size():
			return PackedByteArray()
		var ftype := int(scan[src])
		src += 1
		if ftype < 0 or ftype > 4:
			return PackedByteArray()
		if src + stride > scan.size():
			return PackedByteArray()
		for x in stride:
			var filt := int(scan[src + x])
			var a := int(out[y * stride + x - bpp]) if x >= bpp else 0
			var b := int(out[(y - 1) * stride + x]) if y > 0 else 0
			var c := int(out[(y - 1) * stride + x - bpp]) if y > 0 and x >= bpp else 0
			var recon := filt
			match ftype:
				1:
					recon = (filt + a) & 0xFF
				2:
					recon = (filt + b) & 0xFF
				3:
					recon = (filt + ((a + b) >> 1)) & 0xFF
				4:
					recon = (filt + _paeth(a, b, c)) & 0xFF
			out[y * stride + x] = recon
		src += stride
	return out


static func _png_wrap(width: int, height: int, bit_depth: int, color_type: int, scan: PackedByteArray) -> PackedByteArray:
	var ihdr := PackedByteArray()
	_append_u32_be(ihdr, width)
	_append_u32_be(ihdr, height)
	ihdr.append(bit_depth)
	ihdr.append(color_type)
	ihdr.append(0)
	ihdr.append(0)
	ihdr.append(0)
	var png := PackedByteArray()
	png.append_array(_PNG_SIG)
	_append_chunk(png, "IHDR", ihdr)
	_append_chunk(png, "IDAT", _zlib_stream(scan))
	_append_chunk(png, "IEND", PackedByteArray())
	return png


static func _zlib_stream(uncompressed: PackedByteArray) -> PackedByteArray:
	# IDAT is a zlib stream: 0x78 0x9C + DEFLATE + Adler-32 of the source.
	# Godot 4.7 COMPRESSION_DEFLATE already emits that wrapper (verified);
	# strip it and re-wrap so the header and Adler-32 are the ones we compute.
	var packed: PackedByteArray = uncompressed.compress(FileAccess.COMPRESSION_DEFLATE)
	var deflate := PackedByteArray()
	if packed.size() >= 6 and packed[0] == 0x78:
		deflate = packed.slice(2, packed.size() - 4)
	else:
		deflate = packed
	var out := PackedByteArray()
	out.append(0x78)
	out.append(0x9C)
	out.append_array(deflate)
	_append_u32_be(out, adler32(uncompressed))
	return out


static func _append_chunk(png: PackedByteArray, typ: String, data: PackedByteArray) -> void:
	_append_u32_be(png, data.size())
	var type_and_data := PackedByteArray()
	type_and_data.append_array(typ.to_ascii_buffer())
	type_and_data.append_array(data)
	png.append_array(type_and_data)
	_append_u32_be(png, crc32(type_and_data))


static func _append_u32_be(buf: PackedByteArray, v: int) -> void:
	var u := v & 0xFFFFFFFF
	buf.append((u >> 24) & 0xFF)
	buf.append((u >> 16) & 0xFF)
	buf.append((u >> 8) & 0xFF)
	buf.append(u & 0xFF)


static func _u32_be(buf: PackedByteArray, off: int) -> int:
	return (
		(int(buf[off]) << 24)
		| (int(buf[off + 1]) << 16)
		| (int(buf[off + 2]) << 8)
		| int(buf[off + 3])
	) & 0xFFFFFFFF


static func _has_png_sig(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8:
		return false
	for i in 8:
		if int(bytes[i]) != int(_PNG_SIG[i]):
			return false
	return true


static func _paeth(a: int, b: int, c: int) -> int:
	var p := a + b - c
	var pa := absi(p - a)
	var pb := absi(p - b)
	var pc := absi(p - c)
	if pa <= pb and pa <= pc:
		return a
	if pb <= pc:
		return b
	return c


static func _ensure_crc_table() -> void:
	if _crc_table.size() == 256:
		return
	_crc_table.resize(256)
	for n in 256:
		var c := n
		for _k in 8:
			if (c & 1) != 0:
				c = (0xEDB88320 ^ (c >> 1)) & 0xFFFFFFFF
			else:
				c = (c >> 1) & 0xFFFFFFFF
		_crc_table[n] = c


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
