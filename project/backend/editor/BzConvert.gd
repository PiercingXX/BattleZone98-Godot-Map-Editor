extends RefCounted
class_name BzConvert
## Convert a placeable class to a Godot-loadable ``.glb``.
##
## Port of ``backend/bzmap/editor/convert.py``. Python returns
## ``(path_or_None, …)`` tuples; GDScript returns Arrays of the same slots.
## ``convert.py`` does not import numpy (assignment note); array work is in
## the format classes and is passed through as Packed*/Array values.
##
## Images: PIL ``Image`` → Godot ``Image`` (RGBA8). ``.map`` goes through
## BzMaptex; other suffixes use ``Image.load``.


static func casefold_index(roots: Array) -> Dictionary:
	## Map lowercased filename → path for files under ``roots``.
	var index := {}
	for root_v in roots:
		var root: String = str(root_v)
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			# DirAccess.open also accepts res:// ; try that before skipping.
			var probe := DirAccess.open(root)
			if probe == null:
				continue
		_index_walk(root, index)
	return index


static func resolve(index: Dictionary, name: String, suffixes: Array) -> Variant:
	var stem: String = name.get_file().get_basename().to_lower()
	var raw: String = name.to_lower()
	for suf_v in suffixes:
		var suf: String = str(suf_v)
		var key: String = raw if raw.ends_with(suf) else stem + suf
		if index.has(key):
			return index[key]
	return null


static func parse_material_diffuse(path: String) -> Variant:
	var text: Variant = _read_latin1(path)
	if text == null:
		return null
	for line in _splitlines(str(text)):
		var s: String = line.strip_edges()
		var low: String = s.to_lower()
		if low.contains("set_texture_alias") and low.contains("diffusemap"):
			var parts: PackedStringArray = _split_ws(s)
			if not parts.is_empty():
				return _strip_quotes(parts[parts.size() - 1])
		if low.begins_with("texture "):
			var rest: String = s.substr(8).strip_edges()
			return _strip_quotes(rest)
	return null


static func convert_hd(stem: String, index: Dictionary, dest: String) -> Array:
	var mesh_path: Variant = resolve(index, stem, [".mesh"])
	if mesh_path == null:
		return [null, "no .mesh"]
	var ogre_res: Dictionary = BzOgre.read_ogre_mesh(str(mesh_path))
	if not bool(ogre_res.get("ok", false)):
		var msg: String = _err_message(ogre_res, "ogre read failed")
		return [null, "hd: %s" % msg]
	var ogre: Variant = ogre_res.get("mesh")
	if ogre == null:
		return [null, "empty ogre mesh"]
	var images: Array = []
	var prims: Array = []
	for sm_v in ogre.submeshes:
		var sm: Variant = sm_v
		var positions: Variant = sm.positions
		var indices: Variant = sm.indices
		if _seq_empty(positions) or _seq_empty(indices):
			continue
		var img_i: Variant = null
		var mat_name: String = stem
		if sm.material != null and not str(sm.material).is_empty():
			mat_name = str(sm.material)
		var mat_path: Variant = resolve(index, mat_name, [".material"])
		var tex_name: Variant = null
		if mat_path != null:
			tex_name = parse_material_diffuse(str(mat_path))
		if tex_name == null and sm.material != null and not str(sm.material).is_empty():
			tex_name = sm.material
		var img: Image = null
		if tex_name != null:
			img = _open_image(index, str(tex_name))
		if img == null:
			img = _open_image(index, stem + "_d")
		if img == null:
			img = _open_image(index, stem + "_D")
		if img != null:
			img_i = images.size()
			images.append(img)
		var normals: Variant = sm.normals
		var uvs: Variant = sm.uvs
		if _seq_empty(normals):
			normals = _filled_vec3(positions, Vector3(0.0, 1.0, 0.0))
		if _seq_empty(uvs):
			uvs = _filled_vec2(positions, Vector2.ZERO)
		prims.append({
			"positions": positions,
			"normals": normals,
			"uvs": uvs,
			"indices": indices,
			"image": img_i,
			"colour": [200, 200, 200],
		})
	if prims.is_empty():
		return [null, "empty ogre mesh"]
	var wr: Dictionary = BzGlb.write_glb(dest, prims, images)
	if not bool(wr.get("ok", false)):
		return [null, _err_message(wr, "glb write failed")]
	return [dest, "hd"]


