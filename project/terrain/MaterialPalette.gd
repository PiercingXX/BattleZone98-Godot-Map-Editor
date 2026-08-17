extends RefCounted
class_name MaterialPalette
## Shared material colours / atlas UVs / type names for renderer and picker.


static func colors() -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(16)
	var defaults := [
		Color(0.55, 0.42, 0.28), Color(0.45, 0.48, 0.30), Color(0.40, 0.40, 0.40),
		Color(0.62, 0.55, 0.38), Color(0.30, 0.35, 0.22), Color(0.70, 0.68, 0.60),
		Color(0.50, 0.32, 0.22), Color(0.28, 0.30, 0.38),
	]
	for i in 16:
		colors[i] = defaults[i % defaults.size()]
	var types := _texture_types()
	for t in types:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var idx := int(t.get("index", 0))
		var rgb: Array = t.get("flat_color", [128, 128, 128])
		if idx >= 0 and idx < 16 and rgb.size() >= 3:
			colors[idx] = Color(
				clampf(float(rgb[0]) / 255.0, 0.0, 1.0),
				clampf(float(rgb[1]) / 255.0, 0.0, 1.0),
				clampf(float(rgb[2]) / 255.0, 0.0, 1.0)
			)
	return colors


static func atlas_uvs() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(16)
	for i in 16:
		out[i] = Vector4(0.0, 0.0, 0.125, 0.125)
	var world := _current_world()
	if world.is_empty():
		return out
	var uvs: Array = world.get("tile_uvs", [])
	for i in mini(16, uvs.size()):
		var r: Array = uvs[i]
		if r.size() >= 4:
			out[i] = Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return out


static func type_name(idx: int) -> String:
	for t in _texture_types():
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if int(t.get("index", -1)) == idx:
			var label := str(t.get("name", t.get("label", "")))
			if not label.is_empty():
				return label
	return "mat %d" % idx


static func _current_world() -> Dictionary:
	for world in MapState.worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		if str(world.get("id", "")).to_lower() == MapState.world.to_lower():
			return world
	return {}


static func _texture_types() -> Array:
	var world := _current_world()
	if world.is_empty():
		return []
	var types: Array = world.get("texture_types", [])
	return types
