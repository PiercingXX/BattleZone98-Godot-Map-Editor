extends RefCounted
class_name BzWorlds
## ``bzmap editor worlds`` — stock terrain templates for the new-map wizard.
##
## Port of ``backend/bzmap/editor/worlds.py``. Python ``worlds_from_game``
## returns a list and raises EditorError; GDScript always returns a Dictionary
## (docs/02 §3 ``worlds`` verb payload, or ``BzErrors.err``).

## The nine stock worlds in Edit/trn/.
const STOCK_WORLDS: PackedStringArray = [
	"achilles", "elysium", "europa", "ganymede", "io",
	"mars", "moon", "titan", "venus",
]


static func worlds_from_game(game_root: String) -> Dictionary:
	## Enumerate ``Edit/trn/*.trn`` into the contract's worlds list.
	var trn_dir: String = game_root.path_join("Edit").path_join("trn")
	if not DirAccess.dir_exists_absolute(trn_dir):
		return BzErrors.err(
			"no_trn_templates",
			"no Edit/trn directory under %s" % game_root,
			"the game install is missing its terrain templates",
			trn_dir
		)
	var by_id := {}
	for path in _list_files(trn_dir):
		if path.get_extension().to_lower() != "trn":
			continue
		var world_id: String = path.get_file().get_basename().to_lower()
		by_id[world_id] = _describe_world(path, world_id)
	var worlds: Array = []
	for world_id in STOCK_WORLDS:
		if by_id.has(world_id):
			worlds.append(by_id[world_id])
			by_id.erase(world_id)
	var extras: Array = by_id.keys()
	extras.sort()
	for world_id in extras:
		worlds.append(by_id[world_id])
	if worlds.is_empty():
		return BzErrors.err(
			"no_trn_templates",
			"Edit/trn exists but contains no .trn files: %s" % trn_dir,
			"",
			trn_dir
		)
	return {"ok": true, "worlds": worlds}


static func _describe_world(path: String, world_id: String) -> Dictionary:
	var cfg = _read_trn(path)
	var atlas: String = ""
	var sky: String = ""
	var labels := {}
	if cfg != null:
		var atlas_v: Variant = cfg.value("Atlases", "MaterialName")
		atlas = "" if atlas_v == null else str(atlas_v)
		var sky_tex: Variant = cfg.value("Sky", "SkyTexture")
		var sky_type: Variant = cfg.value("Sky", "SkyType")
		if sky_tex != null and str(sky_tex) != "":
			sky = str(sky_tex)
		elif sky_type != null:
			sky = str(sky_type)
		labels = _texture_labels(cfg)
	var texture_types: Array = []
	if cfg != null:
		for i in 16:
			var section: Variant = cfg.section("TextureType%d" % i)
			if section == null:
				continue
			var flat_v: Variant = section.value("FlatColor")
			var flat: String = "" if flat_v == null else str(flat_v)
			var solid_v: Variant = section.value("SolidA0")
			if solid_v == null:
				solid_v = section.value("SolidB0")
			texture_types.append({
				"index": i,
				"flat_color": _parse_flat_color(flat),
				"label": str(labels.get(i, "")),
				"solid_tile": "" if solid_v == null else str(solid_v).strip_edges(),
			})
	var atlas_name: String = atlas.strip_edges()
	# Edit/trn/mars.trn → game root is parents[2]
	var game_root: String = path.get_base_dir().get_base_dir().get_base_dir()
	var looked: Dictionary = _atlas_lookup(game_root, atlas_name, world_id)
	_apply_trn_solids(looked, texture_types, world_id)
	var palette_name: String = ""
	if cfg != null:
		var pal_v: Variant = cfg.value("Color", "Palette")
		palette_name = "" if pal_v == null else str(pal_v).strip_edges()
	return {
		"id": world_id,
		"label": world_id.capitalize(),
		"trn_template": "Edit".path_join("trn").path_join(path.get_file()),
		"atlas": atlas_name,
		"atlas_image": looked["atlas_image"],
		"tile_uvs": looked["tile_uvs"],
		"atlas_tiles": looked.get("atlas_tiles", {}),
		"sky": sky.strip_edges(),
		# The world's stock .act. Fog colour is a palette entry (F6 §3), so a
		# map that wants its own fog colour ships a copy of this file.
		"palette_act": palette_name,
		"palette_path": _act_lookup(game_root, palette_name, world_id),
		"texture_types": texture_types,
	}


