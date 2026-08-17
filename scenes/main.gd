extends Control
## Editor shell: sculpt, place, validate, package.

const SculptToolScript = preload("res://project/sculpt/SculptTool.gd")
const ObjectCommandScript = preload("res://project/commands/ObjectCommand.gd")
const TerrainRaycastScript = preload("res://project/terrain/TerrainRaycast.gd")
const DarkThemeScript = preload("res://project/ui/DarkTheme.gd")

@onready var _console: TextEdit = %Console
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _new_dialog: ConfirmationDialog = %NewDialog
@onready var _stem_edit: LineEdit = %StemEdit
@onready var _world_option: OptionButton = %WorldOption
@onready var _size_option: OptionButton = %SizeOption
@onready var _size_z: OptionButton = %SizeZ
@onready var _pack_kind: OptionButton = %PackKind
@onready var _terrain: Node3D = %Terrain
@onready var _objects: Node3D = %Objects
@onready var _camera: Camera3D = %Camera
@onready var _center: Control = %Center
@onready var _viewport: SubViewport = %SubViewport

var _status: Label
var _map_label: Label
var _btn_open: Button
var _btn_new: Button
var _btn_save: Button
var _btn_validate: Button
var _btn_probe: Button
var _probe_list: ItemList
var _tool: String = "fly"
var _sculpt = SculptToolScript.new()
var _stroking: bool = false
var _armed: Dictionary = {}
var _palette: ItemList
var _search: LineEdit
var _findings: ItemList
var _variant: OptionButton
var _tool_bar: HBoxContainer
var _tool_buttons: Dictionary = {}
var _radius: HSlider
var _strength: HSlider
var _radius_val: Label
var _strength_val: Label
var _debug: Label
var _cursor: Label
var _water: SpinBox
var _help: Window
var _pending_package: String = ""
var _autosave: Timer
var _ramp_a: Vector3 = Vector3.INF
var _last_stamp: Vector3 = Vector3.INF
var _filter: String = ""
var _insp_prj: LineEdit
var _insp_x: SpinBox
var _insp_y: SpinBox
var _insp_z: SpinBox
var _insp_yaw: SpinBox
var _insp_team: SpinBox
var _insp_label: LineEdit
var _insp_mode: Label
var _busy_targets: Array = []


