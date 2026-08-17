extends RefCounted
class_name BzNew
## ``bzmap editor new`` — create a fresh map session.
##
## Port of ``backend/bzmap/editor/new.py``. Python raises EditorError;
## GDScript returns ``BzErrors.err``. ``create_map`` re-enters through
## ``BzOpen.open_map`` so residue/session buffers share one code path.
##
## docs/02 §3 ``new`` says the world's ``.trn`` template is copied and only
## ``[Size]`` / ``[NormalView]`` / ``[World]`` / ``[Sky]`` are overridden.
## Python ``write_complete_trn`` rewrites only ``[Size]`` (standalone origin
## + Width/Depth). Python wins.
##
## Format/session classes are reached via ``load()`` rather than class_name
## identifiers. Godot 4.7 ``-s`` mode binds a class_name to a bare GDScript
## (static methods missing) when this file lists too many global classes,
## especially inner types like ``BzHg2.HeightMap``.

const KNOWN_TERRAIN_COLLISIONS := []

const _DEFAULT_PAINT_RULES := [
	{"mat_id": 0, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.0, "max_s": 0.05},
	{"mat_id": 1, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.05, "max_s": 0.25},
	{"mat_id": 2, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.25, "max_s": 10.0},
]

const _ZONE_SIZE := 256


