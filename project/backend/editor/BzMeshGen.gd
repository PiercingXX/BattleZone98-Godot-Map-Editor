extends RefCounted
class_name BzMeshGen
## Per-map static meshes: water surfaces and plant fields.
##
## Port of ``bzmap.generate.meshgen`` (see git history / meshgen.py.ref).
## Emits an OGRE ``.mesh`` via ``BzMeshData.write_mesh``, a paired
## ``.material``, and an ``.odf`` with ``classLabel = i76building2``.
## Vertices are world metres, transposed (x<->z) so a corpus -90-degree
## carrier at the origin lands the geometry in world space.

const CELL_M: float = 5.0

# Oasis-style water: additive blue, double-sided, depth-write off, scrolling
# thecavew.png. Copied from the Python template (corpus desrten1.material).
const _WATER_MATERIAL := """\
import * from \"BZBase.material\"

// The exact water pass of the two shipped maps whose water is known
// good (Oasis desrten1.material / The Cave thecave_water): blue additive
// wash over the scrolling ripple texture. depth_write OFF makes the pool
// see-through; fog_override keeps distant water from going neon pink.
// Colours match Oasis (0.25 0.60 1) verbatim.
material {name}
{
\ttechnique
\t{
\t\tpass
\t\t{
\t\t\tambient 0.25 0.60 1
\t\t\tdiffuse 0.25 0.60 1
\t\t\tscene_blend add
\t\t\tcull_hardware none
\t\t\tcull_software none
\t\t\tdepth_write off
\t\t\tfog_override true
\t\t\ttexture_unit
\t\t\t{
\t\t\t\ttexture thecavew.png
\t\t\t\tscroll_anim {scroll_u} {scroll_v}
\t\t\t}
\t\t}
\t}
}
"""

# Alpha-tested plant billboards, from the corpus bomadenv.material (EoPlnt01).
const _PLANT_MATERIAL := """\
import * from \"BZBase.material\"

material {name}
{
\ttechnique
\t{
\t\tpass
\t\t{
\t\t\tscene_blend alpha_blend
\t\t\talpha_rejection greater_equal 128
\t\t\tcull_hardware none
\t\t\tcull_software none
\t\t\ttexture_unit
\t\t\t{
\t\t\t\ttexture EoPlnt01_D.dds
\t\t\t}
\t\t}
\t}
}
"""

# Static-geometry ODF: same class the corpus maps use for water/scenery meshes.
const _STATIC_ODF := """\
[GameObjectClass] // generated static geometry
classLabel = "i76building2"
scrapCost = 0
scrapValue = 0
maxHealth = 99999999
maxAmmo = 0
unitName = "{unit}"
heatSignature = 0
imageSignature = 0
radarSignature = 0
"""


static func validate_feature_stems(entries: Array, map_stem: String) -> Dictionary:
	## Stems must be 1..8 alphanumeric chars and must not collide with the map stem.
	var seen := {}
	var map_l: String = map_stem.to_lower()
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var stem: String = str(entry.get("stem", "")).strip_edges()
		if stem.is_empty() or not _stem_alnum_ok(stem):
			return BzErrors.err(
				"bad_stem",
				"feature stem %s is empty or not alphanumeric" % _py_repr(stem)
			)
		if stem.length() > 8:
			return BzErrors.err(
				"stem_too_long",
				"feature stem %s is %d characters; the engine truncates script lookups above 8"
				% [_py_repr(stem), stem.length()],
				"use a stem of 8 characters or fewer"
			)
		if stem.to_lower() == map_l:
			return BzErrors.err(
				"stem_collision",
				"feature stem %s collides with the map stem" % _py_repr(stem),
				"use a different feature stem"
			)
		var key: String = stem.to_lower()
		if seen.has(key):
			return BzErrors.err(
				"stem_collision",
				"duplicate feature stem %s" % _py_repr(stem),
				"each water/plant feature needs its own stem"
			)
		seen[key] = true
	return {"ok": true}


