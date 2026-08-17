extends Control
## Editor shell: sculpt, place, validate, package.

const SculptToolScript = preload("res://project/sculpt/SculptTool.gd")
const ObjectCommandScript = preload("res://project/commands/ObjectCommand.gd")
const TerrainRaycastScript = preload("res://project/terrain/TerrainRaycast.gd")

@onready var _status: Label = %Status
@onready var _console: TextEdit = %Console
@onready var _probe_list: ItemList = %ProbeList
@onready var _map_label: Label = %MapLabel
@onready var _btn_probe: Button = %BtnProbe
@onready var _btn_open: Button = %BtnOpen
@onready var _btn_new: Button = %BtnNew
@onready var _btn_save: Button = %BtnSave
@onready var _btn_validate: Button = %BtnValidate
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _new_dialog: ConfirmationDialog = %NewDialog
@onready var _stem_edit: LineEdit = %StemEdit
@onready var _world_option: OptionButton = %WorldOption
@onready var _size_option: OptionButton = %SizeOption
@onready var _terrain: Node3D = %Terrain
@onready var _objects: Node3D = %Objects
@onready var _camera: Camera3D = %Camera
@onready var _center: Control = %Center
@onready var _viewport: SubViewport = %SubViewport

var _tool: String = "fly"
var _sculpt = SculptToolScript.new()
var _stroking: bool = false
var _armed: Dictionary = {}
var _palette: ItemList
var _search: LineEdit
var _findings: ItemList
var _inspector: TextEdit
var _variant: OptionButton
var _tool_bar: HBoxContainer
var _radius: HSlider
var _strength: HSlider
var _debug: Label
var _cursor: Label
var _meta: TextEdit
var _water: SpinBox
var _pack_kind: OptionButton
var _size_z: OptionButton
var _help: Window
var _pending_package: String = ""
var _autosave: Timer
var _ramp_a: Vector3 = Vector3.INF
var _last_stamp: Vector3 = Vector3.INF
var _filter: String = ""


func _ready() -> void:
	randomize()
	add_to_group("editor_shell")
	_build_chrome()
	Backend.discovered.connect(_on_discovered)
	Backend.call_started.connect(_on_call_started)
	Backend.stderr_line.connect(_on_stderr)
	Backend.call_finished.connect(_on_call_finished)
	Backend.call_failed.connect(_on_call_failed)
	MapState.session_changed.connect(_on_session_changed)
	MapState.objects_mutated.connect(_on_objects_mutated)
	MapState.materials_changed.connect(_on_materials_changed)
	UndoStack.changed.connect(_refresh_status)
	if _camera.has_signal("speed_changed"):
		_camera.speed_changed.connect(_on_speed_changed)
	_autosave = Timer.new()
	_autosave.wait_time = 30.0
	_autosave.timeout.connect(_on_autosave)
	add_child(_autosave)
	_autosave.start()
	_refresh_map_label()
	_log("BattleZone 98 Godot Map Editor. F1 help. Open a map to sculpt and place.")
	if Backend.available:
		_log(Backend.bzmap_home)
		Backend.probe()
		_queue_smoke_open()
	else:
		_status.text = "backend missing"
		_log(Backend.last_error)


