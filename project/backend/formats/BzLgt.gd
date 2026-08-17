extends RefCounted
class_name BzLgt
## Port of backend/bzmap/formats/lgt.py — copy-only LightMap.
##
## The `.LGT` layout is unresolved (Python module docs, docs/09 E1). There is
## no F-doc. Verified size only: `(zonesX * zonesZ + 1) * 65536`. This class
## round-trips whatever bytes it is given and never decodes or invents values.

const _PLANE_BYTES: int = 65536


static func _fail(message: String, hint: String = "") -> Dictionary:
	return {
		"ok": false,
		"error": {"code": "value_error", "message": message, "hint": hint},
	}


class LightMap:
	extends RefCounted

	var zonesX: int = 0
	var zonesZ: int = 0
	var data: PackedByteArray = PackedByteArray()

	func _init(p_data: PackedByteArray, p_zonesX: int, p_zonesZ: int) -> void:
		zonesX = int(p_zonesX)
		zonesZ = int(p_zonesZ)
		data = p_data
		var expected: int = (zonesX * zonesZ + 1) * BzLgt._PLANE_BYTES
		if data.size() != expected:
			push_error(
				"LGT size %d does not match expected (%dx%d zones -> %d bytes)"
				% [data.size(), zonesX, zonesZ, expected]
			)

	var plane_count: int:
		get:
			return zonesX * zonesZ + 1

	static func read(path: String, zonesX: int, zonesZ: int) -> Dictionary:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return BzLgt._fail(
				"%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		var buf: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		var expected: int = (int(zonesX) * int(zonesZ) + 1) * BzLgt._PLANE_BYTES
		if buf.size() != expected:
			return BzLgt._fail(
				"LGT size %d does not match expected (%dx%d zones -> %d bytes)"
				% [buf.size(), zonesX, zonesZ, expected]
			)
		return {"ok": true, "lightmap": LightMap.new(buf, zonesX, zonesZ)}

	func write(path: String) -> Dictionary:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return BzLgt._fail(
				"%s: cannot write (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		file.store_buffer(data)
		file.close()
		return {"ok": true}


static func read_lgt(path: String, zonesX: int, zonesZ: int) -> Dictionary:
	return LightMap.read(path, zonesX, zonesZ)


static func write_lgt(path: String, lightmap: LightMap) -> Dictionary:
	return lightmap.write(path)
