extends RefCounted
class_name MaterialPalette
## Shared material colours / atlas UVs / type names for renderer and picker.

static var _atlas_path: String = ""
static var _atlas_image: Image = null
static var _catalog_world: String = ""
static var _catalog_n: int = -1
## "k:base:trans" → PackedInt32Array of variant indices that exist.
static var _catalog: Dictionary = {}


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


static func catalog_known() -> bool:
	_ensure_catalog()
	return _catalog_n > 0


static func kind_code(kind: String) -> int:
	match kind:
		"cap":
			return 1
		"diag":
			return 2
		_:
			return 0


static func has_kind_for(base: int, kind: String) -> bool:
	return not transition_partners(base, kind).is_empty()


static func has_transition(base: int, trans: int, kind: String) -> bool:
	if kind == "solid":
		return true
	if not catalog_known():
		return true
	var key := "%d:%d:%d" % [kind_code(kind), base & 0xF, trans & 0xF]
	return _catalog.has(key)


static func transition_partners(base: int, kind: String) -> PackedInt32Array:
	_ensure_catalog()
	var out := PackedInt32Array()
	base &= 0xF
	if kind == "solid":
		return out
	if not catalog_known():
		for i in 16:
			if i != base:
				out.append(i)
		return out
	var k := kind_code(kind)
	for trans in 16:
		if _catalog.has("%d:%d:%d" % [k, base, trans]):
			out.append(trans)
	return out


static func variants_for(base: int, trans: int, kind: String) -> PackedInt32Array:
	_ensure_catalog()
	if kind == "solid" or not catalog_known():
		return PackedInt32Array([0, 1, 2, 3])
	var key := "%d:%d:%d" % [kind_code(kind), base & 0xF, trans & 0xF]
	var raw: Variant = _catalog.get(key, PackedInt32Array())
	if typeof(raw) != TYPE_PACKED_INT32_ARRAY:
		return PackedInt32Array([0])
	var found: PackedInt32Array = raw
	if found.is_empty():
		return PackedInt32Array([0])
	return found


static func _ensure_catalog() -> void:
	var world := _current_world()
	var tiles: Dictionary = world.get("atlas_tiles", {}) if not world.is_empty() else {}
	var id := str(world.get("id", "")).to_lower()
	if id == _catalog_world and tiles.size() == _catalog_n:
		return
	_catalog_world = id
	_catalog_n = tiles.size()
	_catalog.clear()
	for key in tiles.keys():
		var parsed: Dictionary = _parse_tile_name(str(key))
		if parsed.is_empty():
			continue
		var k: int = int(parsed.get("kind", -1))
		if k < 1:
			continue
		var ck := "%d:%d:%d" % [k, int(parsed.get("base", 0)), int(parsed.get("trans", 0))]
		var variant: int = int(parsed.get("variant", 0))
		var list: PackedInt32Array = _catalog.get(ck, PackedInt32Array())
		if not list.has(variant):
			list.append(variant)
		_catalog[ck] = list


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