static func collect_entries(features: Dictionary) -> Array:
	## Flatten features.json water/plants into ``{kind, stem, ...}`` records.
	var out: Array = []
	var waters: Variant = features.get("water", [])
	if typeof(waters) == TYPE_ARRAY:
		for w in waters:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			if bool((w as Dictionary).get("legacy", false)):
				# Pre-existing carrier detected on open (e.g. desrten1):
				# its mesh and BZN object already ship with the map.
				# Regenerating would clobber the original files and break
				# byte-identical round-trips.
				continue
			var rec: Dictionary = (w as Dictionary).duplicate()
			rec["kind"] = "water"
			out.append(rec)
	var plants: Variant = features.get("plants", [])
	if typeof(plants) == TYPE_ARRAY:
		for p in plants:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var rec_p: Dictionary = (p as Dictionary).duplicate()
			rec_p["kind"] = "plants"
			out.append(rec_p)
	return out


static func generate_features(
	session_dir: String,
	out_dir: String,
	map_stem: String,
	heightmap: BzHg2.HeightMap,
	features: Dictionary
) -> Dictionary:
	## Emit ``<stem>.mesh`` / ``.material`` / ``.odf`` for every water/plant entry.
	var entries: Array = collect_entries(features)
	var chk: Dictionary = validate_feature_stems(entries, map_stem)
	if BzErrors.is_err(chk):
		return chk
	if entries.is_empty():
		return {"ok": true, "generated": [], "files": [], "warnings": []}
	if heightmap == null:
		return BzErrors.err(
			"no_heightmap",
			"cannot generate feature meshes without a heightmap"
		)
	var water_level: Variant = null
	for e in entries:
		if str((e as Dictionary).get("kind", "")) == "water":
			water_level = float((e as Dictionary).get("level_m", 0.0))
			break
	var generated: Array = []
	var files: Array = []
	var warnings: Array = []
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z
	for e_v in entries:
		var entry: Dictionary = e_v
		var stem: String = str(entry.get("stem", "")).strip_edges()
		var kind: String = str(entry.get("kind", ""))
		var mask_rel: String = str(entry.get("mask", "")).strip_edges()
		var mask := PackedByteArray()
		if not mask_rel.is_empty():
			var mask_path: String = mask_rel
			if not mask_path.is_absolute_path():
				mask_path = session_dir.path_join(mask_rel)
			var loaded: Dictionary = _read_mask(mask_path, gx, gz)
			if BzErrors.is_err(loaded):
				warnings.append(
					"%s: skipped (%s)" % [stem, str((loaded.get("error", {}) as Dictionary).get("message", "bad mask"))]
				)
				continue
			mask = loaded.get("mask", PackedByteArray())
		var built: Dictionary
		if kind == "water":
			var level: float = float(entry.get("level_m", -1.0))
			if level < 0.0:
				warnings.append("%s: skipped (level_m < 0)" % stem)
				continue
			built = build_water_surface(
				out_dir, stem, heightmap, level, "water", 10.0, 1.0, mask,
				float(entry.get("current_deg", 90.0)),
				float(entry.get("current_speed", 0.04))
			)
		elif kind == "plants":
			var density: int = int(round(float(entry.get("density", 260))))
			var seed: int = int(entry.get("seed", 0))
			built = build_plant_field(
				out_dir, stem, heightmap, seed, density, "plants",
				0.0, 12.0, [], 140.0, 4.0, 2.2, water_level, mask
			)
		else:
			continue
		if BzErrors.is_err(built):
			return built
		if not bool(built.get("written", false)):
			warnings.append("%s: no geometry (nothing to emit)" % stem)
			continue
		generated.append({
			"stem": stem,
			"kind": kind,
			"variant_scope": str(entry.get("variant_scope", "all")),
		})
		for ext in [".mesh", ".material", ".odf"]:
			files.append("%s%s" % [stem, ext])
	return {
		"ok": true,
		"generated": generated,
		"files": files,
		"warnings": warnings,
	}


