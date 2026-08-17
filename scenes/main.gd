extends Control
## Phase 0/1 shell: backend probe, console, open/new/save against the bridge.

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


func _ready() -> void:
	randomize()
	add_to_group("editor_shell")
	Backend.discovered.connect(_on_discovered)
	Backend.call_started.connect(_on_call_started)
	Backend.stderr_line.connect(_on_stderr)
	Backend.call_finished.connect(_on_call_finished)
	Backend.call_failed.connect(_on_call_failed)
	MapState.session_changed.connect(_on_session_changed)
	if _camera.has_signal("speed_changed"):
		_camera.speed_changed.connect(_on_speed_changed)
	_refresh_map_label()
	_log("BattleZone 98 Godot Map Editor — standalone. Open a .trn/.bzn/.hg2 to fly the terrain.")
	print("BZEDITOR: backend available=", Backend.available, " home=", Backend.bzmap_home)
	if Backend.available:
		_log(Backend.bzmap_home)
		Backend.probe()
		_queue_smoke_open()
	else:
		_status.text = "backend missing"
		_log(Backend.last_error)


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
	_log(JSON.stringify(result, "  ").substr(0, 4000))
	match verb:
		"probe":
			print("BZEDITOR: probe ok installs=", result.get("installs", []).size())
			_fill_probe(result)
			if not _smoke_path.is_empty():
				var path := _smoke_path
				_smoke_path = ""
				print("BZEDITOR: smoke-open ", path)
				Backend.open_map(path, MapState.new_session_dir())
		"worlds":
			_fill_worlds(result)
		"open", "new":
			MapState.load_from_open(result)
			for w in result.get("warnings", []):
				_log("warning: %s" % w)
			print("BZEDITOR: map open ", MapState.stem, " ", MapState.width_m, "x", MapState.depth_m)
			if _is_smoke():
				get_tree().quit(0)
		"save":
			var ident: Array = result.get("byte_identical", [])
			var regen: Array = result.get("regenerated", [])
			_log("byte-identical: %s" % ", ".join(ident))
			if not regen.is_empty():
				_log("regenerated: %s" % ", ".join(regen))
		"validate":
			var findings: Array = result.get("findings", [])
			_log("%d findings" % findings.size())


func _on_call_failed(verb: String, error: Dictionary) -> void:
	_set_busy(false)
	_status.text = "error: %s" % verb
	_log("ERROR [%s] %s" % [error.get("code", "?"), error.get("message", error)])
	if error.has("hint"):
		_log("  hint: %s" % error["hint"])
	print("BZEDITOR: FAIL ", verb, " ", error.get("code", ""), " ", error.get("message", ""))
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


func _fill_worlds(result: Dictionary) -> void:
	_world_option.clear()
	for world in result.get("worlds", []):
		if typeof(world) != TYPE_DICTIONARY:
			continue
		_world_option.add_item("%s" % world.get("label", world.get("id", "")))
		_world_option.set_item_metadata(_world_option.item_count - 1, world.get("id", ""))


func _on_session_changed() -> void:
	_refresh_map_label()
	if not MapState.has_session:
		return
	if _terrain.has_method("rebuild"):
		_terrain.rebuild(MapState.field)
	if _objects.has_method("rebuild"):
		_objects.rebuild(MapState.objects, MapState.field)
	camera_frame()


func _refresh_map_label() -> void:
	if not MapState.has_session:
		_map_label.text = "no map open"
		return
	_map_label.text = "%s  %sx%s  %s" % [
		MapState.stem, MapState.width_m, MapState.depth_m, MapState.world
	]


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
	var session := MapState.new_session_dir()
	Backend.open_map(path, session)


func _on_btn_new_pressed() -> void:
	if _world_option.item_count == 0 and not Settings.game_root.is_empty():
		Backend.worlds(Settings.game_root)
	if _size_option.item_count == 0:
		for size in [1280, 2560, 3840, 5120]:
			_size_option.add_item("%s m" % size, size)
	_new_dialog.popup_centered()


func _on_new_dialog_confirmed() -> void:
	var stem := _stem_edit.text.strip_edges()
	if stem.is_empty() or stem.length() > 8:
		_log("stem must be 1–8 characters")
		return
	var world := "mars"
	if _world_option.selected >= 0:
		var meta = _world_option.get_item_metadata(_world_option.selected)
		if meta != null:
			world = str(meta)
	var size := 1280
	if _size_option.selected >= 0:
		size = _size_option.get_item_id(_size_option.selected)
		if size <= 0:
			size = 1280
	var session := MapState.new_session_dir()
	Backend.new_map(stem, world, size, size, session, Settings.game_root)


func _on_btn_save_pressed() -> void:
	if not MapState.has_session:
		_log("nothing to save")
		return
	_save_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_save_dialog.popup_centered_ratio(0.5)


func _on_save_dialog_dir_selected(dir: String) -> void:
	Backend.save_map(MapState.session_dir, dir, MapState.stem)


func _on_btn_validate_pressed() -> void:
	if not MapState.has_session:
		_log("nothing to validate")
		return
	Backend.validate(MapState.session_dir, Settings.game_root)