static func convert_geo_file(
	geo_path: String, index: Dictionary, dest: String, xform: Variant = null
) -> Array:
	var mesh: BzGeo.GeoMesh = BzGeo.read_geo(geo_path)
	if mesh == null:
		return [null, "empty geo"]
	var groups: Array = BzGeo.geo_to_primitives(mesh)
	var images: Array = []
	var prims: Array = []
	for g_v in groups:
		var g: Dictionary = g_v
		var verts: Array = g.get("verts", [])
		var norms: Array = g.get("norms", [])
		if xform != null:
			var xverts: Array = []
			var xnorms: Array = []
			for v in verts:
				xverts.append(BzBwd2.xform_point(xform, v))
			for n in norms:
				xnorms.append(BzBwd2.xform_dir(xform, n))
			verts = xverts
			norms = xnorms
		var img_i: Variant = null
		var tex: Variant = g.get("texture", "")
		if tex != null and not str(tex).is_empty():
			var img: Image = _open_image(index, str(tex))
			if img != null:
				img_i = images.size()
				images.append(img)
		prims.append({
			"positions": verts,
			"normals": norms,
			"uvs": g.get("uvs", []),
			"indices": g.get("indices", []),
			"image": img_i,
			"colour": g.get("colour", [180, 180, 180]),
		})
	if prims.is_empty():
		return [null, "empty geo"]
	var wr: Dictionary = BzGlb.write_glb(dest, prims, images)
	if not bool(wr.get("ok", false)):
		return [null, _err_message(wr, "glb write failed")]
	var fidelity: String = "geo_flat" if images.is_empty() else "geo_textured"
	return [dest, fidelity]


static func convert_bwd2(stem: String, index: Dictionary, dest: String) -> Array:
	var container: Variant = resolve(index, stem, [".sdf", ".vdf"])
	if container == null:
		var geo: Variant = resolve(index, stem, [".geo"])
		if geo == null:
			return [null, "no sdf/vdf/geo"]
		return convert_geo_file(str(geo), index, dest)
	var model: BzBwd2.Bwd2Model = BzBwd2.read_bwd2(str(container))
	if model == null:
		return [null, "no visible nodes"]
	var nodes: Array = BzBwd2.visible_primary(model.nodes)
	if nodes.is_empty():
		var geo2: Variant = resolve(index, stem, [".geo"])
		if geo2 == null:
			return [null, "no visible nodes"]
		return convert_geo_file(str(geo2), index, dest)
	var images: Array = []
	var prims: Array = []
	for node_v in nodes:
		var node: Variant = node_v
		var geo_path: Variant = resolve(index, str(node.name), [".geo"])
		if geo_path == null:
			continue
		var mesh: BzGeo.GeoMesh = BzGeo.read_geo(str(geo_path))
		if mesh == null:
			continue
		for g_v in BzGeo.geo_to_primitives(mesh):
			var g: Dictionary = g_v
			var verts: Array = []
			var norms: Array = []
			for v in g.get("verts", []):
				verts.append(BzBwd2.xform_point(node.transform, v))
			for n in g.get("norms", []):
				norms.append(BzBwd2.xform_dir(node.transform, n))
			var img_i: Variant = null
			var tex: Variant = g.get("texture", "")
			if tex != null and not str(tex).is_empty():
				var img: Image = _open_image(index, str(tex))
				if img != null:
					img_i = images.size()
					images.append(img)
			prims.append({
				"positions": verts,
				"normals": norms,
				"uvs": g.get("uvs", []),
				"indices": g.get("indices", []),
				"image": img_i,
				"colour": g.get("colour", [180, 180, 180]),
			})
	if prims.is_empty():
		return [null, "bwd2 produced no geometry"]
	var fidelity: String = "geo_textured" if not images.is_empty() else "geo_flat"
	var wr: Dictionary = BzGlb.write_glb(dest, prims, images)
	if not bool(wr.get("ok", false)):
		return [null, _err_message(wr, "glb write failed")]
	return [dest, fidelity]


static func convert_class(stem: String, search_roots: Array, dest: String) -> Array:
	## Best-effort convert. Returns ``[path_or_null, fidelity, reason]``.
	dest = _abspath(dest)
	var parent: String = dest.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var index: Dictionary = casefold_index(search_roots)
	var hd_reason: String = ""
	var hd: Array = convert_hd(stem, index, dest)
	if hd[0] != null and str(hd[0]) != "":
		return [hd[0], "hd", ""]
	hd_reason = str(hd[1])
	var geo_reason: String = ""
	var geo: Array = convert_bwd2(stem, index, dest)
	if geo[0] != null and str(geo[0]) != "":
		return [geo[0], str(geo[1]), ""]
	geo_reason = str(geo[1])
	return [null, "proxy", "%s; %s" % [hd_reason, geo_reason]]


