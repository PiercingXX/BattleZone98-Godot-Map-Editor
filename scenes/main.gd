extends Control
## Coordinator: input, backend fan-out, session lifecycle.

const TerrainRaycastScript = preload("res://project/terrain/TerrainRaycast.gd")
const DarkThemeScript = preload("res://project/ui/DarkTheme.gd")

@onready var _console: TextEdit = %Console
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _new_dialog: ConfirmationDialog = %NewDialog
@onready var _new_guard: ConfirmationDialog = %NewGuardDialog
@onready var _template_option: OptionButton = %TemplateOption
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog
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
@onready var _top = %TopBar
@onready var _palette = %PalettePanel
@onready var _inspector = %InspectorPanel
@onready var _findings = %FindingsPanel
@onready var _status = %StatusBar
@onready var _help = %HelpWindow
@onready var _probe = %ProbeDialog

var _sculpt = SculptTool.new()
var _io: SessionIO
var _stroking: bool = false
var _show_grid: bool = false
var _setting_tool: bool = false
var _ramp_a: Vector3 = Vector3.INF
var _last_stamp: Vector3 = Vector3.INF
var _pending_package: String = ""
var _probe_explicit: bool = false
var _save_as: bool = false
var _quit_after_save: bool = false
var _smoke_path: String = ""
var _smoke_save: String = ""


func _ready() -> void:
	randomize()
	theme = DarkThemeScript.make()
	add_to_group("editor_shell")
	get_tree().auto_accept_quit = false
	_io = SessionIO.new(self, _log)
	_wire()
	_try_load_asset_index()
	_pack_kind.add_item("BZP map", 0)
	_pack_kind.add_item("Base-game map", 1)
	for size in [1280, 2560, 3840, 5120]:
		_size_option.add_item("%s m" % size, size)
		_size_z.add_item("%s m" % size, size)
	var autosave := Timer.new()
	autosave.wait_time = 30.0
	autosave.timeout.connect(func():
		if MapState.has_session and MapState.unsaved:
			MapState.persist()
			_log.call("autosaved session")
	)
	add_child(autosave)
	autosave.start()
	_refresh_map_label()
	_log.call("BattleZone 98 Godot Map Editor. F1 help. Open a map to sculpt and place.")
	Backend.probe()
	_queue_smoke_open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if MapState.unsaved:
			_quit_dialog.popup_centered()
		else:
			get_tree().quit()


func _wire() -> void:
	_top.open_requested.connect(_io.open_prompt)
	_top.new_requested.connect(_io.new_prompt)
	_top.save_requested.connect(_io.save)
	_top.save_as_requested.connect(func(): _save_as = true; _io.save(true))
	_top.validate_requested.connect(_io.validate)
	_top.more_selected.connect(_io.handle_more)
	_top.tool_selected.connect(_set_tool)
	_top.variant_changed.connect(func():
		MapState.active_variant = _top.selected_variant()
		_on_objects_mutated()
	)
	_top.undo_requested.connect(func(): UndoStack.undo())
	_top.redo_requested.connect(func(): UndoStack.redo())
	_top.frame_requested.connect(camera_frame)
	_palette.class_armed.connect(func(rec):
		ToolState.set_armed(rec)
		_log.call("armed %s  %s  %s" % [rec.get("prjid"), rec.get("placement_mode"), rec.get("mesh_fidelity")])
	)
	_inspector.apply_requested.connect(func(before, after):
		EditActions.apply_inspector(before, after)
		_on_objects_mutated()
	)
	_inspector.delete_requested.connect(func():
		EditActions.delete_selected(_log)
		_on_objects_mutated()
	)
	_inspector.water_changed.connect(MapState.set_water_level)
	_findings.finding_selected.connect(_on_finding_select)
	_findings.finding_activated.connect(_on_finding_fly)
	_findings.validate_requested.connect(_io.validate)
	_status.log_toggled.connect(func(on): _console.visible = on)
	_probe.install_chosen.connect(_io.choose_install)
	_quit_dialog.confirmed.connect(_io.quit_save)
	_quit_dialog.add_button("Discard", true, "discard")
	_quit_dialog.custom_action.connect(func(a):
		if a == "discard":
			get_tree().quit()
	)
	_new_guard.confirmed.connect(_io.new_after_save)
	_new_guard.add_button("Discard changes", true, "discard")
	_new_guard.custom_action.connect(func(a):
		if a == "discard":
			_new_guard.hide()
			_io.show_new_dialog()
	)
	%Center.gui_input.connect(_on_view_gui_input)
	%Center.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_dialog.canceled.connect(func():
		_quit_after_save = false
		_save_as = false
		_pending_package = ""
	)
	Backend.discovered.connect(_on_discovered)
	Backend.call_started.connect(_on_call_started)
	Backend.stderr_line.connect(_on_stderr)
	Backend.call_finished.connect(_on_call_finished)
	Backend.call_failed.connect(_on_call_failed)
	MapState.session_changed.connect(_on_session_changed)
	MapState.objects_mutated.connect(_on_objects_mutated)
	MapState.materials_changed.connect(_on_materials_changed)
	MapState.dirty_changed.connect(func():
		if MapState.findings_stale and not MapState.findings.is_empty():
			_findings.set_findings(MapState.findings, true)
	)
	UndoStack.changed.connect(_refresh_map_label)
	ToolState.tool_changed.connect(_on_tool_state)
	ToolState.brush_changed.connect(_sync_sculpt)
	ToolState.armed_changed.connect(func():
		if ToolState.armed.is_empty():
			_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
	)
	if _camera.has_signal("speed_changed"):
		_camera.speed_changed.connect(func(mps): _status.set_status("transient", "cam %.0f m/s" % mps))
	_sync_sculpt()


