extends Window
class_name PrefsDialog
## Live-applied editor preferences. Every control writes Settings immediately.

var _applying: bool = false
var _scheme_godot: Button
var _scheme_gimp: Button
var _scale: HSlider
var _scale_label: Label
var _scale_dragging: bool = false
var _auto_15: Button
var _auto_30: Button
var _auto_60: Button
var _auto_off: Button
var _cam_speed: HSlider
var _cam_label: Label
var _invert: CheckBox
var _colorblind: CheckBox
var _save_dir: LineEdit
var _browse: FileDialog


func _ready() -> void:
	title = "Preferences"
	unresizable = false
	visible = false
	close_requested.connect(hide)
	min_size = Vector2i(460, 520)
	size = Vector2i(480, 560)
	_build_ui()
	refresh()


func popup_prefs() -> void:
	refresh()
	popup_centered()


func refresh() -> void:
	_applying = true
	_sync_scheme()
	if _scale:
		_scale.value = Settings.coerce_ui_scale(Settings.ui_scale)
	_sync_scale_label()
	_sync_autosave()
	if _cam_speed:
		_cam_speed.value = Settings.coerce_camera_speed(Settings.camera_speed_mul)
	_sync_cam_label()
	if _invert:
		_invert.set_pressed_no_signal(Settings.invert_look)
	if _colorblind:
		_colorblind.set_pressed_no_signal(Settings.colorblind_teams)
	if _save_dir:
		var shown := Settings.default_save_dir
		if shown.is_empty():
			shown = Settings.last_save_dir
		_save_dir.text = shown
	_applying = false


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(_heading("Keyboard scheme"))
	var scheme_row := HBoxContainer.new()
	scheme_row.add_theme_constant_override("separation", 12)
	box.add_child(scheme_row)
	var scheme_group := ButtonGroup.new()
	_scheme_godot = _radio("Godot", scheme_group)
	_scheme_godot.tooltip_text = "Number-row tool keys"
	_scheme_gimp = _radio("GIMP", scheme_group)
	_scheme_gimp.tooltip_text = "GIMP-style tool keys"
	_scheme_godot.pressed.connect(func(): _apply_scheme(Keymap.SCHEME_GODOT))
	_scheme_gimp.pressed.connect(func(): _apply_scheme(Keymap.SCHEME_GIMP))
	scheme_row.add_child(_scheme_godot)
	scheme_row.add_child(_scheme_gimp)

	box.add_child(_heading("UI scale"))
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	box.add_child(scale_row)
	_scale = HSlider.new()
	_scale.name = "UiScale"
	_scale.min_value = Settings.UI_SCALE_MIN
	_scale.max_value = Settings.UI_SCALE_MAX
	_scale.step = 0.05
	_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale.tooltip_text = "Window content scale (%.2f–%.2f)" % [Settings.UI_SCALE_MIN, Settings.UI_SCALE_MAX]
	_scale.value_changed.connect(_on_scale)
	# Rescaling the whole window on every intermediate value makes the slider
	# fight the cursor it is being dragged with. While the grab is held the
	# readout tracks live and nothing else moves; the scale lands on release.
	_scale.drag_started.connect(func() -> void: _scale_dragging = true)
	_scale.drag_ended.connect(_on_scale_drag_ended)
	scale_row.add_child(_scale)
	_scale_label = Label.new()
	_scale_label.name = "UiScaleValue"
	_scale_label.custom_minimum_size = Vector2(48, 0)
	scale_row.add_child(_scale_label)

	box.add_child(_heading("Autosave"))
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 8)
	box.add_child(auto_row)
	var auto_group := ButtonGroup.new()
	_auto_15 = _radio("15s", auto_group)
	_auto_30 = _radio("30s", auto_group)
	_auto_60 = _radio("60s", auto_group)
	_auto_off = _radio("Off", auto_group)
	_auto_15.tooltip_text = "Persist the unsaved session every 15 seconds"
	_auto_30.tooltip_text = "Persist the unsaved session every 30 seconds"
	_auto_60.tooltip_text = "Persist the unsaved session every 60 seconds"
	_auto_off.tooltip_text = "Do not autosave; Ctrl+S still writes the map files"
	_auto_15.pressed.connect(func(): _apply_autosave(15))
	_auto_30.pressed.connect(func(): _apply_autosave(30))
	_auto_60.pressed.connect(func(): _apply_autosave(60))
	_auto_off.pressed.connect(func(): _apply_autosave(0))
	auto_row.add_child(_auto_15)
	auto_row.add_child(_auto_30)
	auto_row.add_child(_auto_60)
	auto_row.add_child(_auto_off)

	box.add_child(_heading("Camera"))
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 8)
	box.add_child(cam_row)
	var cam_cap := Label.new()
	cam_cap.text = "Speed"
	cam_row.add_child(cam_cap)
	_cam_speed = HSlider.new()
	_cam_speed.name = "CameraSpeed"
	_cam_speed.min_value = Settings.CAM_SPEED_MIN
	_cam_speed.max_value = Settings.CAM_SPEED_MAX
	_cam_speed.step = 0.05
	_cam_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_speed.tooltip_text = "Multiplier on fly / pan speed (Shift and Ctrl still stack)"
	_cam_speed.value_changed.connect(_on_cam_speed)
	cam_row.add_child(_cam_speed)
	_cam_label = Label.new()
	_cam_label.name = "CameraSpeedValue"
	_cam_label.custom_minimum_size = Vector2(48, 0)
	cam_row.add_child(_cam_label)
	_invert = CheckBox.new()
	_invert.name = "InvertLook"
	_invert.text = "Invert look"
	_invert.tooltip_text = "Flip vertical mouse look"
	_invert.toggled.connect(_on_invert)
	box.add_child(_invert)

	box.add_child(_heading("Team colours"))
	_colorblind = CheckBox.new()
	_colorblind.name = "ColorblindTeams"
	_colorblind.text = "Colorblind-safe palette"
	_colorblind.tooltip_text = "Swap the team tint table for a colourblind-safe set"
	_colorblind.toggled.connect(_on_colorblind)
	box.add_child(_colorblind)

	box.add_child(_heading("Default save directory"))
	var dir_row := HBoxContainer.new()
	dir_row.add_theme_constant_override("separation", 8)
	box.add_child(dir_row)
	_save_dir = LineEdit.new()
	_save_dir.name = "SaveDir"
	_save_dir.placeholder_text = "Save As starts here"
	_save_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_dir.text_submitted.connect(_on_save_dir_submitted)
	_save_dir.focus_exited.connect(_commit_save_dir)
	dir_row.add_child(_save_dir)
	var browse_btn := Button.new()
	browse_btn.name = "BrowseSaveDir"
	browse_btn.text = "Browse…"
	browse_btn.tooltip_text = "Choose a default folder for Save / Save As"
	browse_btn.pressed.connect(_on_browse)
	dir_row.add_child(browse_btn)

	_browse = FileDialog.new()
	_browse.name = "SaveDirDialog"
	_browse.access = FileDialog.ACCESS_FILESYSTEM
	_browse.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_browse.title = "Default save directory"
	_browse.ok_button_text = "Use this folder"
	_browse.dir_selected.connect(_apply_save_dir)
	add_child(_browse)