func _build_chrome() -> void:
	var body := $Root/Body
	_tool_bar = HBoxContainer.new()
	_tool_bar.add_theme_constant_override("separation", 6)
	$Root/TopBar/TopInner.add_child(_tool_bar)
	$Root/TopBar/TopInner.move_child(_tool_bar, 1)
	for spec in [
		["fly", "Fly"], ["raise", "Raise"], ["lower", "Lower"],
		["flatten", "Flatten"], ["smooth", "Smooth"], ["ramp", "Ramp"],
		["noise", "Noise"], ["paint", "Paint"], ["place", "Place"],
		["select", "Select"],
	]:
		var b := Button.new()
		b.text = spec[1]
		b.toggle_mode = true
		b.button_pressed = spec[0] == "fly"
		b.pressed.connect(_set_tool.bind(spec[0]))
		_tool_bar.add_child(b)
	_variant = OptionButton.new()
	_variant.item_selected.connect(func(_i): _on_variant_changed())
	_tool_bar.add_child(_variant)
	var undo_b := Button.new()
	undo_b.text = "Undo"
	undo_b.pressed.connect(func(): UndoStack.undo())
	_tool_bar.add_child(undo_b)
	var redo_b := Button.new()
	redo_b.text = "Redo"
	redo_b.pressed.connect(func(): UndoStack.redo())
	_tool_bar.add_child(redo_b)
	var assets_b := Button.new()
	assets_b.text = "Import assets"
	assets_b.pressed.connect(_import_assets)
	_tool_bar.add_child(assets_b)
	var thumb_b := Button.new()
	thumb_b.text = "Thumbnail"
	thumb_b.pressed.connect(_render_thumb)
	_tool_bar.add_child(thumb_b)
	var inst_b := Button.new()
	inst_b.text = "Install to test mod"
	inst_b.pressed.connect(_install_mod)
	_tool_bar.add_child(inst_b)
	var pack_b := Button.new()
	pack_b.text = "Assemble pack"
	pack_b.pressed.connect(_assemble_pack)
	_tool_bar.add_child(pack_b)

	var left: VBoxContainer = $Root/Body/Left
	_search = LineEdit.new()
	_search.placeholder_text = "Search classes…"
	_search.text_changed.connect(func(t): _filter = t; _fill_palette())
	left.add_child(_search)
	left.move_child(_search, 0)
	_palette = ItemList.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.item_selected.connect(_on_palette_selected)
	left.add_child(_palette)

	var sliders := VBoxContainer.new()
	var rl := Label.new()
	rl.text = "Radius m"
	sliders.add_child(rl)
	_radius = HSlider.new()
	_radius.min_value = 5
	_radius.max_value = 400
	_radius.value = 40
	_radius.value_changed.connect(func(v): _sculpt.radius_m = v)
	sliders.add_child(_radius)
	var sl := Label.new()
	sl.text = "Strength"
	sliders.add_child(sl)
	_strength = HSlider.new()
	_strength.min_value = 0.05
	_strength.max_value = 1.0
	_strength.step = 0.05
	_strength.value = 0.45
	_strength.value_changed.connect(func(v): _sculpt.strength = v)
	sliders.add_child(_strength)
	left.add_child(sliders)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(280, 0)
	right.add_theme_constant_override("separation", 6)
	var il := Label.new()
	il.text = "Inspector"
	right.add_child(il)
	_inspector = TextEdit.new()
	_inspector.custom_minimum_size = Vector2(0, 140)
	_inspector.placeholder_text = "No selection"
	right.add_child(_inspector)
	var apply_b := Button.new()
	apply_b.text = "Apply inspector"
	apply_b.pressed.connect(_apply_inspector)
	right.add_child(apply_b)
	var ml := Label.new()
	ml.text = "Metadata (raw)"
	right.add_child(ml)
	_meta = TextEdit.new()
	_meta.custom_minimum_size = Vector2(0, 120)
	right.add_child(_meta)
	var mw := Button.new()
	mw.text = "Write metadata"
	mw.pressed.connect(_write_meta)
	right.add_child(mw)
	var wl := Label.new()
	wl.text = "Waterline (m, -1 off)"
	right.add_child(wl)
	_water = SpinBox.new()
	_water.min_value = -1
	_water.max_value = 820
	_water.step = 0.5
	_water.value = -1
	_water.value_changed.connect(func(v): _terrain.set_water_level(v))
	right.add_child(_water)
	var fl := Label.new()
	fl.text = "Findings  (click to fly)"
	right.add_child(fl)
	_findings = ItemList.new()
	_findings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_findings.item_selected.connect(_on_finding_selected)
	right.add_child(_findings)
	body.add_child(right)

	_cursor = Label.new()
	_cursor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Root/TopBar/TopInner.add_child(_cursor)
	_debug = Label.new()
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	$Root/TopBar/TopInner.add_child(_debug)

	_pack_kind = OptionButton.new()
	_pack_kind.add_item("BZP map", 0)
	_pack_kind.add_item("Base-game map", 1)
	_new_dialog.get_node("NewBox").add_child(_pack_kind)
	var zl := Label.new()
	zl.text = "Depth"
	_new_dialog.get_node("NewBox").add_child(zl)
	_size_z = OptionButton.new()
	for size in [1280, 2560, 3840, 5120]:
		_size_z.add_item("%s m" % size, size)
	_new_dialog.get_node("NewBox").add_child(_size_z)

	_help = Window.new()
	_help.title = "Hotkeys"
	_help.size = Vector2i(480, 360)
	_help.visible = false
	_help.close_requested.connect(func(): _help.hide())
	var help_l := Label.new()
	help_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_l.text = """WASD fly  Q/E up down  RMB look  Shift fast  Ctrl slow
Wheel speed  F frame  Space top-down  H slope  G material grid
1–8 tools  [ ] radius  Ctrl+[ ] strength  Esc disarm
Ctrl+Z undo  Ctrl+Shift+Z redo  Ctrl+S save  F1 this help
LMB sculpt / place / select    Shift+click keep placing
Walk-the-surface: Settings.walk_mode (Alt toggles)"""
	help_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help.add_child(help_l)
	add_child(_help)