# -- image / walk helpers ----------------------------------------------------


static func _open_image(index: Dictionary, name: String) -> Image:
	if name.is_empty():
		return null
	var path_v: Variant = resolve(index, name, [".png", ".dds", ".jpg", ".tga", ".map"])
	if path_v == null:
		return null
	var path: String = str(path_v)
	var suf: String = "." + path.get_extension().to_lower()
	if suf == ".map":
		var act: Variant = null
		var parent: String = path.get_base_dir()
		var da := DirAccess.open(parent)
		if da != null:
			da.include_hidden = true
			da.include_navigational = false
			da.list_dir_begin()
			var fn: String = da.get_next()
			while fn != "":
				if not da.current_is_dir() and fn.get_extension().to_lower() == "act":
					var act_res: Dictionary = BzMaptex.read_act(parent.path_join(fn))
					if bool(act_res.get("ok", false)):
						act = act_res.get("palette")
						break
				fn = da.get_next()
			da.list_dir_end()
		var map_res: Dictionary = BzMaptex.read_map(path, act)
		if not bool(map_res.get("ok", false)):
			return null
		var img_v: Variant = map_res.get("image")
		return img_v if img_v is Image else null
	var img := Image.new()
	var err: Error = img.load(path)
	if err != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _index_walk(root: String, index: Dictionary) -> void:
	var da := DirAccess.open(root)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var full: String = root.path_join(fn)
		if da.current_is_dir():
			_index_walk(full, index)
		else:
			var key: String = fn.to_lower()
			if not index.has(key):
				index[key] = full
		fn = da.get_next()
	da.list_dir_end()


static func _read_latin1(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var parts := PackedStringArray()
	parts.resize(bytes.size())
	for i in bytes.size():
		parts[i] = String.chr(int(bytes[i]))
	return "".join(parts)


static func _split_ws(s: String) -> PackedStringArray:
	var norm: String = s.strip_edges()
	while norm.contains("\t"):
		norm = norm.replace("\t", " ")
	while norm.contains("  "):
		norm = norm.replace("  ", " ")
	if norm.is_empty():
		return PackedStringArray()
	return norm.split(" ", false)


static func _strip_quotes(s: String) -> String:
	var out: String = s
	while out.begins_with("\"") or out.begins_with("'"):
		out = out.substr(1)
	while out.ends_with("\"") or out.ends_with("'"):
		out = out.substr(0, out.length() - 1)
	return out


static func _splitlines(text: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var start: int = i
		while i < n:
			var ch: int = text.unicode_at(i)
			if ch == 0x0A or ch == 0x0D:
				break
			i += 1
		lines.append(text.substr(start, i - start))
		if i >= n:
			break
		if text.unicode_at(i) == 0x0D and i + 1 < n and text.unicode_at(i + 1) == 0x0A:
			i += 2
		else:
			i += 1
	return lines


static func _seq_empty(v: Variant) -> bool:
	if v == null:
		return true
	if v is Array:
		return (v as Array).is_empty()
	if v is PackedVector3Array:
		return (v as PackedVector3Array).is_empty()
	if v is PackedVector2Array:
		return (v as PackedVector2Array).is_empty()
	if v is PackedInt32Array:
		return (v as PackedInt32Array).is_empty()
	if v is PackedFloat32Array:
		return (v as PackedFloat32Array).is_empty()
	return false


static func _filled_vec3(like: Variant, value: Vector3) -> Array:
	var n: int = 0
	if like is Array:
		n = (like as Array).size()
	elif like is PackedVector3Array:
		n = (like as PackedVector3Array).size()
	var out: Array = []
	for _i in n:
		out.append(value)
	return out


static func _filled_vec2(like: Variant, value: Vector2) -> Array:
	var n: int = 0
	if like is Array:
		n = (like as Array).size()
	elif like is PackedVector3Array:
		n = (like as PackedVector3Array).size()
	elif like is PackedVector2Array:
		n = (like as PackedVector2Array).size()
	var out: Array = []
	for _i in n:
		out.append(value)
	return out


static func _err_message(result: Dictionary, fallback: String) -> String:
	var err: Variant = result.get("error", {})
	if typeof(err) == TYPE_DICTIONARY:
		var msg: Variant = (err as Dictionary).get("message", "")
		if msg != null and str(msg) != "":
			return str(msg)
	return fallback


static func _abspath(path: String) -> String:
	if path.is_absolute_path():
		return path.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return path.simplify_path()
	return cwd.get_current_dir().path_join(path).simplify_path()