func _process(_delta: float) -> void:
	_status.set_debug("%d fps  chunks %d  up %d B" % [
		int(Engine.get_frames_per_second()),
		_terrain.get_child_count() if _terrain else 0,
		_sculpt.last_uploaded,
	])
	if not MapState.has_session:
		return
	if not _center.get_global_rect().has_point(get_global_mouse_position()):
		_terrain.set_brush(false, Vector2.ZERO, 0.0, 0.0, false)
		return
	var hit := _pick()
	if hit.get("hit", false):
		var p: Vector3 = hit["position"]
		_camera.pivot = p
		_status.set_cursor("xz %.1f, %.1f  h %.1f m  mat %d  %s   ·  RMB look  wheel zoom  MMB orbit  WASD fly" % [
			p.x, p.z, p.y, MapState.material_at(p.x, p.z), ToolState.tool,
		])
		var sculpting := ToolState.tool in ["raise", "lower", "flatten", "smooth", "ramp", "noise", "undefined", "paint"]
		if sculpting:
			_terrain.set_brush(true, Vector2(p.x, p.z), ToolState.radius_m, ToolState.falloff, ToolState.shape == "square")
		else:
			_terrain.set_brush(false, Vector2.ZERO, 0.0, 0.0, false)
		if ToolState.tool == "place" and not ToolState.armed.is_empty():
			var ghost := ToolState.armed.duplicate()
			ghost["x"] = p.x
			ghost["z"] = p.z
			ghost["y"] = p.y
			_objects.set_ghost(true, ghost, MapState.field, hit.get("normal", Vector3.UP))
	if _stroking and hit.get("hit", false) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var p2: Vector3 = hit["position"]
		if _last_stamp.distance_to(p2) >= maxf(HeightField.CELL_M, ToolState.radius_m * 0.15):
			_sculpt.stamp(MapState.field, p2.x, p2.z)
			_last_stamp = p2


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	var handled := true
	if k.keycode == KEY_F1:
		_help.popup_help()
	elif k.keycode == KEY_QUOTELEFT:
		_console.visible = not _console.visible
		_status.set_log_visible(_console.visible)
	elif k.keycode == KEY_G:
		_show_grid = not _show_grid
		_apply_grid()
	elif k.keycode == KEY_DELETE:
		EditActions.delete_selected(_log)
		_on_objects_mutated()
	elif k.keycode == KEY_ESCAPE:
		ToolState.clear_armed()
		_set_tool("fly")
	elif k.ctrl_pressed and k.keycode == KEY_Z:
		UndoStack.redo() if k.shift_pressed else UndoStack.undo()
	elif k.ctrl_pressed and k.keycode == KEY_S:
		_io.save()
	elif k.keycode == KEY_V:
		Settings.walk_mode = not Settings.walk_mode
		Settings.save()
		_log.call("walk mode %s" % Settings.walk_mode)
	elif k.keycode == KEY_BRACKETLEFT:
		ToolState.set_strength(maxf(0.05, ToolState.strength - 0.05)) if k.shift_pressed else ToolState.set_radius(maxf(5, ToolState.radius_m - 5))
	elif k.keycode == KEY_BRACKETRIGHT:
		ToolState.set_strength(minf(1.0, ToolState.strength + 0.05)) if k.shift_pressed else ToolState.set_radius(minf(400, ToolState.radius_m + 5))
	elif k.keycode >= KEY_1 and k.keycode <= KEY_8:
		_set_tool(["fly", "raise", "lower", "flatten", "smooth", "ramp", "paint", "place"][k.keycode - KEY_1])
	elif k.keycode == KEY_9:
		_set_tool("select")
	elif k.keycode == KEY_0:
		_set_tool("noise")
	elif k.keycode == KEY_F and not k.ctrl_pressed:
		camera_frame()
	elif k.keycode == KEY_SPACE:
		if MapState.has_session:
			_camera.top_down(float(MapState.width_m), float(MapState.depth_m))
	elif k.keycode == KEY_H:
		if _terrain.has_method("set_slope_overlay"):
			_terrain._show_slope = not _terrain._show_slope
			_terrain.set_slope_overlay(_terrain._show_slope)
			_log.call("slope overlay %s" % ("on" if _terrain._show_slope else "off"))
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_view_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.handle_event(event)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				_on_lmb_up()
			elif ToolState.tool == "select":
				EditActions.select_click(_objects, _camera, _viewport, mb.shift_pressed)
				_fill_inspector()
			else:
				var hit := _pick()
				if hit.get("hit", false):
					_on_lmb_down(hit["position"], hit, mb.shift_pressed)
			accept_event()
	elif event is InputEventMouseMotion and (_camera.looking or _camera.orbiting):
		_camera.handle_event(event)
		accept_event()