static func create_map(
	stem: String,
	world: String,
	width_m: int,
	depth_m: int,
	session_dir: String,
	game_root: String,
	base_height: int = 1000,
	pack_kind: String = "bzp"
) -> Dictionary:
	## Create a new map session. Returns the open-map response dict.
	stem = str(stem)
	if stem.length() > 8:
		return BzErrors.err(
			"stem_too_long",
			"terrain stem %s is %d characters; the engine truncates script lookups above 8"
			% [_py_repr(stem), stem.length()],
			"use a stem of 8 characters or fewer"
		)
	if stem.is_empty() or not _stem_alnum_ok(stem):
		return BzErrors.err("bad_stem", "stem %s is empty or not alphanumeric" % _py_repr(stem))

	var disc: GDScript = _script("res://project/backend/editor/BzDiscover.gd")
	if game_root.is_empty():
		game_root = str(disc.call("first_game_root")) if disc != null else ""
	if game_root.is_empty():
		return BzErrors.err(
			"no_game",
			"no game install found; pass --game-root",
			"probe first, or install Battlezone 98 Redux"
		)

	var taken: Dictionary = _known_terrain_names(game_root, disc)
	if taken.has(stem.to_lower()):
		return BzErrors.err(
			"stem_collision",
			"terrain name %s collides with an installed map" % _py_repr(stem),
			"terrain names are global across loaded mods"
		)

	world = world.to_lower()
	var available: Dictionary = {}
	var wr: Dictionary = BzWorlds.worlds_from_game(game_root)
	if wr.get("ok") == true:
		for w in wr.get("worlds", []):
			if typeof(w) == TYPE_DICTIONARY:
				available[str((w as Dictionary).get("id", ""))] = true
	# Python: EditorError from worlds_from_game → treat as STOCK_WORLDS only.
	if not available.has(world) and not _is_stock_world(world):
		return BzErrors.err(
			"unknown_world",
			"unknown world %s" % _py_repr(world),
			"stock worlds: %s" % ", ".join(BzWorlds.STOCK_WORLDS)
		)

	if base_height < 1 or base_height > 4095:
		return BzErrors.err(
			"bad_base_height",
			"base_height %d is outside the authoring range 1..4095" % base_height
		)

	var template_trn: String = game_root.path_join("Edit").path_join("trn").path_join("%s.trn" % world)
	if not FileAccess.file_exists(template_trn):
		var trn_dir: String = game_root.path_join("Edit").path_join("trn")
		template_trn = ""
		if DirAccess.dir_exists_absolute(trn_dir):
			for p in _list_files(trn_dir):
				if (
					FileAccess.file_exists(p)
					and p.get_file().get_basename().to_lower() == world
					and p.get_extension().to_lower() == "trn"
				):
					template_trn = p
					break
		if template_trn.is_empty():
			return BzErrors.err(
				"no_world_template",
				"no Edit/trn/%s.trn in %s" % [world, game_root],
				"",
				game_root.path_join("Edit").path_join("trn")
			)

	var paths: Dictionary = _ensure_session_dir(session_dir)
	if BzErrors.is_err(paths):
		return paths
	var staging: String = str(paths["source"])

	var hm_v: Variant = _flat_heightmap(width_m, depth_m, base_height)
	if BzErrors.is_err(hm_v):
		return hm_v
	var heightmap = hm_v
	if heightmap == null:
		return BzErrors.err("value_error", "failed to build flat heightmap")
	var wr_hg2: Variant = heightmap.write(staging.path_join("%s.hg2" % stem))
	if typeof(wr_hg2) == TYPE_DICTIONARY and wr_hg2.get("ok") == false:
		return wr_hg2
	var mat: GDScript = _script("res://project/backend/formats/BzMat.gd")
	if mat == null:
		return BzErrors.err("backend_crash", "BzMat is not available")
	var painted: Variant = mat.call("auto_paint", heightmap, _DEFAULT_PAINT_RULES)
	if BzErrors.is_err(painted) or (typeof(painted) == TYPE_DICTIONARY and painted.get("ok") == false):
		if typeof(painted) == TYPE_DICTIONARY:
			return painted
		return BzErrors.err("value_error", "auto_paint failed")
	if typeof(painted) == TYPE_DICTIONARY:
		return BzErrors.err("value_error", "auto_paint did not return a MaterialGrid")
	var wr_mat: Variant = painted.write(staging.path_join("%s.mat" % stem))
	if typeof(wr_mat) == TYPE_DICTIONARY and wr_mat.get("ok") == false:
		return wr_mat
	_write_complete_trn(staging.path_join("%s.trn" % stem), width_m, depth_m, template_trn)
	var ini: GDScript = _script("res://project/backend/formats/BzIni.gd")
	if ini != null:
		ini.call("write_ini", staging.path_join("%s.ini" % stem), stem, "multiplayer")
	var des: GDScript = _script("res://project/backend/formats/BzDes.gd")
	if des != null:
		des.call(
			"write_des",
			staging.path_join("%s.des" % stem),
			stem,
			world.capitalize(),
			"%dx%d" % [width_m, depth_m],
			0,
			0,
			14
		)
	if pack_kind == "bzp":
		var odf: GDScript = _script("res://project/backend/formats/BzOdf.gd")
		if odf != null:
			odf.call("write_odf", staging.path_join("%s.odf" % stem))
	var vxt: GDScript = _script("res://project/backend/formats/BzVxt.gd")
	if vxt != null:
		vxt.call("write_standard_vxt", staging.path_join("%s.vxt" % stem))
	_bake_lgt(heightmap, staging.path_join("%s.lgt" % stem))

	var warnings: Array = []
	var template_bzn: String = _find_template_bzn(disc)
	var variants: Array = ["", "_S", "_ST", "_SW"]
	if not template_bzn.is_empty():
		var bzns: Dictionary = _build_starter_bzns(template_bzn, stem, heightmap, variants)
		if bzns.is_empty():
			warnings.append(
				"no stock BZN with player + pspwn_1 templates was found; session has terrain but no objects"
			)
		for variant in bzns.keys():
			var name: String = "%s%s.bzn" % [stem, variant] if str(variant) != "" else "%s.bzn" % stem
			var bzn = bzns[variant]
			var wr_b: Variant = bzn.write(staging.path_join(name))
			if typeof(wr_b) == TYPE_DICTIONARY and wr_b.get("ok") == false:
				return wr_b
	else:
		warnings.append(
			"no stock BZN with player + pspwn_1 templates was found; session has terrain but no objects"
		)

	var result: Dictionary = _open_map(staging.path_join("%s.trn" % stem), session_dir)
	if BzErrors.is_err(result) or result.get("ok") == false:
		return result
	if not warnings.is_empty():
		var existing_w: Array = result.get("warnings", [])
		existing_w.append_array(warnings)
		result["warnings"] = existing_w
	var manifest: Dictionary = result.get("manifest", {})
	if typeof(manifest) != TYPE_DICTIONARY:
		manifest = {}
	manifest["source_path"] = ""
	manifest["world"] = world
	manifest["pack_context"] = {"kind": "bzp"} if pack_kind == "bzp" else {"kind": "base"}
	var wr_man: Dictionary = _write_json(str(paths["manifest"]), manifest)
	if BzErrors.is_err(wr_man):
		return wr_man
	result["manifest"] = manifest
	return result