static func _act_lookup(game_root: String, palette_name: String, world_id: String) -> String:
	## Absolute path of the world's `.act`, or "" when the install does not
	## have it where we look. Same candidate-list shape as _atlas_lookup —
	## a full recursive scan of the install per world is not worth it.
	var names: Array[String] = []
	var named: String = palette_name.get_file().strip_edges()
	if not named.is_empty():
		names.append(named)
		if named.get_extension().is_empty():
			names.append("%s.act" % named)
	if not world_id.is_empty():
		names.append("%s.act" % world_id.to_lower())
	var dirs: Array[String] = [
		game_root.path_join("Edit").path_join("act"),
		game_root.path_join("Edit").path_join("Palettes"),
		game_root.path_join("Edit"),
		game_root.path_join("BZ_ASSETS").path_join("pc").path_join("textures"),
		game_root.path_join("BZ_ASSETS").path_join("common").path_join("textures"),
		game_root.path_join("BZ_ASSETS").path_join("common"),
	]
	for name in names:
		for dir_path in dirs:
			var candidate: String = dir_path.path_join(name)
			if FileAccess.file_exists(candidate):
				return candidate
			# Installs differ in case; scan the directory once per miss.
			var found: String = _file_named(dir_path, name)
			if not found.is_empty():
				return found
	return ""


static func _file_named(dir_path: String, name: String) -> String:
	var da := DirAccess.open(dir_path)
	if da == null:
		return ""
	var needle: String = name.to_lower()
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir() and fn.to_lower() == needle:
			da.list_dir_end()
			return dir_path.path_join(fn)
		fn = da.get_next()
	da.list_dir_end()
	return ""


static func _atlas_lookup(game_root: String, atlas_name: String, world_id: String) -> Dictionary:
	## Return ``{atlas_image, tile_uvs}`` for solid tiles.
	var stem: String = atlas_name
	if stem.to_lower().ends_with("_atlas"):
		stem = stem.substr(0, stem.length() - "_atlas".length())
	if stem.is_empty():
		stem = "%s_detail" % world_id.substr(0, mini(2, world_id.length()))
	var candidates: Array[String] = [
		# The per-world diffuse tile atlas — the image the CSV's UV rects
		# actually index. Checked FIRST: the legacy Detail_PNG/Detail files
		# below are close-range noise detail textures on modern installs,
		# and rendering one as the atlas paints the whole map grey.
		game_root.path_join("Edit").path_join("BZ_TERRAIN_ATLASES_DIFF_PNG")
			.path_join("%s_ATLAS_D.png" % world_id.to_upper()),
		game_root.path_join("Edit").path_join("Detail_PNG").path_join("%s.png" % stem),
		game_root.path_join("Edit").path_join("Detail").path_join("%s.dds" % stem),
		game_root.path_join("BZ_ASSETS").path_join("pc").path_join("textures")
			.path_join("TerrainTextures").path_join("Detail").path_join("%s.dds" % stem),
	]
	var image: String = ""
	for c in candidates:
		if FileAccess.file_exists(c):
			image = c
			break
	var uvs: Array = []
	for _i in 16:
		uvs.append([0.0, 0.0, 0.125, 0.125])
	var csv: String = game_root.path_join("Edit").path_join("PlanetMaterials").path_join(
		"%s.csv" % atlas_name
	)
	if not FileAccess.file_exists(csv):
		csv = game_root.path_join("Edit").path_join("PlanetMaterials").path_join(
			"%s_atlas.csv" % stem
		)
	var prefix: String = world_id.substr(0, mini(2, world_id.length())).to_upper()
	if FileAccess.file_exists(csv):
		var text: String = FileAccess.get_file_as_string(csv)
		var found := {}
		for line in text.split("\n"):
			var raw_parts: PackedStringArray = line.split(",")
			if raw_parts.size() < 5:
				continue
			var parts: PackedStringArray = PackedStringArray()
			for p in raw_parts:
				parts.append(String(p).strip_edges())
			var name: String = parts[0].to_upper()
			if (
				not parts[1].strip_edges().is_valid_float()
				or not parts[2].strip_edges().is_valid_float()
				or not parts[3].strip_edges().is_valid_float()
				or not parts[4].strip_edges().is_valid_float()
			):
				continue
			found[name] = [
				parts[1].strip_edges().to_float(),
				parts[2].strip_edges().to_float(),
				parts[3].strip_edges().to_float(),
				parts[4].strip_edges().to_float(),
			]
		for i in 16:
			var key: String = "%s%d%dSA0.MAP" % [prefix, i, i]
			var alt: String = "%s%s%sSA0.MAP" % [prefix, _hex_upper(i), _hex_upper(i)]
			if found.has(key):
				uvs[i] = found[key]
			elif found.has(alt):
				uvs[i] = found[alt]
		# The full tile table (solids, caps, diagonals, variants) so the
		# viewport can draw the exact tile each .mat word names (F2 §4).
		return {"atlas_image": image, "tile_uvs": uvs, "atlas_tiles": found}
	return {"atlas_image": image, "tile_uvs": uvs, "atlas_tiles": {}}