static func build_water_surface(
	out_dir: String,
	stem: String,
	heightmap: BzHg2.HeightMap,
	water_level_m: float,
	material: String = "water",
	tile_m: float = 10.0,
	margin_below_m: float = 1.0,
	region_mask: PackedByteArray = PackedByteArray(),
	current_deg: float = 90.0,
	current_speed: float = 0.04
) -> Dictionary:
	## Horizontal quadgrid at ``water_level_m``, clipped to underwater (and mask) cells.
	if heightmap == null:
		return BzErrors.err("value_error", "build_water_surface: no heightmap")
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z
	if gx < 2 or gz < 2:
		return {"ok": true, "written": false, "stem": ""}
	var mask_err: Dictionary = _check_mask(region_mask, gx, gz)
	if BzErrors.is_err(mask_err):
		return mask_err
	var heights: PackedFloat64Array = _heights_m(heightmap)
	var step: int = maxi(1, int(round(tile_m / CELL_M)))
	var verts: Array = []
	var norms: Array = []
	var uvs: Array = []
	var tris: Array = []
	var vindex := {}

	var iz: int = 0
	while iz < gz - step:
		var ix: int = 0
		while ix < gx - step:
			if (
				_underwater(iz, ix, heights, gx, gz, region_mask, water_level_m, margin_below_m)
				or _underwater(iz, ix + step, heights, gx, gz, region_mask, water_level_m, margin_below_m)
				or _underwater(iz + step, ix, heights, gx, gz, region_mask, water_level_m, margin_below_m)
				or _underwater(iz + step, ix + step, heights, gx, gz, region_mask, water_level_m, margin_below_m)
			):
				var a: int = _water_vert(ix, iz, water_level_m, verts, norms, uvs, vindex)
				var b: int = _water_vert(ix + step, iz, water_level_m, verts, norms, uvs, vindex)
				var c: int = _water_vert(ix, iz + step, water_level_m, verts, norms, uvs, vindex)
				var d: int = _water_vert(ix + step, iz + step, water_level_m, verts, norms, uvs, vindex)
				tris.append(a)
				tris.append(c)
				tris.append(b)
				tris.append(b)
				tris.append(c)
				tris.append(d)
			ix += step
		iz += step

	if tris.is_empty():
		return {"ok": true, "written": false, "stem": ""}
	# Visible current: the scrolling ripple's direction. UVs are world-
	# aligned (u tracks +x, v tracks +z), so a compass-style angle maps
	# straight onto scroll_anim. 90 deg / 0.04 reproduces the Oasis pass.
	var mat_template := _WATER_MATERIAL.replace(
		"{scroll_u}", "%.4f" % (cos(deg_to_rad(current_deg)) * current_speed)
	).replace(
		"{scroll_v}", "%.4f" % (sin(deg_to_rad(current_deg)) * current_speed)
	)
	return _emit_mesh_set(
		out_dir, stem, material, "%s water" % stem, mat_template, verts, norms, uvs, tris
	)