func _ready() -> void:
	randomize()
	theme = DarkThemeScript.make()
	add_to_group("editor_shell")
	_build_chrome()
	_try_load_asset_index()
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
	var top: HBoxContainer = %TopInner
	var brand := Label.new()
	brand.text = "BZ98"
	top.add_child(brand)
	_map_label = Label.new()
	_map_label.text = "no map"
	top.add_child(_map_label)
	top.add_child(_vsep())
	_btn_open = _bar_btn("Open", _on_btn_open_pressed)
	_btn_new = _bar_btn("New", _on_btn_new_pressed)
	_btn_save = _bar_btn("Save", _on_btn_save_pressed)
	_btn_validate = _bar_btn("Validate", _on_btn_validate_pressed)
	top.add_child(_btn_open)
	top.add_child(_btn_new)
	top.add_child(_btn_save)
	top.add_child(_btn_validate)
	var more := MenuButton.new()
	more.text = "More"
	var pop := more.get_popup()
	pop.add_item("Import assets", 0)
	pop.add_item("Render thumbnail", 1)
	pop.add_item("Install to test mod", 2)
	pop.add_item("Assemble pack", 3)
	pop.add_separator()
	pop.add_item("Re-probe install", 4)
	pop.add_item("Hotkeys  F1", 5)
	pop.id_pressed.connect(_on_more)
	top.add_child(more)
	top.add_child(_vsep())
	_tool_bar = HBoxContainer.new()
	_tool_bar.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for spec in [
		["fly", "Fly", "1"], ["raise", "Raise", "2"], ["lower", "Lower", "3"],
		["flatten", "Flat", "4"], ["smooth", "Smooth", "5"], ["ramp", "Ramp", "6"],
		["paint", "Paint", "7"], ["place", "Place", "8"], ["select", "Select", ""],
		["noise", "Noise", ""],
	]:
		var b := Button.new()
		b.text = spec[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = spec[0] == "fly"
		b.tooltip_text = spec[1] if spec[2] == "" else "%s  (%s)" % [spec[1], spec[2]]
		b.pressed.connect(_set_tool.bind(spec[0]))
		_tool_bar.add_child(b)
		_tool_buttons[spec[0]] = b
	top.add_child(_tool_bar)
	top.add_child(_vsep())
	_variant = OptionButton.new()
	_variant.tooltip_text = "Active variant"
	_variant.item_selected.connect(func(_i): _on_variant_changed())
	top.add_child(_variant)
	var undo_b := _bar_btn("Undo", func(): UndoStack.undo())
	var redo_b := _bar_btn("Redo", func(): UndoStack.redo())
	top.add_child(undo_b)
	top.add_child(redo_b)
	top.add_child(_bar_btn("Frame", func(): camera_frame()))
	%Center.gui_input.connect(_on_view_gui_input)
	%Center.mouse_filter = Control.MOUSE_FILTER_STOP

	var left: VBoxContainer = %LeftBox
	left.add_child(_section("Palette"))
	_search = LineEdit.new()
	_search.placeholder_text = "Search units…"
	_search.text_changed.connect(func(t): _filter = t; _fill_palette())
	left.add_child(_search)
	_palette = ItemList.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.item_selected.connect(_on_palette_selected)
	left.add_child(_palette)
	left.add_child(_section("Brush"))
	var rr := HBoxContainer.new()
	var rl := Label.new()
	rl.text = "Radius"
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radius_val = Label.new()
	_radius_val.text = "40 m"
	rr.add_child(rl)
	rr.add_child(_radius_val)
	left.add_child(rr)
	_radius = HSlider.new()
	_radius.min_value = 5
	_radius.max_value = 400
	_radius.value = 40
	_radius.value_changed.connect(func(v):
		_sculpt.radius_m = v
		_radius_val.text = "%d m" % int(v)
	)
	left.add_child(_radius)
	var sr := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Strength"
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strength_val = Label.new()
	_strength_val.text = "45%"
	sr.add_child(sl)
	sr.add_child(_strength_val)
	left.add_child(sr)
	_strength = HSlider.new()
	_strength.min_value = 0.05
	_strength.max_value = 1.0
	_strength.step = 0.05
	_strength.value = 0.45
	_strength.value_changed.connect(func(v):
		_sculpt.strength = v
		_strength_val.text = "%d%%" % int(v * 100.0)
	)
	left.add_child(_strength)

	var right: VBoxContainer = %RightBox
	right.add_child(_section("Object"))
	_insp_prj = _ro_field("class")
	_insp_label = LineEdit.new()
	_insp_label.placeholder_text = "label"
	_insp_x = _spin("x m", -20000, 20000, 0.1)
	_insp_y = _spin("y m", -50, 900, 0.1)
	_insp_z = _spin("z m", -20000, 20000, 0.1)
	_insp_yaw = _spin("yaw °", -180, 180, 1)
	_insp_team = _spin("team", 0, 15, 1)
	_insp_mode = Label.new()
	for n in [_insp_prj, _insp_label, _insp_x, _insp_y, _insp_z, _insp_yaw, _insp_team, _insp_mode]:
		right.add_child(n)
	var irow := HBoxContainer.new()
	var apply_b := Button.new()
	apply_b.text = "Apply"
	apply_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_b.pressed.connect(_apply_inspector)
	var del_b := Button.new()
	del_b.text = "Delete"
	del_b.pressed.connect(_delete_selected)
	irow.add_child(apply_b)
	irow.add_child(del_b)
	right.add_child(irow)
	right.add_child(_section("Water"))
	_water = SpinBox.new()
	_water.min_value = -1
	_water.max_value = 820
	_water.step = 0.5
	_water.value = -1
	_water.prefix = "line "
	_water.suffix = "m"
	_water.value_changed.connect(func(v): _terrain.set_water_level(v))
	right.add_child(_water)
	right.add_child(_section("Findings"))
	_findings = ItemList.new()
	_findings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_findings.item_selected.connect(_on_finding_selected)
	right.add_child(_findings)

	var status: HBoxContainer = %StatusInner
	_cursor = Label.new()
	_cursor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cursor.text = "Open a map to begin"
	status.add_child(_cursor)
	_status = Label.new()
	_status.text = "starting"
	status.add_child(_status)
	_debug = Label.new()
	status.add_child(_debug)
	var cons := Button.new()
	cons.text = "Log"
	cons.toggle_mode = true
	cons.tooltip_text = "Toggle console  (`)"
	cons.toggled.connect(func(on): _console.visible = on)
	status.add_child(cons)

	_probe_list = ItemList.new()
	_probe_list.visible = false
	add_child(_probe_list)
	_btn_probe = Button.new()
	_busy_targets = [_btn_open, _btn_new, _btn_save, _btn_validate]

	_pack_kind.add_item("BZP map", 0)
	_pack_kind.add_item("Base-game map", 1)
	for size in [1280, 2560, 3840, 5120]:
		_size_option.add_item("%s m" % size, size)
		_size_z.add_item("%s m" % size, size)

	_help = Window.new()
	_help.title = "Hotkeys"
	_help.size = Vector2i(460, 320)
	_help.visible = false
	_help.close_requested.connect(func(): _help.hide())
	var help_l := Label.new()
	help_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_l.offset_left = 16
	help_l.offset_top = 16
	help_l.offset_right = 444
	help_l.offset_bottom = 300
	help_l.text = """RMB look   mouse wheel zoom   MMB orbit   WASD fly   Q/E up down
Shift fast   Ctrl slow   F frame map   Space top-down   H slope tint
1–8 tools   [ ] radius   Shift+[ ] strength   Esc fly
Ctrl+Z undo   Ctrl+Shift+Z redo   Ctrl+S save   ` log   F1 this
LMB sculpt / place / select    Shift+click keep placing
Alt walk-the-surface"""
	_help.add_child(help_l)
	add_child(_help)


func _section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	return l


func _bar_btn(caption: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.pressed.connect(cb)
	return b


func _vsep() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(1, 18)
	r.color = Color(1, 1, 1, 0.10)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _ro_field(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.editable = false
	e.placeholder_text = placeholder
	return e


func _spin(prefix: String, mn: float, mx: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.prefix = prefix + " "
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _on_more(id: int) -> void:
	match id:
		0:
			_import_assets()
		1:
			_render_thumb()
		2:
			_install_mod()
		3:
			_assemble_pack()
		4:
			Backend.probe()
		5:
			_help.popup_centered()


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
		_camera.pivot = p
		_cursor.text = "xz %.1f, %.1f  h %.1f m  mat %d  %s   ·  RMB look  wheel zoom  MMB orbit  WASD fly" % [
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
		elif k.keycode == KEY_QUOTELEFT:
			_console.visible = not _console.visible
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
		elif k.keycode == KEY_F and not k.ctrl_pressed:
			camera_frame()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_SPACE:
			camera_overview()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_H:
			toggle_slope()
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
	if _tool_buttons.has(name):
		var btn: Button = _tool_buttons[name]
		btn.set_pressed_no_signal(true)
	if name != "place":
		_armed = {}
		_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
	if _terrain.has_method("set_show_grid"):
		_terrain.set_show_grid(name == "paint")
	_refresh_status()


func _on_view_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.handle_event(event)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _pick()
			if hit.get("hit", false):
				if mb.pressed:
					_on_lmb_down(hit["position"], hit, mb.shift_pressed)
				else:
					_on_lmb_up()
			accept_event()
			return
	elif event is InputEventMouseMotion and (_camera.looking or _camera.orbiting):
		_camera.handle_event(event)
		accept_event()


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
				_log("first run: importing asset index (icons). Import assets again to convert meshes.")
				Backend.assets(Settings.game_root, MapState.cache_dir(), false, false)
		"worlds":
			MapState.worlds = result.get("worlds", [])
			_fill_worlds(result)
			if MapState.has_session and _terrain.has_method("refresh_materials"):
				_terrain.refresh_materials()
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
		_try_load_asset_index()


func _fill_worlds(result: Dictionary) -> void:
	_world_option.clear()
	for world in result.get("worlds", []):
		if typeof(world) != TYPE_DICTIONARY:
			continue
		_world_option.add_item("%s" % world.get("label", world.get("id", "")))
		_world_option.set_item_metadata(_world_option.item_count - 1, world.get("id", ""))


func _try_load_asset_index() -> void:
	var idx := MapState.cache_dir().path_join("index.json")
	if not FileAccess.file_exists(idx):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	MapState.asset_index = parsed
	_fill_palette()


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
	if _insp_prj == null:
		return
	if MapState.selected_ids.is_empty():
		_insp_prj.text = ""
		_insp_label.text = ""
		_insp_mode.text = "nothing selected"
		return
	var rec := MapState.find_object(MapState.selected_ids[0])
	if rec.is_empty():
		return
	_insp_prj.text = str(rec.get("prjid", ""))
	_insp_label.text = str(rec.get("label", ""))
	_insp_x.value = float(rec.get("x", 0.0))
	_insp_y.value = float(rec.get("y", 0.0))
	_insp_z.value = float(rec.get("z", 0.0))
	_insp_yaw.value = float(rec.get("yaw_deg", 0.0))
	_insp_team.value = int(rec.get("team", 0))
	_insp_mode.text = "%s  ·  %s" % [
		rec.get("placement_mode", "bzn"),
		"required" if rec.get("required", false) else rec.get("id", ""),
	]


func _apply_inspector() -> void:
	if MapState.selected_ids.is_empty():
		return
	var id := MapState.selected_ids[0]
	var before := MapState.find_object(id).duplicate(true)
	if before.is_empty():
		return
	var after := before.duplicate(true)
	after["label"] = _insp_label.text
	after["x"] = _insp_x.value
	after["y"] = _insp_y.value
	after["z"] = _insp_z.value
	after["yaw_deg"] = _insp_yaw.value
	after["team"] = int(_insp_team.value)
	var cmd = ObjectCommandScript.new()
	cmd.kind = ObjectCommandScript.Kind.EDIT
	cmd.variant = MapState.find_object_variant(id)
	cmd.object_id = id
	cmd.before = before
	cmd.after = after
	UndoStack.push(cmd)
	_on_objects_mutated()


func _on_session_changed() -> void:
	_refresh_map_label()
	_fill_variants()
	_try_load_asset_index()
	_fill_palette()
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
	for b in _busy_targets:
		if b:
			b.disabled = value


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