static func _known_terrain_names(game_root: String, disc: GDScript) -> Dictionary:
	var names := {}
	var trn_dir: String = game_root.path_join("Edit").path_join("trn")
	if DirAccess.dir_exists_absolute(trn_dir):
		for p in _list_files(trn_dir):
			if p.get_extension().to_lower() == "trn":
				names[p.get_file().get_basename().to_lower()] = true
	var discovery := {}
	if disc != null:
		var got: Variant = disc.call("discover")
		if typeof(got) == TYPE_DICTIONARY:
			discovery = got
	for item_v in discovery.get("installs", []):
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		if str(item.get("kind", "")) != "workshop_item":
			continue
		var root: String = str(item.get("path", ""))
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue
		for p in _list_files(root):
			if p.get_extension().to_lower() == "trn":
				names[p.get_file().get_basename().to_lower()] = true
	return names


static func _find_template_bzn(disc: GDScript) -> String:
	## Return a stock .bzn that can clone player + pspwn_1, or "".
	var discovery := {}
	if disc != null:
		var got: Variant = disc.call("discover")
		if typeof(got) == TYPE_DICTIONARY:
			discovery = got
	var candidates: Array = []
	for item_v in discovery.get("installs", []):
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		if str(item.get("kind", "")) != "workshop_item":
			continue
		var root: String = str(item.get("path", ""))
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue
		for p in _list_files(root):
			if p.get_extension().to_lower() == "bzn":
				candidates.append(p)
	var search: Array = []
	for p in candidates:
		if str(p).get_file().get_basename().to_lower() == "umoonwar":
			search.append(p)
	search.append_array(candidates)
	for path_v in search:
		var path: String = str(path_v)
		if _bzn_has_prjid(path, "player") and _bzn_has_prjid(path, "pspwn_1"):
			return path
	return ""