func _on_lmb_down(p: Vector3, hit: Dictionary, shift: bool) -> void:
	if ToolState.tool == "place" and not ToolState.armed.is_empty():
		EditActions.place_at(p, hit.get("normal", Vector3.UP), shift, _log)
		return
	if ToolState.tool == "ramp":
		if _ramp_a.x > 1.0e8:
			_ramp_a = p
			_log.call("ramp start %.1f, %.1f  h %.1f" % [p.x, p.z, p.y])
		else:
			EditActions.apply_ramp(_sculpt, _ramp_a, p, _log)
			_ramp_a = Vector3.INF
		return
	if ToolState.tool in ["raise", "lower", "flatten", "smooth", "noise", "undefined", "paint"]:
		_sync_sculpt()
		_sculpt.begin_stroke(MapState.field, p.x, p.z, ToolState.tool == "paint")
		_stroking = true
		_last_stamp = p


func _on_lmb_up() -> void:
	if not _stroking:
		return
	_stroking = false
	if ToolState.tool == "paint":
		var paint_cmd = _sculpt.end_paint()
		if paint_cmd:
			UndoStack.push(paint_cmd)
	else:
		var cmd2 = _sculpt.end_stroke(MapState.field)
		if cmd2:
			UndoStack.push(cmd2, true)
	_on_objects_mutated()


func _set_tool(name: String) -> void:
	if _setting_tool:
		return
	_setting_tool = true
	ToolState.set_tool(name)
	_setting_tool = false


func _on_tool_state(name: String) -> void:
	_sculpt.mode = name
	# TopBar subscribes to ToolState.tool_changed itself.
	_apply_grid()
	if name != "ramp":
		_ramp_a = Vector3.INF
	if name != "place":
		_objects.set_ghost(false, {}, MapState.field, Vector3.UP)


func _sync_sculpt() -> void:
	_sculpt.radius_m = ToolState.radius_m
	_sculpt.strength = ToolState.strength
	_sculpt.falloff = ToolState.falloff
	_sculpt.shape = ToolState.shape
	_sculpt.paint_material = ToolState.paint_material
	_sculpt.mode = ToolState.tool


func _apply_grid() -> void:
	if _terrain.has_method("set_show_grid"):
		_terrain.set_show_grid(_show_grid or ToolState.tool == "paint")


func _pick() -> Dictionary:
	if not MapState.has_session:
		return {"hit": false}
	var mouse := _viewport.get_mouse_position()
	return TerrainRaycastScript.intersect(_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse), MapState.field)


func _on_discovered(ok: bool, detail: String) -> void:
	_log.call(detail)
	_status.set_status("ok" if ok else "error", "backend ready" if ok else "backend missing")


func _on_call_started(verb: String) -> void:
	_status.set_status("busy", "bzmap editor %s…" % verb)
	_top.set_busy(true)