static func material_thumbnails(size: int = 28) -> Array:
	## 16 slots: solid-tile crop from the world atlas, or null to use flat_color.
	## Prefer the TRN SolidA0 name (Elysium type 4 is EL04SA0, not EL44SA0).
	## Dummy origin UVs are never used — those impersonate material 0.
	var out: Array = []
	out.resize(16)
	var world := _current_world()
	if world.is_empty():
		return out
	var path := str(world.get("atlas_image", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	# DDS ice atlases blow out to white (same rule as TerrainRenderer).
	if not path.to_lower().ends_with(".png"):
		return out
	var atlas := _load_atlas_png(path)
	if atlas == null or atlas.get_width() < 2 or atlas.get_height() < 2:
		return out
	for i in 16:
		var uv := _solid_tile_uv(world, i)
		if uv.z <= 0.0 or uv.w <= 0.0:
			continue
		var tex := _crop_tile(atlas, uv, size)
		if tex:
			out[i] = tex
	return out


static func _load_atlas_png(path: String) -> Image:
	if path == _atlas_path and _atlas_image != null:
		return _atlas_image
	var img := Image.load_from_file(path)
	if img == null:
		return null
	_atlas_path = path
	_atlas_image = img
	return img


static func _solid_tile_uv(world: Dictionary, idx: int) -> Vector4:
	## Fill tile for material idx, or (0,0,0,0) if the atlas has none.
	var tiles: Dictionary = world.get("atlas_tiles", {})
	if tiles.is_empty() or idx < 0 or idx > 15:
		return Vector4()
	for t in world.get("texture_types", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if int(t.get("index", -1)) != idx:
			continue
		var named := _rect_of(tiles, str(t.get("solid_tile", "")))
		if named.z > 0.0:
			return named
		break
	return _scan_solid_uv(tiles, idx)


static func _scan_solid_uv(tiles: Dictionary, idx: int) -> Vector4:
	## Prefer `{i}{i}S*` (true solid). Elysium type 4 only has EL04SA0, which
	## encodes as base 0 / trans 4 / solid — catch that as trans==idx next.
	var exact := Vector4()
	var to_idx := Vector4()
	var from_idx := Vector4()
	var exact_var := 99
	var to_var := 99
	var from_var := 99
	for key in tiles.keys():
		var parsed := _parse_tile_name(str(key))
		if parsed.is_empty() or int(parsed.get("kind", -1)) != 0:
			continue
		var variant := int(parsed.get("variant", 99))
		var uv := _rect_of(tiles, str(key))
		if uv.z <= 0.0:
			continue
		var base := int(parsed.get("base", -1))
		var trans := int(parsed.get("trans", -1))
		if base == idx and trans == idx and variant < exact_var:
			exact = uv
			exact_var = variant
		elif trans == idx and variant < to_var:
			to_idx = uv
			to_var = variant
		elif base == idx and variant < from_var:
			from_idx = uv
			from_var = variant
	if exact.z > 0.0:
		return exact
	if to_idx.z > 0.0:
		return to_idx
	if from_idx.z > 0.0:
		return from_idx
	return Vector4()


static func _parse_tile_name(key: String) -> Dictionary:
	## "EL04SA0.MAP" → {base:0, trans:4, kind:0, variant:0}. kind 0/1/2 = S/C/D.
	var stem := key.get_file().get_basename().to_upper()
	if stem.length() < 6 or not stem.ends_with("0"):
		return {}
	var core := stem.substr(stem.length() - 5, 4)
	var kind := ["S", "C", "D"].find(core.substr(2, 1))
	if kind < 0:
		return {}
	var variant := core.unicode_at(3) - "A".unicode_at(0)
	return {
		"base": core.substr(0, 1).hex_to_int(),
		"trans": core.substr(1, 1).hex_to_int(),
		"kind": kind,
		"variant": variant,
	}


static func _rect_of(tiles: Dictionary, raw: String) -> Vector4:
	var name := raw.get_file().strip_edges().to_upper()
	if name.is_empty():
		return Vector4()
	for key in [name, name + ".MAP", name.trim_suffix(".MAP")]:
		if not tiles.has(key):
			continue
		var r: Array = tiles[key]
		if r.size() >= 4:
			return Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return Vector4()


static func _crop_tile(atlas: Image, uv: Vector4, size: int) -> ImageTexture:
	var atlas_w := atlas.get_width()
	var atlas_h := atlas.get_height()
	var x0 := clampi(int(floor(uv.x * float(atlas_w))), 0, atlas_w - 1)
	var y0 := clampi(int(floor(uv.y * float(atlas_h))), 0, atlas_h - 1)
	var x1 := clampi(int(ceil((uv.x + uv.z) * float(atlas_w))), x0 + 1, atlas_w)
	var y1 := clampi(int(ceil((uv.y + uv.w) * float(atlas_h))), y0 + 1, atlas_h)
	var w := x1 - x0
	var h := y1 - y0
	# Skip the outer eighth so atlas seams do not dominate a 35 px swatch.
	var inset_x := 0 if w < 8 else mini(w / 8, (w - 4) / 2)
	var inset_y := 0 if h < 8 else mini(h / 8, (h - 4) / 2)
	var crop: Image = atlas.get_region(Rect2i(
		x0 + inset_x, y0 + inset_y, w - inset_x * 2, h - inset_y * 2
	))
	if crop == null or crop.get_width() < 1 or crop.get_height() < 1:
		return null
	if crop.get_width() != size or crop.get_height() != size:
		crop.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(crop)


static func _texture_types() -> Array:
	var world := _current_world()
	if world.is_empty():
		return []
	var types: Array = world.get("texture_types", [])
	return types