static func _bzn_has_prjid(path: String, prjid: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text: String = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = text.split("\n")
	for i in lines.size():
		if lines[i].strip_edges().to_lower() == "prjid [1] =":
			if i + 1 < lines.size() and lines[i + 1].strip_edges() == prjid:
				return true
	return false


static func _flat_heightmap(width_m: int, depth_m: int, base_height: int) -> Variant:
	if width_m % 1280 != 0 or depth_m % 1280 != 0:
		return BzErrors.err(
			"bad_dimensions",
			"width and depth must be multiples of 1280 (got %dx%d)" % [width_m, depth_m],
			"legal sizes are 1280, 2560, 3840, 5120; non-square is allowed"
		)
	var hg2: GDScript = _script("res://project/backend/formats/BzHg2.gd")
	if hg2 == null:
		return BzErrors.err("backend_crash", "BzHg2 is not available")
	var zone: int = int(hg2.get("ZONE_SIZE")) if hg2.get("ZONE_SIZE") != null else _ZONE_SIZE
	var zones_x: int = width_m / 1280
	var zones_z: int = depth_m / 1280
	var n: int = zones_z * zone * zones_x * zone
	var data := PackedInt32Array()
	data.resize(n)
	data.fill(int(base_height))
	return hg2.HeightMap.new(zones_x, zones_z, data)


static func _bake_lgt(heightmap, path: String) -> void:
	## North-light slope bake. Never zero-fill (black in-game radar).
	## Private copy of new.py ``_bake_lgt`` — BzLgt is copy-only (unresolved layout).
	var zone: int = _ZONE_SIZE
	var planes: int = int(heightmap.zonesX) * int(heightmap.zonesZ) + 1
	var gx: int = int(heightmap.grid_x)
	var gz: int = int(heightmap.grid_z)
	var raw: PackedInt32Array = heightmap.data
	var shade := PackedByteArray()
	shade.resize(gx * gz)
	for z in gz:
		for x in gx:
			var dz := 0.0
			if z > 0 and z < gz - 1:
				dz = (float(raw[(z + 1) * gx + x]) - float(raw[(z - 1) * gx + x])) / 2.0
			var s: float = 56.0 + clampf((-dz) * 2.0 + 80.0, 0.0, 199.0)
			shade[z * gx + x] = int(s)
	var out := PackedByteArray()
	out.resize(planes * zone * zone)
	out.fill(56)
	var plane: int = 1
	for zz in int(heightmap.zonesZ):
		for zx in int(heightmap.zonesX):
			var dest: int = plane * zone * zone
			for sub_z in zone:
				var src_row: int = (zz * zone + sub_z) * gx + zx * zone
				var dst_row: int = dest + sub_z * zone
				for sub_x in zone:
					out[dst_row + sub_x] = shade[src_row + sub_x]
			plane += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(out)
	f.close()


static func _append_mission_trailer(bzn) -> void:
	## Ensure the mission record sits at the end of the last object block.
	if bzn.objects.is_empty():
		return
	var last = bzn.objects[bzn.objects.size() - 1]
	var text: String = "\r\n".join(last.lines)
	if text.contains("sObject ="):
		return
	var sobject: int = bzn.objects.size() + 1
	last.lines.append("name = MultSTMission")
	last.lines.append("sObject = %s" % _hex_upper8(sobject))


static func _build_starter_bzns(template_bzn: String, stem: String, heightmap, variants: Array) -> Dictionary:
	## Clone player + spawn-ring scaffolds into one BznFile per variant.
	var bzn_mod: GDScript = _script("res://project/backend/formats/BzBzn.gd")
	var hg2: GDScript = _script("res://project/backend/formats/BzHg2.gd")
	if bzn_mod == null or hg2 == null:
		return {}
	var loaded: Variant = bzn_mod.call("read_bzn", template_bzn)
	if typeof(loaded) != TYPE_DICTIONARY or not bool(loaded.get("ok", false)):
		return {}
	var src_bzn = loaded.get("bznfile")
	if src_bzn == null:
		return {}
	var player_text := ""
	var spawn_text := ""
	for obj in src_bzn.objects:
		var prj: String = "" if obj.prjid == null else str(obj.prjid)
		if prj == "player" and player_text.is_empty():
			player_text = str(obj.render())
		if prj == "pspwn_1" and spawn_text.is_empty():
			spawn_text = str(obj.render())
	if player_text.is_empty() or spawn_text.is_empty():
		return {}
	var header_text: String = "\r\n".join(src_bzn.header)
	var tail_text: String = "\r\n".join(src_bzn.tail)
	var width_m: float = float(heightmap.width_m)
	var depth_m: float = float(heightmap.depth_m)
	var cx: float = width_m / 2.0
	var cz: float = depth_m / 2.0
	var cy: float = float(hg2.call("sample_m", heightmap, cx, cz))
	var radius: float = minf(width_m, depth_m) * 0.30
	var files := {}
	for variant_v in variants:
		var variant: String = str(variant_v)
		var n_spawns: int = 2 if variant == "_S" else 14
		var blocks: Array = []
		var player = bzn_mod.GameObject.from_template(player_text)
		player.set_position(cx, cy, cz)
		player.set_yaw(0.0)
		player.set_identity(0, 1, "%s0_player" % stem)
		player.set_team(1)
		player.set_is_user(true)
		blocks.append(player)
		for i in n_spawns:
			var ang: float = (2.0 * PI * float(i)) / float(n_spawns)
			var x: float = cx + radius * cos(ang)
			var z: float = cz + radius * sin(ang)
			var y: float = float(hg2.call("sample_m", heightmap, x, z))
			var spawn = bzn_mod.GameObject.from_template(spawn_text)
			spawn.set_position(x, y, z)
			spawn.set_yaw(ang)
			spawn.set_identity(i + 1, i + 2, "%s%d_spawn" % [stem, i + 1])
			spawn.set_team(0)
			spawn.set_is_user(false)
			blocks.append(spawn)
		var bzn = bzn_mod.BznFile.build(header_text, blocks, tail_text)
		bzn.set_header("size [1]", blocks.size())
		bzn.set_header("seq_count [1]", blocks.size())
		bzn.set_header("msn_filename", "%s.bzn" % stem)
		bzn.set_header("TerrainName", stem)
		_append_mission_trailer(bzn)
		files[variant] = bzn
	return files


static func _write_complete_trn(path: String, width_m: int, depth_m: int, template_path: String) -> void:
	## Private copy of BzTrn.write_complete_trn (no compile dep on BzTrn).
	if not FileAccess.file_exists(template_path):
		return
	var text: String = FileAccess.get_file_as_string(template_path)
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	var lines: PackedStringArray = PackedStringArray()
	for raw in text.split("\n"):
		lines.append(String(raw).trim_suffix("\r"))
	var replacements := {
		"MinX": "0",
		"MinZ": "0",
		"Height": "0.000000",
		"Width": str(int(width_m)),
		"Depth": str(int(depth_m)),
	}
	var in_size := false
	var seen := {}
	for i in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped.begins_with("["):
			var close: int = stripped.find("]")
			in_size = close > 0 and stripped.substr(1, close - 1) == "Size"
			continue
		if not in_size or not stripped.contains("="):
			continue
		var key: String = stripped.substr(0, stripped.find("=")).strip_edges()
		if replacements.has(key):
			lines[i] = "%s = %s" % [key, replacements[key]]
			seen[key] = true
	var insert_at: int = -1
	var saw_size := false
	for i in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped.begins_with("[") and stripped.find("]") > 0:
			var name: String = stripped.substr(1, stripped.find("]") - 1)
			if saw_size and name != "Size":
				insert_at = i
				break
			if name == "Size":
				saw_size = true
		if saw_size:
			insert_at = i + 1
	if insert_at < 0:
		insert_at = lines.size()
	var pending: Array[String] = []
	for key in ["MinX", "MinZ", "Height", "Width", "Depth"]:
		if not seen.has(key):
			pending.append("%s = %s" % [key, replacements[key]])
	for j in pending.size():
		lines.insert(insert_at + j, pending[j])
	var out: String = "\r\n".join(lines)
	if not lines.is_empty():
		out += "\r\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(out.to_utf8_buffer())
	f.close()


static func _open_map(path: String, session_dir: String) -> Dictionary:
	## Private copy of open.py open_map. BzOpen/BzSession currently fail to
	## compile (BzSession uses String.is_absolute(), missing in 4.7.1).
	var directory: String = path.get_base_dir()
	var stem: String = path.get_file().get_basename()
	var files: Array = []
	for p in _list_files(directory):
		var name: String = str(p).get_file().to_lower()
		var sl: String = stem.to_lower()
		if name.begins_with(sl + ".") or name.begins_with(sl + "_") or name == sl + "map.lua":
			files.append(p)
	var warnings: Array = []
	var paths: Dictionary = _ensure_session_dir(session_dir)
	if BzErrors.is_err(paths):
		return paths
	var source_dir: String = str(paths["source"])
	for src in files:
		var dest: String = source_dir.path_join(str(src).get_file())
		if dest.simplify_path() != str(src).simplify_path():
			DirAccess.copy_absolute(str(src), dest)
	var hg2_path: String = _find_source_file(source_dir, stem, ".hg2")
	if hg2_path.is_empty():
		return BzErrors.err(
			"missing_hg2",
			"no .hg2 for stem %s next to %s" % [_py_repr(stem), path],
			"",
			directory
		)
	var hg2: GDScript = _script("res://project/backend/formats/BzHg2.gd")
	if hg2 == null:
		return BzErrors.err("backend_crash", "BzHg2 is not available")
	var hm_r: Variant = hg2.call("read_hg2", hg2_path)
	if typeof(hm_r) != TYPE_DICTIONARY or not bool(hm_r.get("ok", false)):
		return hm_r if typeof(hm_r) == TYPE_DICTIONARY else BzErrors.err("value_error", "failed to read hg2")
	var heightmap = hm_r.get("heightmap")
	if heightmap == null:
		return BzErrors.err("value_error", "BzHg2.read_hg2 did not return a HeightMap", "", hg2_path)
	_write_terrain_r16(str(paths["terrain"]), heightmap)
	_write_hg2_flags(str(paths["hg2_flags"]), heightmap)
	_write_json(str(paths["hg2_header"]), {
		"version": heightmap.version,
		"depth": heightmap.depth,
		"zonesX": heightmap.zonesX,
		"zonesZ": heightmap.zonesZ,
		"unknownA": heightmap.unknownA,
		"unknownB": heightmap.unknownB,
	})
	var mat_grid_x: int
	var mat_grid_z: int
	var mat_path: String = _find_source_file(source_dir, stem, ".mat")
	var mat: GDScript = _script("res://project/backend/formats/BzMat.gd")
	if not mat_path.is_empty() and mat != null:
		var mat_r: Variant = mat.MaterialGrid.read(mat_path)
		if typeof(mat_r) == TYPE_DICTIONARY and bool(mat_r.get("ok", false)):
			var grid = mat_r.get("grid")
			_write_u16(str(paths["materials"]), grid.data)
			mat_grid_x = int(grid.grid_x)
			mat_grid_z = int(grid.grid_z)
		else:
			return mat_r if typeof(mat_r) == TYPE_DICTIONARY else BzErrors.err("value_error", "failed to read MAT")
	else:
		warnings.append("no .mat in the basename group")
		mat_grid_x = int(heightmap.grid_x) / 4
		mat_grid_z = int(heightmap.grid_z) / 4
		var empty := PackedInt32Array()
		empty.resize(mat_grid_z * mat_grid_x)
		empty.fill(0)
		_write_u16(str(paths["materials"]), empty)
	var objects := {"": [], "_S": [], "_ST": [], "_SW": []}
	var present_variants: Array = []
	var objs: GDScript = _script("res://project/backend/editor/BzObjects.gd")
	for variant in ["", "_S", "_ST", "_SW"]:
		var suffix: String = "%s.bzn" % variant if variant != "" else ".bzn"
		var bzn_path: String = _find_source_file(source_dir, stem, suffix)
		if bzn_path.is_empty() or objs == null:
			continue
		var prefix: String = "obj" if variant == "" else "obj%s" % variant.to_lower()
		var loaded: Variant = objs.call("load_variant_objects", bzn_path, prefix)
		if typeof(loaded) == TYPE_DICTIONARY and loaded.get("ok") == true:
			objects[variant] = loaded.get("records", [])
			present_variants.append(variant)
	if present_variants.is_empty():
		warnings.append("no .bzn in the basename group")
		present_variants = [""]
	var features := {"water": [], "plants": []}
	_write_json(str(paths["objects"]), objects)
	_write_json(str(paths["features"]), features)
	_write_json(str(paths["meta"]), {})
	var dirty_objects := {}
	for v in present_variants:
		dirty_objects[str(v)] = []
	_write_json(str(paths["dirty"]), {
		"terrain": false,
		"materials": false,
		"objects": dirty_objects,
		"features": false,
		"meta": [],
	})
	var over := false
	var words: PackedInt32Array = heightmap.data
	for i in words.size():
		if (words[i] & 0x1FFF) > 4095:
			over = true
			break
	if over:
		warnings.append(
			"source heightmap has cells above the editor authoring ceiling (raw 4095); inherited values are preserved"
		)
	var has_lgt: bool = not _find_source_file(source_dir, stem, ".lgt").is_empty()
	var manifest := {
		"contract_version": 1,
		"stem": stem,
		"source_path": directory,
		"converted_from_binary": false,
		"world": "",
		"width_m": int(heightmap.width_m),
		"depth_m": int(heightmap.depth_m),
		"grid_x": int(heightmap.grid_x),
		"grid_z": int(heightmap.grid_z),
		"cell_m": 5.0,
		"height_scale": 0.1,
		"height_max_raw": 4095,
		"height_over_ceiling": over,
		"mat_grid_x": int(mat_grid_x),
		"mat_grid_z": int(mat_grid_z),
		"mat_cell_m": 20.0,
		"variants": present_variants,
		"has_lightmap": has_lgt,
		"pack_context": {"kind": "bzp"} if _find_source_file(source_dir, stem, ".odf") != "" else {"kind": "base"},
	}
	_write_json(str(paths["manifest"]), manifest)
	return {
		"ok": true,
		"session": str(paths["root"]),
		"manifest": manifest,
		"warnings": warnings,
	}


static func _session_paths(session_dir: String) -> Dictionary:
	var root: String = session_dir
	var residue: String = root.path_join("residue")
	return {
		"root": root,
		"manifest": root.path_join("manifest.json"),
		"terrain": root.path_join("terrain.r16"),
		"materials": root.path_join("materials.u16"),
		"objects": root.path_join("objects.json"),
		"features": root.path_join("features.json"),
		"meta": root.path_join("meta.json"),
		"dirty": root.path_join("dirty.json"),
		"masks": root.path_join("masks"),
		"residue": residue,
		"source": residue.path_join("source"),
		"hg2_header": residue.path_join("hg2_header.json"),
		"hg2_flags": residue.path_join("hg2_flags.u8"),
	}


static func _ensure_session_dir(session_dir: String) -> Dictionary:
	var paths: Dictionary = _session_paths(session_dir)
	for key in ["root", "masks", "residue", "source"]:
		DirAccess.make_dir_recursive_absolute(str(paths[key]))
	return paths


static func _write_json(path: String, payload: Variant) -> Dictionary:
	var text: String = JSON.stringify(payload, "  ")
	if not text.ends_with("\n"):
		text += "\n"
	var parent: String = path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return BzErrors.err("write_failed", "cannot write %s" % path, "", path)
	f.store_string(text)
	f.close()
	return {"ok": true}


static func _find_source_file(source_dir: String, stem: String, suffix: String) -> String:
	var target: String = (stem + suffix).to_lower()
	for p in _list_files(source_dir):
		if str(p).get_file().to_lower() == target:
			return str(p)
	return ""


static func _write_terrain_r16(path: String, heightmap) -> void:
	var words: PackedInt32Array = heightmap.data
	var bytes := PackedByteArray()
	bytes.resize(words.size() * 2)
	for i in words.size():
		bytes.encode_u16(i * 2, words[i] & 0x1FFF)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)