func _on_stderr(line: String) -> void:
	_log.call(line)


func _on_call_finished(verb: String, result: Dictionary) -> void:
	_top.set_busy(false)
	_status.set_status("ok", "ok: %s" % verb)
	match verb:
		"probe":
			# Only interrupt with the install picker when there is a choice
			# to make (no saved root) or the user explicitly asked via More →
			# Re-probe; routine startup probes stay silent.
			var explicit := _probe_explicit
			_probe_explicit = false
			if not _is_smoke() and (
				explicit
				or Settings.game_root.is_empty()
				or (result.get("installs", []) as Array).is_empty()
			):
				_probe.show_probe(result)
			if not Settings.game_root.is_empty() and not _is_smoke():
				Backend.worlds(Settings.game_root)
				_try_load_asset_index()
			if not Settings.game_root.is_empty() and not FileAccess.file_exists(MapState.cache_dir().path_join("index.json")):
				_log.call("first run: importing asset index (icons). Import assets again to convert meshes.")
				Backend.assets(Settings.game_root, MapState.cache_dir(), false, false)
			if not _smoke_path.is_empty():
				var path := _smoke_path
				_smoke_path = ""
				Backend.open_map(path, MapState.new_session_dir())
		"worlds":
			MapState.worlds = result.get("worlds", [])
			_world_option.clear()
			for world in result.get("worlds", []):
				if typeof(world) != TYPE_DICTIONARY:
					continue
				_world_option.add_item("%s" % world.get("label", world.get("id", "")))
				_world_option.set_item_metadata(_world_option.item_count - 1, world.get("id", ""))
			if MapState.has_session and _terrain.has_method("refresh_materials"):
				_terrain.refresh_materials()
			_palette.refresh_swatches()
		"open", "new":
			MapState.load_from_open(result)
			if not _io.template_stem.is_empty():
				MapState.stem = _io.template_stem
				_io.template_stem = ""
				MapState.unsaved = true
				_refresh_map_label()
			for w in result.get("warnings", []):
				_log.call("warning: %s" % w)
			if _is_smoke():
				if not _smoke_save.is_empty():
					var out := _smoke_save
					_smoke_save = ""
					MapState.persist()
					Backend.save_map(MapState.session_dir, out, MapState.stem)
				else:
					get_tree().quit(0)
		"save":
			MapState.unsaved = false
			_log.call("saved %d files to %s" % [
				(result.get("files", []) as Array).size(), Settings.last_save_dir,
			])
			_log.call("byte-identical: %s" % ", ".join(PackedStringArray(result.get("byte_identical", []))))
			var regen: Array = result.get("regenerated", [])
			if not regen.is_empty():
				_log.call("regenerated: %s" % ", ".join(PackedStringArray(regen)))
			for w2 in result.get("warnings", []):
				_log.call("warning: %s" % w2)
			if result.has("features"):
				_log.call("features: %s" % result["features"])
			if _quit_after_save:
				get_tree().quit()
			if _is_smoke():
				get_tree().quit(0)
			if _io.consume_new_after_save():
				_io.show_new_dialog()
		"validate":
			MapState.findings = result.get("findings", [])
			MapState.findings_stale = false
			_findings.set_findings(MapState.findings, false)
			_log.call("%d findings (not an in-game verdict)" % MapState.findings.size())
		"assets":
			MapState.asset_index = result
			Settings.last_cache_fingerprint = str(result.get("source_fingerprint", ""))
			Settings.save()
			_fill_palette()
			_log.call("%d classes  %d unresolved  fidelity mostly proxy" % [
				result.get("classes", []).size(), result.get("unresolved", []).size(),
			])
		"render":
			_log.call("thumbnail %s" % result.get("png", ""))
		"package":
			_log.call("package %s: %d files → %s" % [
				result.get("mode", ""), (result.get("files", []) as Array).size(),
				result.get("dest", ""),
			])
			var shared: Array = result.get("shared_lua", [])
			if not shared.is_empty():
				_log.call("bundled shared lua: %s" % ", ".join(PackedStringArray(shared)))