func _process(_delta: float) -> void:
	_debug.text = "%d fps  chunks %d  up %d B" % [
		int(Engine.get_frames_per_second()),
		_terrain.get_child_count() if _terrain else 0,
		_sculpt.last_uploaded,
	]
	if not MapState.has_session:
		return
	if not _over_viewport():
		_terrain.set_brush(false, Vector2.ZERO, 0.0, 0.0, false)
		return
	var hit := _pick()
	if hit.get("hit", false):
		var p: Vector3 = hit["position"]
		_cursor.text = "xz %.1f, %.1f  h %.1f m  mat %d  %s" % [
			p.x, p.z, p.y, MapState.material_at(p.x, p.z), _tool,
		]
		if _tool in ["raise", "lower", "flatten", "smooth", "ramp", "noise", "undefined", "paint"]:
			_terrain.set_brush(true, Vector2(p.x, p.z), _sculpt.radius_m, _sculpt.falloff, _sculpt.shape == "square")
		else:
			_terrain.set_brush(false, Vector2.ZERO, 0.0, 0.0, false)
		if _tool == "place" and not _armed.is_empty():
			var ghost := _armed.duplicate()
			ghost["x"] = p.x
			ghost["z"] = p.z
			ghost["y"] = p.y
			_objects.set_ghost(true, ghost, MapState.field, hit.get("normal", Vector3.UP))
	if _stroking and hit.get("hit", false) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var p2: Vector3 = hit["position"]
		if _last_stamp.distance_to(p2) >= maxf(HeightField.CELL_M, _sculpt.radius_m * 0.15):
			_sculpt.stamp(MapState.field, p2.x, p2.z)
			_last_stamp = p2


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F1:
			_help.popup_centered()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_G:
			_terrain.set_show_grid(not _terrain.get_child_count() == 0)
			if _terrain.has_method("set_show_grid"):
				_terrain.set_show_grid(true)
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_DELETE:
			_delete_selected()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			_armed = {}
			_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
			_set_tool("fly")
		elif k.ctrl_pressed and k.keycode == KEY_Z:
			if k.shift_pressed:
				UndoStack.redo()
			else:
				UndoStack.undo()
			get_viewport().set_input_as_handled()
		elif k.ctrl_pressed and k.keycode == KEY_S:
			_on_btn_save_pressed()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ALT:
			Settings.walk_mode = not Settings.walk_mode
			Settings.save()
			_log("walk mode %s" % Settings.walk_mode)
		elif k.keycode == KEY_BRACKETLEFT:
			if k.shift_pressed:
				_strength.value = maxf(0.05, _strength.value - 0.05)
			else:
				_radius.value = maxf(5, _radius.value - 5)
		elif k.keycode == KEY_BRACKETRIGHT:
			if k.shift_pressed:
				_strength.value = minf(1.0, _strength.value + 0.05)
			else:
				_radius.value = minf(400, _radius.value + 5)
		elif k.keycode >= KEY_1 and k.keycode <= KEY_8:
			var tools := ["fly", "raise", "lower", "flatten", "smooth", "ramp", "paint", "place"]
			_set_tool(tools[k.keycode - KEY_1])
	if event is InputEventMouseButton and _over_viewport():
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var hit := _pick()
		if not hit.get("hit", false):
			return
		var p: Vector3 = hit["position"]
		if mb.pressed:
			_on_lmb_down(p, hit, mb.shift_pressed)
		else:
			_on_lmb_up()
		get_viewport().set_input_as_handled()


