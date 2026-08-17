extends SceneTree
## Regenerates the starter templates in templates/ from vendored reference
## data only — no game install needed, nothing game-derived is written.
## Each template is a complete base-game map file set. The editor treats
## templates/ as read-only; this script is the one sanctioned writer.
##
## Usage: godot --headless --path . -s res://scripts/make_templates.gd

const BASE_RAW := 1000  # 100 m


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var specs := [
		{
			"dir": "crater-arena",
			"stem": "xtcrater",
			"size": 1280,
			"height": Callable(self, "_crater"),
		},
		{
			"dir": "valley-2team",
			"stem": "xtvalley",
			"size": 2560,
			"height": Callable(self, "_valley"),
		},
		{
			"dir": "highlands-4team",
			"stem": "xthiland",
			"size": 2560,
			"height": Callable(self, "_highlands"),
		},
	]
	var root := ProjectSettings.globalize_path("res://templates").simplify_path()
	var failures := 0
	for spec in specs:
		if not _make(root, spec):
			failures += 1
	quit(1 if failures > 0 else 0)


func _make(root: String, spec: Dictionary) -> bool:
	var out_dir: String = root.path_join(str(spec["dir"]))
	var session := OS.get_temp_dir().path_join("bz-template-%s" % spec["stem"])
	if DirAccess.dir_exists_absolute(session):
		OS.move_to_trash(session)
	var size: int = int(spec["size"])
	var created: Dictionary = BzNew.create_map(
		str(spec["stem"]), "elysium", size, size, session, "", BASE_RAW, "base"
	)
	if not created.get("ok", false):
		printerr("%s: create_map failed: %s" % [spec["dir"], created.get("error")])
		return false

	var grid: int = size / 5
	var heights := PackedInt32Array()
	heights.resize(grid * grid)
	var fn: Callable = spec["height"]
	for z in grid:
		for x in grid:
			var u := float(x) / float(grid - 1)
			var v := float(z) / float(grid - 1)
			var dm: float = fn.call(u, v)
			heights[z * grid + x] = clampi(BASE_RAW + int(round(dm * 10.0)), 1, 4095)
	var bytes := PackedByteArray()
	bytes.resize(heights.size() * 2)
	for i in heights.size():
		bytes.encode_u16(i * 2, heights[i])
	var f := FileAccess.open(session.path_join("terrain.r16"), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var dirty_v: Variant = BzSession.read_json(session.path_join("dirty.json"))
	var dirty: Dictionary = dirty_v if typeof(dirty_v) == TYPE_DICTIONARY else {}
	dirty["terrain"] = true
	BzSession.write_json(session.path_join("dirty.json"), dirty)

	var saved: Dictionary = BzSave.save_session(session, out_dir)
	if not saved.get("ok", false):
		printerr("%s: save failed: %s" % [spec["dir"], saved.get("error")])
		return false
	print("%s: %d files" % [spec["dir"], (saved.get("files", []) as Array).size()])
	return true


## Height offsets in metres relative to the base plane; u/v in 0..1.


func _crater(u: float, v: float) -> float:
	var d := Vector2(u - 0.5, v - 0.5).length() * 2.0  # 0 centre → 1 edge
	var rim := 80.0 * exp(-pow((d - 0.62) / 0.10, 2.0))
	var bowl := -25.0 * smoothstep(0.55, 0.15, d)
	return rim + bowl


func _valley(u: float, v: float) -> float:
	var from_mid := absf(u - 0.5) * 2.0  # 0 valley centre → 1 map edge
	var ridge := 100.0 * smoothstep(0.45, 0.85, from_mid)
	var roll := 6.0 * sin(v * TAU * 3.0) * smoothstep(0.3, 0.6, from_mid)
	return ridge + roll


func _highlands(u: float, v: float) -> float:
	var h := 0.0
	for cx in [0.2, 0.8]:
		for cz in [0.2, 0.8]:
			var d := Vector2(u - cx, v - cz).length()
			h = maxf(h, 60.0 * smoothstep(0.24, 0.10, d))
	return h