func _heading(caption: String) -> Label:
	var l := Label.new()
	l.text = caption
	l.add_theme_color_override("font_color", Color(0.78, 0.80, 0.84))
	return l


func _radio(caption: String, group: ButtonGroup) -> Button:
	var b := CheckBox.new()
	b.text = caption
	b.toggle_mode = true
	b.button_group = group
	return b


func _apply_scheme(scheme: String) -> void:
	if _applying:
		return
	var next := Keymap.normalize_scheme(scheme)
	if Settings.keymap_scheme == next:
		return
	var io: Variant = null
	var shell := _shell()
	if shell != null:
		io = shell.get("_io")
	if io != null and io.has_method("apply_keymap_scheme"):
		io.apply_keymap_scheme(next)
	else:
		Settings.keymap_scheme = next
		Settings.save()
		EditorFeedback.log("keyboard scheme %s" % next)
	_sync_scheme()


func _on_scale_drag_ended(value_changed: bool) -> void:
	_scale_dragging = false
	if _scale == null:
		return
	if value_changed or not is_equal_approx(
		Settings.ui_scale, Settings.coerce_ui_scale(_scale.value)
	):
		_on_scale(_scale.value)


func _on_scale(v: float) -> void:
	if _applying:
		return
	if _scale_dragging:
		# Preview only — the label reads the slider, not the applied setting.
		if _scale_label:
			_scale_label.text = "%.2f×" % Settings.coerce_ui_scale(v)
		return
	var next := Settings.coerce_ui_scale(v)
	if is_equal_approx(Settings.ui_scale, next):
		_sync_scale_label()
		return
	Settings.ui_scale = next
	Settings.apply_ui_scale()
	Settings.save()
	_sync_scale_label()
	EditorFeedback.log("ui scale %.2f" % next)


