extends RefCounted
class_name BzReport
## Per-candidate validation report (port of validate/report.py).
##
## `preview()` uses a Godot `Image` instead of PIL `render_preview` (BzRender
## is a different agent's file; this keeps the report self-contained).

const DEFAULT_PREVIEW_SIZE := Vector2i(512, 512)


var heightmap: BzHg2.HeightMap = null
var layout: BzLayout = null
var spawns: Variant = null
var structural_problems: PackedStringArray = PackedStringArray()
var seed: Variant = null
var preview_size: Vector2i = DEFAULT_PREVIEW_SIZE

var terrain: BzCheckTerrain = null
var connectivity: BzCheckConnectivity = null
var balance: BzCheckBalance = null


func _init(
	p_heightmap: Variant = null,
	p_layout: BzLayout = null,
	p_spawns: Variant = null,
	p_structural_problems: Variant = null,
	p_seed: Variant = null,
	p_preview_size: Variant = null
) -> void:
	heightmap = BzCheckTerrain._coerce_heightmap(p_heightmap)
	layout = p_layout
	spawns = p_spawns
	if p_structural_problems != null:
		for p in p_structural_problems:
			structural_problems.append(str(p))
	seed = p_seed
	preview_size = _as_size(p_preview_size)
	terrain = BzCheckTerrain.new(heightmap)
	connectivity = BzCheckConnectivity.new(heightmap, layout)
	balance = BzCheckBalance.new(heightmap, layout, spawns)


func measured() -> Dictionary:
	return {
		"terrain": terrain.measure(),
		"connectivity": connectivity.measure(),
		"balance": balance.measure(),
	}


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(structural_problems)
	out.append_array(terrain.validate())
	out.append_array(connectivity.validate())
	out.append_array(balance.validate())
	return out


func _problems_by_severity() -> Dictionary:
	var grouped := {"error": [], "warning": [], "info": []}
	for p in problems():
		var sev: String = _severity(str(p))
		var list: Array = grouped[sev]
		list.append(str(p))
		grouped[sev] = list
	return grouped


func to_dict() -> Dictionary:
	var by_severity: Dictionary = _problems_by_severity()
	var gx := 0
	var gz := 0
	var width := 0.0
	var depth := 0.0
	if heightmap != null:
		gx = heightmap.grid_x
		gz = heightmap.grid_z
		width = heightmap.width_m
		depth = heightmap.depth_m
	return {
		"seed": seed,
		"width_m": width,
		"depth_m": depth,
		"grid": [gx, gz],
		"measured": measured(),
		"problems": {
			"error": by_severity["error"],
			"warning": by_severity["warning"],
			"info": by_severity["info"],
		},
		"verdict": "pass" if (by_severity["error"] as Array).is_empty() else "fail",
	}


func preview() -> Image:
	## Top-down shaded height with layout nodes. Returns a Godot Image.
	var w: int = preview_size.x
	var h: int = preview_size.y
	var img := Image.create_empty(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGB8)
	img.fill(Color(0.08, 0.09, 0.10))
	if heightmap == null:
		return img
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z
	if gx < 1 or gz < 1:
		return img
	var lo := 0x7fffffff
	var hi := 0
	for i in heightmap.data.size():
		var v: int = heightmap.data[i]
		if v < lo:
			lo = v
		if v > hi:
			hi = v
	var span: float = float(maxi(1, hi - lo))
	for py in h:
		# North-up: +z is the top of the image (docs/02).
		var z: int = int(float(gz - 1) * (1.0 - float(py) / float(maxi(1, h - 1))))
		z = clampi(z, 0, gz - 1)
		for px in w:
			var x: int = int(float(gx - 1) * float(px) / float(maxi(1, w - 1)))
			x = clampi(x, 0, gx - 1)
			var raw: int = heightmap.data[z * gx + x]
			var t: float = float(raw - lo) / span
			img.set_pixel(px, py, Color(t * 0.55 + 0.12, t * 0.48 + 0.10, t * 0.32 + 0.08))
	if layout != null:
		for nid in layout.nodes().keys():
			var n: BzLayout.LayoutNode = layout.nodes()[nid]
			if (
				n.kind == BzLayout.BASE
				or n.kind == BzLayout.GEYSER
				or n.kind == BzLayout.SCRAP
				or n.kind == BzLayout.SPAWN
			):
				_plot(img, n.x, n.z, _node_color(n.kind))
	return img


func write(out_dir: String) -> String:
	## Write `report.json` and `preview.png` into `out_dir`. Returns JSON path.
	DirAccess.make_dir_recursive_absolute(out_dir)
	var json_path: String = out_dir.path_join("report.json")
	var text: String = _dumps_sorted(to_dict())
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	var img: Image = preview()
	img.save_png(out_dir.path_join("preview.png"))
	return json_path


static func write_report(
	out_dir: String,
	heightmap: Variant,
	layout: BzLayout,
	spawns: Variant = null,
	structural_problems: Variant = null,
	seed: Variant = null,
	p_preview_size: Variant = null
) -> String:
	var report := BzReport.new(
		heightmap, layout, spawns, structural_problems, seed, p_preview_size
	)
	return report.write(out_dir)


static func _severity(problem: String) -> String:
	if problem.begins_with("[error]"):
		return "error"
	if problem.begins_with("[warning]"):
		return "warning"
	return "info"


static func _as_size(v: Variant) -> Vector2i:
	if v == null:
		return DEFAULT_PREVIEW_SIZE
	if v is Vector2i:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return DEFAULT_PREVIEW_SIZE


func _plot(img: Image, x_m: float, z_m: float, color: Color) -> void:
	if heightmap == null or heightmap.width_m <= 0.0 or heightmap.depth_m <= 0.0:
		return
	var px: int = int(round((x_m / heightmap.width_m) * float(img.get_width() - 1)))
	var py: int = int(round((1.0 - z_m / heightmap.depth_m) * float(img.get_height() - 1)))
	px = clampi(px, 0, img.get_width() - 1)
	py = clampi(py, 0, img.get_height() - 1)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = px + dx
			var y: int = py + dy
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				img.set_pixel(x, y, color)


static func _node_color(kind: String) -> Color:
	match kind:
		BzLayout.BASE:
			return Color(0.95, 0.85, 0.20)
		BzLayout.GEYSER:
			return Color(0.25, 0.85, 0.95)
		BzLayout.SCRAP:
			return Color(0.85, 0.45, 0.20)
		_:
			return Color(0.90, 0.90, 0.95)


static func _dumps_sorted(value: Variant) -> String:
	## `json.dumps(..., indent=2, sort_keys=True)` + trailing newline.
	return JSON.stringify(_sort_value(value), "  ") + "\n"


static func _sort_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		var keys: Array = d.keys()
		keys.sort()
		var out := {}
		for k in keys:
			out[k] = _sort_value(d[k])
		return out
	if typeof(value) == TYPE_ARRAY:
		var out: Array = []
		for item in value:
			out.append(_sort_value(item))
		return out
	if value is PackedStringArray:
		var out: Array = []
		for item in value:
			out.append(str(item))
		return out
	return value