static func build_plant_field(
	out_dir: String,
	stem: String,
	heightmap: BzHg2.HeightMap,
	seed: int,
	count: int = 260,
	material: String = "plants",
	min_slope_deg: float = 0.0,
	max_slope_deg: float = 12.0,
	avoid: Array = [],
	avoid_radius_m: float = 140.0,
	blade_h_m: float = 4.0,
	blade_w_m: float = 2.2,
	water_level_m: Variant = null,
	region_mask: PackedByteArray = PackedByteArray()
) -> Dictionary:
	## ``count`` crossed alpha billboards on gentle dry ground (deterministic in ``seed``).
	if heightmap == null:
		return BzErrors.err("value_error", "build_plant_field: no heightmap")
	if count <= 0:
		return {"ok": true, "written": false, "stem": ""}
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z
	if gx < 2 or gz < 2:
		return {"ok": true, "written": false, "stem": ""}
	var mask_err: Dictionary = _check_mask(region_mask, gx, gz)
	if BzErrors.is_err(mask_err):
		return mask_err
	var heights: PackedFloat64Array = _heights_m(heightmap)
	var slope_deg: PackedFloat64Array = _slope_deg(heightmap)
	var domain: Dictionary = _sample_domain(gx, gz, region_mask)
	if not bool(domain.get("ok", false)):
		return {"ok": true, "written": false, "stem": ""}

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts: Array = []
	var norms: Array = []
	var uvs: Array = []
	var tris: Array = []
	var placed: int = 0
	var attempts: int = 0
	var max_attempts: int = count * 40
	var avoid_r2: float = avoid_radius_m * avoid_radius_m
	var wx_lo: float = float(domain["wx_lo"])
	var wx_hi: float = float(domain["wx_hi"])
	var wz_lo: float = float(domain["wz_lo"])
	var wz_hi: float = float(domain["wz_hi"])
	var wet: bool = water_level_m != null
	var water_m: float = float(water_level_m) if wet else 0.0

	while placed < count and attempts < max_attempts:
		attempts += 1
		var wx: float = rng.randf_range(wx_lo, wx_hi)
		var wz: float = rng.randf_range(wz_lo, wz_hi)
		if not region_mask.is_empty():
			var mx: int = clampi(int(wx / CELL_M), 0, gx - 1)
			var mz: int = clampi(int(wz / CELL_M), 0, gz - 1)
			if region_mask[mz * gx + mx] == 0:
				continue
		var sample: Dictionary = _sample_h(wx, wz, heights, slope_deg, gx, gz)
		var h: float = float(sample["h"])
		var s: float = float(sample["s"])
		if s < min_slope_deg or s > max_slope_deg:
			continue
		if wet and h < water_m:
			continue
		# Sink the billboard base so the opaque part of the texture roots at
		# ground level and slope-float is hidden (Python meshgen).
		h -= 2.5
		var blocked := false
		for av in avoid:
			var ax := 0.0
			var az := 0.0
			if av is Vector2:
				ax = (av as Vector2).x
				az = (av as Vector2).y
			elif av is Array and (av as Array).size() >= 2:
				ax = float(av[0])
				az = float(av[1])
			else:
				continue
			var dx: float = wx - ax
			var dz: float = wz - az
			if dx * dx + dz * dz < avoid_r2:
				blocked = true
				break
		if blocked:
			continue
		placed += 1
		var yaw: float = rng.randf_range(0.0, PI)
		var hh: float = blade_h_m * rng.randf_range(0.7, 1.3)
		var hw: float = blade_w_m * 0.5 * rng.randf_range(0.7, 1.3)
		for a_off in [0.0, PI * 0.5]:
			var a: float = yaw + a_off
			var bdx: float = cos(a) * hw
			var bdz: float = sin(a) * hw
			var base: int = verts.size()
			# (x, y, z, u, v) — two-triangle cross-billboard.
			var quad: Array = [
				[wx - bdx, h, wz - bdz, 0.0, 1.0],
				[wx + bdx, h, wz + bdz, 1.0, 1.0],
				[wx - bdx, h + hh, wz - bdz, 0.0, 0.0],
				[wx + bdx, h + hh, wz + bdz, 1.0, 0.0],
			]
			for q in quad:
				verts.append([float(q[0]), float(q[1]), float(q[2])])
				norms.append([0.0, 0.0, 1.0])
				uvs.append([float(q[3]), float(q[4])])
			tris.append(base)
			tris.append(base + 2)
			tris.append(base + 1)
			tris.append(base + 1)
			tris.append(base + 2)
			tris.append(base + 3)
		if verts.size() > 64000:
			break

	if tris.is_empty():
		return {"ok": true, "written": false, "stem": ""}
	return _emit_mesh_set(
		out_dir, stem, material, "%s plants" % stem, _PLANT_MATERIAL, verts, norms, uvs, tris
	)


static func _emit_mesh_set(
	out_dir: String,
	stem: String,
	material: String,
	unit: String,
	template: String,
	verts: Array,
	norms: Array,
	uvs: Array,
	tris: Array
) -> Dictionary:
	if not DirAccess.dir_exists_absolute(out_dir):
		var mk: Error = DirAccess.make_dir_recursive_absolute(out_dir)
		if mk != OK and not DirAccess.dir_exists_absolute(out_dir):
			return BzErrors.err(
				"write_failed",
				"cannot create out dir: %s" % out_dir,
				"",
				out_dir
			)
	var wr_m: Dictionary = _write_material(out_dir.path_join("%s.material" % stem), template, material)
	if BzErrors.is_err(wr_m):
		return wr_m
	var wr_o: Dictionary = _write_static_odf(out_dir.path_join("%s.odf" % stem), unit)
	if BzErrors.is_err(wr_o):
		return wr_o
	# Mesh-local vertices are the TRANSPOSE of world coordinates (x<->z):
	# the engine applies the carrier object's transform basis and then
	# NEGATES Z (a handedness flip no pure-rotation basis can cancel,
	# det -1). Shipped maps pair a -90-degree carrier basis with
	# transposed vertices: local (wz, y, wx) lands at world (wx, wz).
	var local: Array = []
	local.resize(verts.size())
	for i in verts.size():
		var v: Array = verts[i]
		local[i] = [float(v[2]), float(v[1]), float(v[0])]
	var mesh_path: String = out_dir.path_join("%s.mesh" % stem)
	var wrote: String = BzMeshData.write_mesh(mesh_path, local, norms, uvs, tris, material)
	if wrote.is_empty():
		return BzErrors.err(
			"write_failed",
			"BzMeshData.write_mesh failed for %s" % mesh_path,
			"",
			mesh_path
		)
	return {"ok": true, "written": true, "stem": stem}