func _on_lmb_down(p: Vector3, hit: Dictionary, shift: bool) -> void:
	if _tool == "select":
		var id: String = _objects.pick(_camera.project_ray_origin(_viewport.get_mouse_position()), _camera.project_ray_normal(_viewport.get_mouse_position()))
		if id.is_empty():
			MapState.selected_ids.clear()
		else:
			if shift:
				if id in MapState.selected_ids:
					MapState.selected_ids.erase(id)
				else:
					MapState.selected_ids.append(id)
			else:
				MapState.selected_ids = [id] as Array[String]
		_objects.highlight(MapState.selected_ids)
		_fill_inspector()
		return
	if _tool == "place" and not _armed.is_empty():
		_place_at(p, hit.get("normal", Vector3.UP), shift)
		return
	if _tool == "ramp":
		if _ramp_a.x > 1.0e8:
			_ramp_a = p
			_log("ramp start %.1f, %.1f  h %.1f" % [p.x, p.z, p.y])
		else:
			_apply_ramp(_ramp_a, p)
			_ramp_a = Vector3.INF
		return
	if _tool in ["raise", "lower", "flatten", "smooth", "noise", "undefined", "paint"]:
		_sculpt.mode = _tool
		_sculpt.radius_m = _radius.value
		_sculpt.strength = _strength.value
		_sculpt.begin_stroke(MapState.field, p.x, p.z, _tool == "paint")
		_stroking = true
		_last_stamp = p


func _on_lmb_up() -> void:
	if not _stroking:
		return
	_stroking = false
	if _tool == "paint":
		var paint_cmd = _sculpt.end_paint()
		if paint_cmd:
			UndoStack.push(paint_cmd)
	else:
		var cmd2 = _sculpt.end_stroke(MapState.field)
		if cmd2:
			# begin_stroke already applied; push without re-doing.
			cmd2.do = Callable() # not used
			UndoStack.push(_wrap_already_done(cmd2))
	_on_objects_mutated()


func _wrap_already_done(cmd: RefCounted) -> RefCounted:
	# UndoStack.push calls do(). The stroke is already on the field.
	# Push a thin wrapper whose do() is a no-op the first time.
	var w := _OnceCommand.new()
	w.inner = cmd
	return w


class _OnceCommand:
	extends RefCounted
	var inner: RefCounted
	var applied := true
	func do() -> void:
		if applied:
			applied = false
			return
		if inner and inner.has_method("do"):
			inner.call("do")
	func undo() -> void:
		if inner and inner.has_method("undo"):
			inner.call("undo")


func _place_at(p: Vector3, normal: Vector3, keep: bool) -> void:
	var info: Dictionary = _armed
	var prjid := str(info.get("prjid", ""))
	if prjid.to_lower() == "player" and MapState.player_in_variant(MapState.active_variant):
		_log("player already placed in this variant")
		return
	var rec := {
		"id": MapState.alloc_id(),
		"origin": "new",
		"prjid": prjid,
		"x": p.x,
		"y": p.y,
		"z": p.z,
		"yaw_deg": rad_to_deg(atan2(normal.x, normal.z)) if str(info.get("up_convention", "upright")) == "follow" else 0.0,
		"team": _default_team(prjid, info),
		"label": "%s%s" % [prjid, MapState.next_new_id],
		"up_convention": "upright",
		"pinned_y": false,
		"managed": false,
		"required": prjid.to_lower() == "player",
		"template_verified": bool(info.get("template_verified", false)),
		"placement_mode": str(info.get("placement_mode", "runtime")),
	}
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.ADD
	cmd.variant = MapState.active_variant
	cmd.object_id = rec["id"]
	cmd.after = rec
	UndoStack.push(cmd)
	if not keep:
		_armed = {}
		_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
	_log("placed %s at %.1f, %.1f (%s)" % [prjid, p.x, p.z, rec["placement_mode"]])


func _delete_selected() -> void:
	for id in MapState.selected_ids.duplicate():
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		if bool(rec.get("required", false)):
			_log("player object is undeletable")
			continue
		var cmd = ObjectCommandScript.new()
		cmd.kind = ObjectCommandScript.Kind.DELETE
		cmd.variant = MapState.find_object_variant(id)
		cmd.object_id = id
		cmd.before = rec.duplicate(true)
		UndoStack.push(cmd)
	MapState.selected_ids.clear()
	_on_objects_mutated()