static func _apply_trn_solids(looked: Dictionary, texture_types: Array, world_id: String) -> void:
	## SolidA0 is the fill tile for that type. Usually `{i}{i}SA0`, but
	## Elysium type 4 is EL04SA0 — without this, tile_uvs[4] stays the dummy
	## origin square and the palette/renderer miss the grid-iron tile.
	var tiles: Dictionary = looked.get("atlas_tiles", {})
	if tiles.is_empty():
		return
	var uvs: Array = looked.get("tile_uvs", [])
	var prefix := world_id.substr(0, mini(2, world_id.length())).to_upper()
	for t in texture_types:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var idx := int(t.get("index", -1))
		if idx < 0 or idx >= uvs.size():
			continue
		var rect: Array = _atlas_rect(tiles, str(t.get("solid_tile", "")))
		if rect.size() < 4:
			continue
		uvs[idx] = rect
		var d := _hex_upper(idx)
		var alias := "%s%s%sSA0.MAP" % [prefix, d, d]
		if not tiles.has(alias):
			tiles[alias] = rect
	looked["tile_uvs"] = uvs
	looked["atlas_tiles"] = tiles


static func _atlas_rect(tiles: Dictionary, raw: String) -> Array:
	var name := raw.get_file().strip_edges().to_upper()
	if name.is_empty():
		return []
	for key in [name, name + ".MAP", name.trim_suffix(".MAP")]:
		if tiles.has(key):
			var r: Array = tiles[key]
			if r.size() >= 4:
				return r
	return []


static func _texture_labels(cfg) -> Dictionary:
	## Pull ``// Sandy`` comments off ``[TextureTypeN]`` header lines.
	var labels := {}
	var header_re := RegEx.new()
	header_re.compile("^\\[TextureType(\\d+)\\](.*)$")
	for line in cfg._lines:
		var match: RegExMatch = header_re.search(String(line).strip_edges())
		if match == null:
			continue
		var index: int = int(match.get_string(1))
		var rest: String = match.get_string(2)
		var cut: int = rest.find("//")
		if cut >= 0:
			labels[index] = rest.substr(cut + 2).strip_edges()
		else:
			var stripped: String = rest.strip_edges()
			if not stripped.is_empty() and not stripped.begins_with(";"):
				labels[index] = stripped
	return labels


static func _parse_flat_color(value: String) -> Array:
	## Return an RGB triple. A single number is a palette index, expanded.
	value = value.strip_edges()
	var rgb_re := RegEx.new()
	rgb_re.compile("(\\d+)\\s+(\\d+)\\s+(\\d+)")
	var rgb: RegExMatch = rgb_re.search(value)
	if rgb != null:
		return [int(rgb.get_string(1)), int(rgb.get_string(2)), int(rgb.get_string(3))]
	var parts: PackedStringArray = value.split(" ", false)
	if parts.is_empty() or not parts[0].is_valid_int():
		return [128, 128, 128]
	var n: int = int(parts[0])
	return [n, n, n]


class _TrnView:
	extends RefCounted
	## Read-only subset of TerrainConfig. Private copy so this file does not
	## compile-depend on BzTrn (whose Object.get/set overrides fail as a
	## depended script under warning-as-error).
	var _lines: PackedStringArray = PackedStringArray()
	var _secs: Dictionary = {}

	func load_file(path: String) -> void:
		if not FileAccess.file_exists(path):
			return
		var text: String = FileAccess.get_file_as_string(path)
		if text.begins_with("\uFEFF"):
			text = text.substr(1)
		_lines = text.split("\n")
		for i in _lines.size():
			_lines[i] = _lines[i].trim_suffix("\r")
		var current: String = ""
		for line in _lines:
			var stripped: String = String(line).strip_edges()
			if stripped.is_empty() or stripped.begins_with(";") or stripped.begins_with("#"):
				continue
			if stripped.begins_with("["):
				var close: int = stripped.find("]")
				if close > 0:
					current = stripped.substr(1, close - 1)
					if not _secs.has(current):
						_secs[current] = {}
				continue
			if current.is_empty() or not String(line).contains("="):
				continue
			var eq: int = String(line).find("=")
			var key: String = String(line).substr(0, eq).strip_edges()
			var value: String = String(line).substr(eq + 1).strip_edges()
			var sec: Dictionary = _secs[current]
			if not sec.has(key):
				sec[key] = value
				_secs[current] = sec

	func value(section: String, key: String, default_value: Variant = null) -> Variant:
		if not _secs.has(section):
			return default_value
		var sec: Dictionary = _secs[section]
		if not sec.has(key):
			return default_value
		return sec[key]

	func section(name: String) -> Variant:
		if not _secs.has(name):
			return null
		return _SecView.new(_secs[name])


class _SecView:
	extends RefCounted
	var _items: Dictionary = {}

	func _init(items: Dictionary = {}) -> void:
		_items = items

	func value(key: String, default_value: Variant = null) -> Variant:
		if not _items.has(key):
			return default_value
		return _items[key]


static func _read_trn(path: String) -> _TrnView:
	var cfg := _TrnView.new()
	cfg.load_file(path)
	return cfg


static func _hex_upper(n: int) -> String:
	return ("%x" % n).to_upper()


static func _list_files(dir_path: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir():
			out.append(dir_path.path_join(fn))
		fn = da.get_next()
	da.list_dir_end()
	return out