static func _write_material(path: String, template: String, name: String) -> Dictionary:
	# OGRE material files are ASCII. A stray non-ASCII char in a comment
	# (an em-dash slipping into a template) used to crash the map build;
	# degrade it to '?' rather than abort (Python meshgen).
	var text: String = template.replace("{name}", name)
	return _write_text_crlf(path, text)


static func _write_static_odf(path: String, unit: String) -> Dictionary:
	var text: String = _STATIC_ODF.replace("{unit}", unit)
	return _write_text_crlf(path, text)


static func _write_text_crlf(path: String, text: String) -> Dictionary:
	text = _ascii_replace(text)
	text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
	if not text.ends_with("\r\n"):
		text += "\r\n"
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return BzErrors.err(
			"write_failed",
			"cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())],
			"",
			path
		)
	f.store_buffer(text.to_utf8_buffer())
	f.close()
	return {"ok": true}


static func _ascii_replace(text: String) -> String:
	var out := ""
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c < 128:
			out += String.chr(c)
		else:
			out += "?"
	return out


static func _heights_m(heightmap: BzHg2.HeightMap) -> PackedFloat64Array:
	var raw: PackedInt32Array = heightmap.data
	var out := PackedFloat64Array()
	out.resize(raw.size())
	for i in raw.size():
		out[i] = float(raw[i]) * BzHg2.HEIGHT_SCALE
	return out


static func _slope_deg(heightmap: BzHg2.HeightMap) -> PackedFloat64Array:
	## numpy.degrees(arctan(hypot(gxf, gyf))) — BzHg2.slope is the hypot.
	var rise: PackedFloat64Array = BzHg2.slope(heightmap)
	var out := PackedFloat64Array()
	out.resize(rise.size())
	for i in rise.size():
		out[i] = rad_to_deg(atan(rise[i]))
	return out


static func _underwater(
	iz: int,
	ix: int,
	heights: PackedFloat64Array,
	gx: int,
	gz: int,
	region_mask: PackedByteArray,
	water_level_m: float,
	margin_below_m: float
) -> bool:
	var z: int = mini(iz, gz - 1)
	var x: int = mini(ix, gx - 1)
	if not region_mask.is_empty() and region_mask[z * gx + x] == 0:
		return false
	return heights[z * gx + x] < water_level_m - margin_below_m


static func _water_vert(
	ix: int,
	iz: int,
	water_level_m: float,
	verts: Array,
	norms: Array,
	uvs: Array,
	vindex: Dictionary
) -> int:
	var key := Vector2i(ix, iz)
	if vindex.has(key):
		return int(vindex[key])
	var wx: float = float(ix) * CELL_M
	var wz: float = float(iz) * CELL_M
	var v: int = verts.size()
	verts.append([wx, water_level_m, wz])
	norms.append([0.0, 1.0, 0.0])
	uvs.append([wx / 64.0, wz / 64.0])
	vindex[key] = v
	return v