func _default_team(prjid: String, info: Dictionary) -> int:
	var p := prjid.to_lower()
	var cat := str(info.get("category", ""))
	if p == "player":
		return 1
	if cat in ["scrap", "geyser", "spawn", "environment"] or p == "pspwn_1":
		return 0
	return 0


func _apply_ramp(a: Vector3, b: Vector3) -> void:
	var field = MapState.field
	var delta := b - a
	var length := Vector2(delta.x, delta.z).length()
	if length < 1.0:
		return
	var dir := Vector2(delta.x, delta.z) / length
	var cell := HeightField.CELL_M
	var _r: float = _sculpt.radius_m
	var steps := int(ceil(length / cell)) + 1
	_sculpt.mode = "flatten"
	_sculpt.begin_stroke(field, a.x, a.z, false)
	for i in steps:
		var t := float(i) / float(max(steps - 1, 1))
		var h := lerpf(a.y, b.y, t)
		_sculpt.flatten_target = int(round(h / HeightField.HEIGHT_SCALE))
		var c := a + Vector3(dir.x, 0, dir.y) * (t * length)
		_sculpt.stamp(field, c.x, c.z)
	var cmd = _sculpt.end_stroke(field)
	if cmd:
		UndoStack.push(_wrap_already_done(cmd))
	var slope_deg := rad_to_deg(atan2(absf(b.y - a.y), length))
	_log("ramp %.0f m  slope %.1f°  (30° is the climb limit)" % [length, slope_deg])


func _set_tool(name: String) -> void:
	_tool = name
	_sculpt.mode = name
	if _tool_bar:
		for child in _tool_bar.get_children():
			if child is Button and child.toggle_mode:
				child.button_pressed = child.text.to_lower() == name or (
					name == "fly" and child.text == "Fly"
				)
	if name != "place":
		_armed = {}
		_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
	_terrain.set_show_grid(name == "paint")
	_refresh_status()


func _over_viewport() -> bool:
	return _center.get_global_rect().has_point(get_global_mouse_position())


func _pick() -> Dictionary:
	if not MapState.has_session:
		return {"hit": false}
	var mouse := _viewport.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	return TerrainRaycastScript.intersect(origin, dir, MapState.field)


func _on_discovered(ok: bool, detail: String) -> void:
	_log(detail)
	_status.text = "backend ready" if ok else "backend missing"


func _on_call_started(verb: String) -> void:
	_status.text = "bzmap editor %s…" % verb
	_set_busy(true)


func _on_stderr(line: String) -> void:
	_log(line)


func _on_call_finished(verb: String, result: Dictionary) -> void:
	_set_busy(false)
	_status.text = "ok: %s" % verb
	match verb:
		"probe":
			_fill_probe(result)
			if not _smoke_path.is_empty():
				var path := _smoke_path
				_smoke_path = ""
				Backend.open_map(path, MapState.new_session_dir())
			elif not Settings.game_root.is_empty() and not FileAccess.file_exists(MapState.cache_dir().path_join("index.json")):
				_log("first run: importing asset index (proxies + icons)…")
				Backend.assets(Settings.game_root, MapState.cache_dir(), false)
		"worlds":
			MapState.worlds = result.get("worlds", [])
			_fill_worlds(result)
		"open", "new":
			MapState.load_from_open(result)
			for w in result.get("warnings", []):
				_log("warning: %s" % w)
			if _is_smoke():
				get_tree().quit(0)
		"save":
			MapState.unsaved = false
			var ident: Array = result.get("byte_identical", [])
			var regen: Array = result.get("regenerated", [])
			_log("byte-identical: %s" % ", ".join(PackedStringArray(ident)))
			if not regen.is_empty():
				_log("regenerated: %s" % ", ".join(PackedStringArray(regen)))
			for w2 in result.get("warnings", []):
				_log("warning: %s" % w2)
		"validate":
			MapState.findings = result.get("findings", [])
			MapState.findings_stale = false
			_fill_findings()
			_log("%d findings (not an in-game verdict)" % MapState.findings.size())
		"assets":
			MapState.asset_index = result
			Settings.last_cache_fingerprint = str(result.get("source_fingerprint", ""))
			Settings.save()
			_fill_palette()
			_log("%d classes  %d unresolved  fidelity mostly proxy" % [
				result.get("classes", []).size(), result.get("unresolved", []).size(),
			])
		"render":
			_log("thumbnail %s" % result.get("png", ""))
		"package":
			_log("package %s → %s" % [result.get("mode", ""), result.get("dest", "")])