func _apply_autosave(seconds: int) -> void:
	if _applying:
		return
	var next := Settings.coerce_autosave_interval(seconds)
	if Settings.autosave_interval_s == next:
		return
	Settings.autosave_interval_s = next
	Settings.save()
	var shell := _shell()
	if shell != null and shell.has_method("_apply_autosave"):
		shell.call("_apply_autosave")
	Settings.notify_prefs()
	if next <= 0:
		EditorFeedback.log("autosave off")
	else:
		EditorFeedback.log("autosave every %ds" % next)


func _on_cam_speed(v: float) -> void:
	if _applying:
		return
	var next := Settings.coerce_camera_speed(v)
	if is_equal_approx(Settings.camera_speed_mul, next):
		_sync_cam_label()
		return
	Settings.camera_speed_mul = next
	Settings.save()
	Settings.notify_prefs()
	_sync_cam_label()
	EditorFeedback.log("camera speed %.2f×" % next)


func _on_invert(on: bool) -> void:
	if _applying:
		return
	if Settings.invert_look == on:
		return
	Settings.invert_look = on
	Settings.save()
	Settings.notify_prefs()
	EditorFeedback.log("invert look %s" % ("on" if on else "off"))


func _on_colorblind(on: bool) -> void:
	if _applying:
		return
	if Settings.colorblind_teams == on:
		return
	Settings.colorblind_teams = on
	Settings.save()
	Settings.notify_prefs()
	_refresh_team_views()
	EditorFeedback.log("colorblind team palette %s" % ("on" if on else "off"))


func _on_browse() -> void:
	var start := _save_dir.text.strip_edges() if _save_dir else ""
	if start.is_empty():
		start = Settings.effective_save_dir()
	if not start.is_empty() and DirAccess.dir_exists_absolute(start):
		_browse.current_dir = start
	_browse.popup_centered_ratio(0.5)


func _on_save_dir_submitted(path: String) -> void:
	_apply_save_dir(path)


func _commit_save_dir() -> void:
	if _save_dir == null or _applying:
		return
	_apply_save_dir(_save_dir.text)


func _apply_save_dir(path: String) -> void:
	if _applying:
		return
	var cleaned := path.strip_edges().simplify_path()
	if cleaned == Settings.default_save_dir and cleaned == Settings.last_save_dir:
		return
	Settings.default_save_dir = cleaned
	if not cleaned.is_empty():
		Settings.last_save_dir = cleaned
	Settings.save()
	if _save_dir:
		_save_dir.text = cleaned
	if cleaned.is_empty():
		EditorFeedback.log("default save directory cleared")
	else:
		EditorFeedback.log("default save directory %s" % cleaned)


func _sync_scheme() -> void:
	var scheme := Keymap.active_scheme()
	if _scheme_godot:
		_scheme_godot.set_pressed_no_signal(scheme == Keymap.SCHEME_GODOT)
	if _scheme_gimp:
		_scheme_gimp.set_pressed_no_signal(scheme == Keymap.SCHEME_GIMP)


func _sync_autosave() -> void:
	var n := Settings.coerce_autosave_interval(Settings.autosave_interval_s)
	if _auto_15:
		_auto_15.set_pressed_no_signal(n == 15)
	if _auto_30:
		_auto_30.set_pressed_no_signal(n == 30)
	if _auto_60:
		_auto_60.set_pressed_no_signal(n == 60)
	if _auto_off:
		_auto_off.set_pressed_no_signal(n == 0)


func _sync_scale_label() -> void:
	if _scale_label:
		_scale_label.text = "%.2f×" % Settings.coerce_ui_scale(Settings.ui_scale)


func _sync_cam_label() -> void:
	if _cam_label:
		_cam_label.text = "%.2f×" % Settings.coerce_camera_speed(Settings.camera_speed_mul)


func _refresh_team_views() -> void:
	var shell := _shell()
	if shell == null:
		return
	var objects: Variant = shell.get("_objects")
	if objects != null and objects.has_method("apply_visibility"):
		objects.call("apply_visibility")
	var balance: Variant = shell.get("_balance")
	if balance != null and balance.has_method("schedule_recompute"):
		balance.call("schedule_recompute")


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")