static func _sample_h(
	wx: float,
	wz: float,
	heights: PackedFloat64Array,
	slope_deg: PackedFloat64Array,
	gx: int,
	gz: int
) -> Dictionary:
	# Bilinear height — nearest-cell sampling floated billboards over the
	# engine's smoothly-interpolated terrain (Python meshgen).
	var fx: float = wx / CELL_M
	var fz: float = wz / CELL_M
	var ix: int = int(fx)
	var iz: int = int(fz)
	var ix1: int = mini(ix + 1, gx - 1)
	var iz1: int = mini(iz + 1, gz - 1)
	ix = clampi(ix, 0, gx - 1)
	iz = clampi(iz, 0, gz - 1)
	var tx: float = fx - float(int(fx))
	var tz: float = fz - float(int(fz))
	var h0: float = heights[iz * gx + ix] * (1.0 - tx) + heights[iz * gx + ix1] * tx
	var h1: float = heights[iz1 * gx + ix] * (1.0 - tx) + heights[iz1 * gx + ix1] * tx
	var h: float = h0 * (1.0 - tz) + h1 * tz
	var si: int = mini(iz, gz - 1) * gx + mini(ix, gx - 1)
	return {"h": h, "s": slope_deg[si]}


static func _sample_domain(gx: int, gz: int, region_mask: PackedByteArray) -> Dictionary:
	## World-metre [lo, hi] for plant sampling. Full-map matches Python
	## ``uniform(60, (g-1)*cell - 60)``; a mask shrinks to its bbox.
	var map_lo: float = 60.0
	var map_hi_x: float = float(gx - 1) * CELL_M - 60.0
	var map_hi_z: float = float(gz - 1) * CELL_M - 60.0
	if map_hi_x <= map_lo or map_hi_z <= map_lo:
		return {"ok": false}
	var wx_lo: float = map_lo
	var wx_hi: float = map_hi_x
	var wz_lo: float = map_lo
	var wz_hi: float = map_hi_z
	if not region_mask.is_empty():
		var min_x: int = gx
		var max_x: int = -1
		var min_z: int = gz
		var max_z: int = -1
		for z in gz:
			var row: int = z * gx
			for x in gx:
				if region_mask[row + x] != 0:
					if x < min_x:
						min_x = x
					if x > max_x:
						max_x = x
					if z < min_z:
						min_z = z
					if z > max_z:
						max_z = z
		if max_x < min_x:
			return {"ok": false}
		wx_lo = float(min_x) * CELL_M
		wx_hi = float(max_x) * CELL_M
		wz_lo = float(min_z) * CELL_M
		wz_hi = float(max_z) * CELL_M
		if wx_hi <= wx_lo:
			wx_hi = wx_lo + CELL_M
		if wz_hi <= wz_lo:
			wz_hi = wz_lo + CELL_M
		# Apply the 60 m map-edge margin only when the bbox is large enough
		# that it would not invert (full-map mask then matches Python).
		if wx_hi - wx_lo > 120.0:
			wx_lo = maxf(wx_lo, map_lo)
			wx_hi = minf(wx_hi, map_hi_x)
		if wz_hi - wz_lo > 120.0:
			wz_lo = maxf(wz_lo, map_lo)
			wz_hi = minf(wz_hi, map_hi_z)
		if wx_hi <= wx_lo or wz_hi <= wz_lo:
			return {"ok": false}
	return {
		"ok": true,
		"wx_lo": wx_lo,
		"wx_hi": wx_hi,
		"wz_lo": wz_lo,
		"wz_hi": wz_hi,
	}


static func _read_mask(path: String, gx: int, gz: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var expected: int = gx * gz
	if raw.size() != expected:
		return BzErrors.err(
			"mask_size_mismatch",
			"mask %s has %d samples, expected %d (%dx%d)"
			% [path.get_file(), raw.size(), expected, gz, gx],
			"",
			path
		)
	return {"ok": true, "mask": raw}


static func _check_mask(region_mask: PackedByteArray, gx: int, gz: int) -> Dictionary:
	if region_mask.is_empty():
		return {"ok": true}
	if region_mask.size() != gx * gz:
		return BzErrors.err(
			"mask_size_mismatch",
			"region_mask has %d samples, expected %d" % [region_mask.size(), gx * gz]
		)
	return {"ok": true}


static func _stem_alnum_ok(stem: String) -> bool:
	if stem.is_empty():
		return false
	for i in stem.length():
		var c: int = stem.unicode_at(i)
		var is_az: bool = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		var is_d: bool = c >= 48 and c <= 57
		if not is_az and not is_d:
			return false
	return true


static func _py_repr(s: String) -> String:
	return "'%s'" % s.replace("\\", "\\\\").replace("'", "\\'")