func _on_call_failed(verb: String, error: Dictionary) -> void:
	_set_busy(false)
	_status.text = "error: %s" % verb
	_log("ERROR [%s] %s" % [error.get("code", "?"), error.get("message", error)])
	if error.has("hint"):
		_log("  hint: %s" % error["hint"])
	if _is_smoke() and verb != "probe":
		get_tree().quit(1)


func _is_smoke() -> bool:
	return OS.get_cmdline_user_args().has("--smoke-open")


func _fill_probe(result: Dictionary) -> void:
	_probe_list.clear()
	var installs: Array = result.get("installs", [])
	for item in installs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var kind := str(item.get("kind", ""))
		var path := str(item.get("path", ""))
		var extra := ""
		if kind == "workshop_item":
			extra = "  [%s %s]" % [item.get("id", ""), item.get("source", "")]
			if str(item.get("id", "")) == "3406347034" and Settings.last_map_dir.is_empty():
				Settings.last_map_dir = path
				Settings.save()
		_probe_list.add_item("%s  %s%s" % [kind, path, extra])
	for warning in result.get("warnings", []):
		_probe_list.add_item("warning: %s" % warning)
	if not Settings.game_root.is_empty() and not _is_smoke():
		Backend.worlds(Settings.game_root)
		var idx := MapState.cache_dir().path_join("index.json")
		if FileAccess.file_exists(idx):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx))
			if typeof(parsed) == TYPE_DICTIONARY:
				MapState.asset_index = parsed
				_fill_palette()


func _fill_worlds(result: Dictionary) -> void:
	_world_option.clear()
	for world in result.get("worlds", []):
		if typeof(world) != TYPE_DICTIONARY:
			continue
		_world_option.add_item("%s" % world.get("label", world.get("id", "")))
		_world_option.set_item_metadata(_world_option.item_count - 1, world.get("id", ""))


func _fill_palette() -> void:
	if _palette == null:
		return
	_palette.clear()
	var classes: Array = MapState.asset_index.get("classes", [])
	var pack: Dictionary = MapState.manifest.get("pack_context", {})
	var kind := str(pack.get("kind", "bzp"))
	var q := _filter.to_lower()
	for rec in classes:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var prjid := str(rec.get("prjid", ""))
		var label := str(rec.get("label", prjid))
		if q != "" and q not in prjid.to_lower() and q not in label.to_lower():
			continue
		var source := str(rec.get("source", "game"))
		var legal := source == "game" or kind == "bzp"
		var mode := str(rec.get("placement_mode", "runtime"))
		var text := "%s  [%s]  %s" % [prjid, rec.get("category", ""), mode]
		if not legal:
			text += "  (other pack — unavailable)"
		var i := _palette.add_item(text)
		_palette.set_item_metadata(i, rec)
		_palette.set_item_disabled(i, not legal)
	_palette.sort_items_by_text()


func _on_palette_selected(index: int) -> void:
	var rec = _palette.get_item_metadata(index)
	if typeof(rec) != TYPE_DICTIONARY:
		return
	if _palette.is_item_disabled(index):
		_log("class is outside this map's pack context")
		return
	_armed = rec
	_set_tool("place")
	_log("armed %s  %s  %s" % [rec.get("prjid"), rec.get("placement_mode"), rec.get("mesh_fidelity")])


func _fill_findings() -> void:
	if _findings == null:
		return
	_findings.clear()
	var prefix := "(stale) " if MapState.findings_stale else ""
	for f in MapState.findings:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var i := _findings.add_item("%s%s  %s" % [prefix, f.get("severity", ""), f.get("title", "")])
		_findings.set_item_metadata(i, f)