func _on_call_failed(verb: String, error: Dictionary) -> void:
	if verb == "save":
		# A failed save must not leave quit / new-map / package intents
		# armed for the next save that succeeds.
		_quit_after_save = false
		_save_as = false
		_pending_package = ""
		_io.consume_new_after_save()
	_top.set_busy(false)
	_console.visible = true
	_status.set_log_visible(true)
	_status.set_status("error", "error: %s" % verb)
	_log.call("ERROR [%s] %s" % [error.get("code", "?"), error.get("message", error)])
	if error.has("hint"):
		_log.call("  hint: %s" % error["hint"])
	if _is_smoke() and verb != "probe":
		get_tree().quit(1)


func _is_smoke() -> bool:
	return OS.get_cmdline_user_args().has("--smoke-open")


func _try_load_asset_index() -> void:
	var idx := MapState.cache_dir().path_join("index.json")
	if not FileAccess.file_exists(idx):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx))
	if typeof(parsed) == TYPE_DICTIONARY:
		MapState.asset_index = parsed
		_fill_palette()


func _fill_palette() -> void:
	var pack: Dictionary = MapState.manifest.get("pack_context", {})
	_palette.set_classes(MapState.asset_index, str(pack.get("kind", "bzp")))


func _on_finding_select(f: Dictionary) -> void:
	var oid := str(f.get("object_id", ""))
	if oid.is_empty():
		return
	MapState.selected_ids = [oid] as Array[String]
	_objects.highlight(MapState.selected_ids)
	_fill_inspector()


func _on_finding_fly(f: Dictionary) -> void:
	_on_finding_select(f)
	var pos = f.get("world_pos", null)
	if typeof(pos) != TYPE_ARRAY or (pos as Array).size() < 3:
		var rec := MapState.find_object(str(f.get("object_id", "")))
		if not rec.is_empty():
			pos = [rec.get("x", 0.0), rec.get("y", 0.0), rec.get("z", 0.0)]
	if typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
		_camera.global_position = Vector3(float(pos[0]), float(pos[1]) + 40.0, float(pos[2]) - 40.0)
		_camera.look_at(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), Vector3.UP)


func _fill_inspector() -> void:
	if MapState.selected_ids.is_empty():
		_inspector.clear()
	else:
		_inspector.show_object(MapState.find_object(MapState.selected_ids[0]))


func _on_session_changed() -> void:
	if _objects.has_method("reset"):
		_objects.reset()
	_refresh_map_label()
	_top.fill_variants(MapState.manifest.get("variants", [""]), MapState.active_variant)
	_try_load_asset_index()
	_fill_palette()
	_inspector.set_water(MapState.water_level())
	_findings.set_findings(MapState.findings, MapState.findings_stale)
	if not MapState.has_session:
		return
	if _terrain.has_method("rebuild"):
		_terrain.rebuild(MapState.field)
	_on_objects_mutated()
	camera_frame()
	_terrain.refresh_materials()
	_palette.refresh_swatches()


func _on_objects_mutated() -> void:
	if _objects.has_method("rebuild"):
		_objects.rebuild(MapState.objects, MapState.field)
	_objects.highlight(MapState.selected_ids)
	_fill_inspector()
	_refresh_map_label()


func _on_materials_changed() -> void:
	if _terrain.has_method("refresh_materials"):
		_terrain.refresh_materials()


func _refresh_map_label() -> void:
	if not MapState.has_session:
		_top.set_map_label("no map open")
		_status.set_map_info("")
		return
	_top.set_map_label("%s%s" % [MapState.stem, "*" if MapState.unsaved else ""])
	_status.set_map_info("%sx%s  %s" % [MapState.width_m, MapState.depth_m, MapState.world])
	if MapState.ceiling_hit:
		_status.set_status("error", "hit raw 4095 ceiling")


func camera_frame() -> void:
	if not MapState.has_session or MapState.field.grid_x < 2:
		return
	_camera.frame_map(float(MapState.width_m), float(MapState.depth_m), MapState.field.height_at(float(MapState.width_m) * 0.5, float(MapState.depth_m) * 0.5))


func _log(text: String) -> void:
	_console.text = text if _console.text.is_empty() else _console.text + "\n" + text
	_console.scroll_vertical = _console.get_line_count()


func _queue_smoke_open() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--smoke-open" and i + 1 < args.size():
			_smoke_path = args[i + 1]
		if args[i] == "--smoke-save" and i + 1 < args.size():
			_smoke_save = args[i + 1]


func _on_file_dialog_file_selected(path: String) -> void:
	_io.open_file(path)


func _on_new_dialog_confirmed() -> void:
	_io.new_confirmed()


func _on_save_dialog_dir_selected(dir: String) -> void:
	_io.dir_selected(dir)