static func _write_hg2_flags(path: String, heightmap) -> void:
	var words: PackedInt32Array = heightmap.data
	var flags := PackedByteArray()
	flags.resize(words.size())
	for i in words.size():
		flags[i] = (words[i] >> 13) & 0xFF
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(flags)


static func _write_u16(path: String, values: PackedInt32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 2)
	for i in values.size():
		bytes.encode_u16(i * 2, values[i] & 0xFFFF)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)


static func _script(path: String) -> GDScript:
	var loaded: Variant = load(path)
	if loaded is GDScript:
		return loaded
	return null


static func _stem_alnum_ok(stem: String) -> bool:
	var s: String = stem.replace("_", "")
	if s.is_empty():
		return false
	for i in s.length():
		var c: int = s.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_upper: bool = c >= 65 and c <= 90
		var is_lower: bool = c >= 97 and c <= 122
		if not (is_digit or is_upper or is_lower):
			return false
	return true


static func _is_stock_world(world_id: String) -> bool:
	for w in BzWorlds.STOCK_WORLDS:
		if w == world_id:
			return true
	return false


static func _hex_upper8(n: int) -> String:
	return ("%x" % n).to_upper().pad_zeros(8)


static func _py_repr(s: String) -> String:
	return "'%s'" % s.replace("\\", "\\\\").replace("'", "\\'")


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