func _on_finding_selected(index: int) -> void:
	var f = _findings.get_item_metadata(index)
	if typeof(f) != TYPE_DICTIONARY:
		return
	var pos = f.get("world_pos", null)
	if typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
		_camera.global_position = Vector3(float(pos[0]), float(pos[1]) + 40.0, float(pos[2]) - 40.0)
		_camera.look_at(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), Vector3.UP)
	var oid := str(f.get("object_id", ""))
	if not oid.is_empty():
		MapState.selected_ids = [oid] as Array[String]
		_objects.highlight(MapState.selected_ids)


func _fill_inspector() -> void:
	if _inspector == null:
		return
	if MapState.selected_ids.is_empty():
		_inspector.text = ""
		return
	var rec := MapState.find_object(MapState.selected_ids[0])
	_inspector.text = JSON.stringify(rec, "  ")


func _apply_inspector() -> void:
	if MapState.selected_ids.is_empty():
		return
	var parsed: Variant = JSON.parse_string(_inspector.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("inspector JSON did not parse")
		return
	var id := MapState.selected_ids[0]
	var before := MapState.find_object(id).duplicate(true)
	if bool(before.get("required", false)) and parsed.get("id", id) != id:
		_log("player object cannot be re-id'd")
		return
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.EDIT
	cmd.variant = MapState.find_object_variant(id)
	cmd.object_id = id
	cmd.before = before
	cmd.after = parsed
	UndoStack.push(cmd)
	_on_objects_mutated()


func _write_meta() -> void:
	var parsed: Variant = JSON.parse_string(_meta.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("metadata JSON did not parse")
		return
	MapState.meta = parsed
	if not MapState.dirty.has("meta"):
		MapState.dirty["meta"] = []
	MapState.dirty["meta"] = ["raw"]
	MapState.unsaved = true
	MapState.persist()
	_log("metadata marked dirty")


func _on_session_changed() -> void:
	_refresh_map_label()
	_fill_variants()
	_fill_palette()
	if _meta:
		_meta.text = JSON.stringify(MapState.meta, "  ")
	if not MapState.has_session:
		return
	if _terrain.has_method("rebuild"):
		_terrain.rebuild(MapState.field)
	_on_objects_mutated()
	camera_frame()
	_terrain.refresh_materials()


func _on_objects_mutated() -> void:
	if _objects.has_method("rebuild"):
		_objects.rebuild(MapState.objects, MapState.field)
	_objects.highlight(MapState.selected_ids)
	_fill_inspector()
	_refresh_status()


func _on_materials_changed() -> void:
	if _terrain.has_method("refresh_materials"):
		_terrain.refresh_materials()


func _fill_variants() -> void:
	if _variant == null:
		return
	_variant.clear()
	var vars: Array = MapState.manifest.get("variants", [""])
	for v in vars:
		var label := "DM" if str(v) == "" else str(v)
		_variant.add_item(label)
		_variant.set_item_metadata(_variant.item_count - 1, v)
		if str(v) == MapState.active_variant:
			_variant.select(_variant.item_count - 1)


func _on_variant_changed() -> void:
	if _variant.selected < 0:
		return
	MapState.active_variant = str(_variant.get_item_metadata(_variant.selected))
	_on_objects_mutated()


func _refresh_map_label() -> void:
	if not MapState.has_session:
		_map_label.text = "no map open"
		return
	var star := "*" if MapState.unsaved else ""
	_map_label.text = "%s%s  %sx%s  %s" % [
		MapState.stem, star, MapState.width_m, MapState.depth_m, MapState.world
	]


func _refresh_status() -> void:
	_refresh_map_label()
	if MapState.ceiling_hit:
		_status.text = "hit raw 4095 ceiling"


func camera_frame() -> void:
	if not MapState.has_session or MapState.field.grid_x < 2:
		return
	var mid_h: float = MapState.field.height_at(float(MapState.width_m) * 0.5, float(MapState.depth_m) * 0.5)
	_camera.frame_map(float(MapState.width_m), float(MapState.depth_m), mid_h)


func camera_overview() -> void:
	if not MapState.has_session:
		return
	_camera.top_down(float(MapState.width_m), float(MapState.depth_m))


func toggle_slope() -> void:
	if _terrain.has_method("set_slope_overlay"):
		_terrain._show_slope = not _terrain._show_slope
		_terrain.set_slope_overlay(_terrain._show_slope)
		_log("slope overlay %s" % ("on" if _terrain._show_slope else "off"))


func _on_speed_changed(mps: float) -> void:
	if not Backend.busy:
		_status.text = "cam %.0f m/s" % mps


func _set_busy(value: bool) -> void:
	_btn_probe.disabled = value
	_btn_open.disabled = value
	_btn_new.disabled = value
	_btn_save.disabled = value
	_btn_validate.disabled = value


func _log(text: String) -> void:
	if _console.text.is_empty():
		_console.text = text
	else:
		_console.text += "\n" + text
	_console.scroll_vertical = _console.get_line_count()


var _smoke_path: String = ""


func _queue_smoke_open() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--smoke-open" and i + 1 < args.size():
			_smoke_path = args[i + 1]
			return


func _on_autosave() -> void:
	if MapState.has_session and MapState.unsaved:
		MapState.persist()
		_log("autosaved session")


func _import_assets() -> void:
	if Settings.game_root.is_empty():
		_log("probe an install first")
		return
	Backend.assets(Settings.game_root, MapState.cache_dir(), true)


func _render_thumb() -> void:
	if not MapState.has_session:
		return
	MapState.persist()
	Backend.render_map(MapState.session_dir, MapState.session_dir.path_join("thumbs"))


func _install_mod() -> void:
	if not MapState.has_session:
		return
	if Settings.game_root.is_empty():
		_log("no game root")
		return
	MapState.persist()
	Backend.package_install(MapState.session_dir, Settings.game_root)


func _assemble_pack() -> void:
	if not MapState.has_session:
		return
	_pending_package = "pack"
	_save_dialog.title = "Assemble pack into…"
	_save_dialog.popup_centered_ratio(0.5)


func _on_btn_probe_pressed() -> void:
	Backend.probe()


func _on_btn_open_pressed() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	if not Settings.last_map_dir.is_empty():
		_file_dialog.current_dir = Settings.last_map_dir
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_dialog_file_selected(path: String) -> void:
	Settings.last_map_dir = path.get_base_dir()
	Settings.save()
	Backend.open_map(path, MapState.new_session_dir())


func _on_btn_new_pressed() -> void:
	if _world_option.item_count == 0 and not Settings.game_root.is_empty():
		Backend.worlds(Settings.game_root)
	if _size_option.item_count == 0:
		for size in [1280, 2560, 3840, 5120]:
			_size_option.add_item("%s m" % size, size)
	if _size_z.item_count == 0:
		for size in [1280, 2560, 3840, 5120]:
			_size_z.add_item("%s m" % size, size)
	_new_dialog.popup_centered()


func _on_new_dialog_confirmed() -> void:
	var stem := _stem_edit.text.strip_edges()
	if stem.is_empty() or stem.length() > 8:
		_log("stem must be 1–8 characters (engine truncates scripts above 8)")
		return
	var world := "mars"
	if _world_option.selected >= 0:
		var meta = _world_option.get_item_metadata(_world_option.selected)
		if meta != null:
			world = str(meta)
	var w := 1280
	var d := 1280
	if _size_option.selected >= 0:
		w = _size_option.get_item_id(_size_option.selected)
		if w <= 0:
			w = 1280
	if _size_z.selected >= 0:
		d = _size_z.get_item_id(_size_z.selected)
		if d <= 0:
			d = w
	var kind := "bzp" if _pack_kind.selected == 0 else "base"
	Backend.new_map(stem, world, w, d, MapState.new_session_dir(), Settings.game_root, kind)
	_log("new %s %sx%s %s" % [stem, w, d, kind])


func _on_btn_save_pressed() -> void:
	if not MapState.has_session:
		_log("nothing to save")
		return
	_pending_package = "save"
	_save_dialog.title = "Save map to directory"
	_save_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_save_dialog.popup_centered_ratio(0.5)


func _on_save_dialog_dir_selected(dir: String) -> void:
	MapState.persist()
	if _pending_package == "pack":
		Backend.package_pack(MapState.session_dir, dir)
	else:
		Backend.save_map(MapState.session_dir, dir, MapState.stem)
	_pending_package = ""


func _on_btn_validate_pressed() -> void:
	if not MapState.has_session:
		_log("nothing to validate")
		return
	MapState.persist()
	Backend.validate(MapState.session_dir, Settings.game_root)
