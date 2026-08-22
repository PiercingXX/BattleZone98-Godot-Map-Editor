extends Window
class_name PrefsDialog
## Live-applied editor preferences. Every control writes Settings immediately.

var _applying: bool = false
var _scheme_godot: Button
var _scheme_gimp: Button
var _bindings: Tree
var _binding_status: Label
var _btn_rebind: Button
var _btn_clear: Button
var _btn_reset: Button
var _btn_reset_all: Button
var _confirm_row: HBoxContainer
## Action waiting for a keypress, "" when not capturing.
var _capture_action: String = ""
## Chord captured but parked behind a conflict the user has not answered.
var _pending_action: String = ""
var _pending_chord: Dictionary = {}
var _font: HSlider
var _font_label: Label
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
	min_size = Vector2i(500, 600)
	size = Vector2i(540, 760)
	_build_ui()
	refresh()


func popup_prefs() -> void:
	refresh()
	popup_centered()


func refresh() -> void:
	_applying = true
	_sync_scheme()
	_rebuild_bindings()
	if _scale:
		_scale.value = Settings.coerce_ui_scale(Settings.ui_scale)
	_sync_scale_label()
	if _font:
		_font.value = Settings.coerce_ui_font_size(Settings.ui_font_size)
	_sync_font_label()
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

	box.add_child(_heading("Key bindings"))
	_build_bindings(box)

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

	box.add_child(_heading("Text size"))
	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 8)
	box.add_child(font_row)
	_font = HSlider.new()
	_font.name = "FontSize"
	_font.min_value = Settings.UI_FONT_SIZE_MIN
	_font.max_value = Settings.UI_FONT_SIZE_MAX
	_font.step = 1
	_font.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font.tooltip_text = "Base text size in points (%d–%d). Independent of UI scale." % [
		Settings.UI_FONT_SIZE_MIN, Settings.UI_FONT_SIZE_MAX,
	]
	_font.value_changed.connect(_on_font_size)
	font_row.add_child(_font)
	_font_label = Label.new()
	_font_label.name = "FontSizeValue"
	_font_label.custom_minimum_size = Vector2(48, 0)
	font_row.add_child(_font_label)

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


func _build_bindings(box: VBoxContainer) -> void:
	_bindings = Tree.new()
	_bindings.name = "Bindings"
	_bindings.columns = 2
	_bindings.column_titles_visible = true
	_bindings.set_column_title(0, "Action")
	_bindings.set_column_title(1, "Shortcut")
	_bindings.set_column_expand(1, false)
	_bindings.set_column_custom_minimum_width(1, 140)
	_bindings.hide_root = true
	_bindings.allow_rmb_select = false
	_bindings.custom_minimum_size = Vector2(0, 220)
	_bindings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bindings.item_activated.connect(_begin_capture)
	_bindings.item_selected.connect(_on_binding_selected)
	box.add_child(_bindings)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_btn_rebind = _bind_button("Rebind…", "RebindKey",
		"Press the next chord to bind it to the selected action")
	_btn_rebind.pressed.connect(_begin_capture)
	row.add_child(_btn_rebind)
	_btn_clear = _bind_button("Clear", "ClearKey",
		"Leave the selected action with no shortcut")
	_btn_clear.pressed.connect(_clear_selected)
	row.add_child(_btn_clear)
	_btn_reset = _bind_button("Reset", "ResetKey",
		"Restore the shipped shortcut for the selected action")
	_btn_reset.pressed.connect(_reset_selected)
	row.add_child(_btn_reset)
	_btn_reset_all = _bind_button("Reset all", "ResetAllKeys",
		"Restore every shortcut in this scheme")
	_btn_reset_all.pressed.connect(_reset_all_bindings)
	row.add_child(_btn_reset_all)

	_confirm_row = HBoxContainer.new()
	_confirm_row.name = "ConfirmRow"
	_confirm_row.add_theme_constant_override("separation", 8)
	_confirm_row.visible = false
	box.add_child(_confirm_row)
	var reassign := _bind_button("Reassign", "ConfirmRebind",
		"Take the chord and unbind whatever holds it")
	reassign.pressed.connect(_confirm_pending)
	_confirm_row.add_child(reassign)
	var keep := _bind_button("Cancel", "CancelRebind", "Leave both bindings alone")
	keep.pressed.connect(_cancel_pending)
	_confirm_row.add_child(keep)

	_binding_status = Label.new()
	_binding_status.name = "BindingStatus"
	_binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_binding_status.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	box.add_child(_binding_status)


func _bind_button(caption: String, node_name: String, tip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = caption
	b.tooltip_text = tip
	return b


## Category → action rows for the active scheme. Reads the registry, so an
## action another feature registered shows up without touching this file.
func _rebuild_bindings() -> void:
	if _bindings == null:
		return
	var keep := _selected_action()
	_bindings.clear()
	var root := _bindings.create_item()
	var scheme := Keymap.active_scheme()
	for raw_category in Keymap.categories():
		var category := str(raw_category)
		var head := _bindings.create_item(root)
		head.set_text(0, category)
		head.set_selectable(0, false)
		head.set_selectable(1, false)
		for raw_action in Keymap.actions_in(category):
			var action := str(raw_action)
			var item := _bindings.create_item(head)
			item.set_text(0, Keymap.action_label(action))
			item.set_tooltip_text(0, Keymap.action_tooltip(action))
			item.set_metadata(0, action)
			item.set_text(1, Keymap.format_action(action, scheme))
			item.set_selectable(1, false)
			if Keymap.has_override(action, scheme):
				item.set_custom_color(1, DarkTheme.token("accent_hover"))
				item.set_tooltip_text(1, "Custom — default is %s" % Keymap.format_binding(
					Keymap.default_binding(action, scheme)
				))
			if action == keep:
				item.select(0)


func _selected_action() -> String:
	if _bindings == null:
		return ""
	var item := _bindings.get_selected()
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(0)
	return str(meta) if meta != null else ""


func _on_binding_selected() -> void:
	if _capture_action.is_empty() and _pending_action.is_empty():
		_set_status(Keymap.action_tooltip(_selected_action()))


## Arm capture: the next non-modifier keypress becomes the new chord.
func _begin_capture() -> void:
	var action := _selected_action()
	if action.is_empty():
		_set_status("pick an action first")
		return
	_cancel_pending()
	_capture_action = action
	set_process_input(true)
	_set_status("press a chord for %s — Esc cancels" % Keymap.action_label(action))


func _end_capture() -> void:
	_capture_action = ""
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if _capture_action.is_empty():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	_capture_key(k)


## Seam the tests drive: everything from here down is scheme logic, not input
## plumbing.
func _capture_key(k: InputEventKey) -> void:
	if _capture_action.is_empty():
		return
	if KeyAction.is_modifier_key(k.keycode):
		return
	var action := _capture_action
	_end_capture()
	if k.keycode == KEY_ESCAPE:
		_set_status("rebind cancelled")
		return
	_offer_binding(action, KeyAction.chord_from_event(k))


## Bind when the chord is free; park it behind a named clash when it is not.
## Returns the clash line, "" when the binding went through.
func _offer_binding(action: String, chord: Dictionary) -> String:
	var scheme := Keymap.active_scheme()
	var clash := Keymap.conflict_text(action, chord, scheme)
	if clash.is_empty():
		_commit_binding(action, chord)
		return ""
	_pending_action = action
	_pending_chord = chord
	_show_confirm(true)
	_set_status("%s. Reassign it to %s?" % [clash, Keymap.action_label(action)])
	return clash


func _confirm_pending() -> void:
	if _pending_action.is_empty():
		return
	var scheme := Keymap.active_scheme()
	var action := _pending_action
	var chord := _pending_chord.duplicate()
	for other in Keymap.conflicts_with(action, chord, scheme):
		Keymap.unbind(str(other), scheme)
		EditorFeedback.log("%s unbound — %s took its chord" % [
			Keymap.action_label(str(other)), Keymap.action_label(action),
		])
	_clear_pending()
	_commit_binding(action, chord)


func _cancel_pending() -> void:
	if _pending_action.is_empty():
		return
	_clear_pending()
	_set_status("binding unchanged")


func _clear_pending() -> void:
	_pending_action = ""
	_pending_chord = {}
	_show_confirm(false)


func _show_confirm(on: bool) -> void:
	if _confirm_row:
		_confirm_row.visible = on


func _commit_binding(action: String, chord: Dictionary) -> void:
	if not Keymap.set_binding(action, chord, Keymap.active_scheme()):
		_set_status("cannot bind %s" % action)
		return
	_after_binding_change()
	_set_status("%s → %s" % [
		Keymap.action_label(action), Keymap.format_binding(chord),
	])
	EditorFeedback.log("bound %s to %s" % [action, Keymap.format_binding(chord)])


func _clear_selected() -> void:
	var action := _selected_action()
	if action.is_empty():
		_set_status("pick an action first")
		return
	_cancel_pending()
	Keymap.unbind(action, Keymap.active_scheme())
	_after_binding_change()
	_set_status("%s has no shortcut" % Keymap.action_label(action))


func _reset_selected() -> void:
	var action := _selected_action()
	if action.is_empty():
		_set_status("pick an action first")
		return
	_cancel_pending()
	Keymap.reset_binding(action, Keymap.active_scheme())
	_after_binding_change()
	_set_status("%s → %s (default)" % [
		Keymap.action_label(action), Keymap.format_action(action),
	])


func _reset_all_bindings() -> void:
	_cancel_pending()
	var scheme := Keymap.active_scheme()
	Keymap.reset_all(scheme)
	_after_binding_change()
	_set_status("every %s shortcut is back to default" % Keymap.scheme_label(scheme))
	EditorFeedback.log("keymap reset to %s defaults" % Keymap.scheme_label(scheme))


func _after_binding_change() -> void:
	_rebuild_bindings()
	_refresh_keymap_views()


func _set_status(text: String) -> void:
	if _binding_status:
		_binding_status.text = text


func binding_status() -> String:
	return _binding_status.text if _binding_status else ""


## Tooltips and the help window quote chords, so they go stale on a rebind.
func _refresh_keymap_views() -> void:
	var shell := _shell()
	if shell == null:
		return
	var help: Variant = shell.get("_help")
	if help != null and help.has_method("refresh"):
		help.call("refresh")
	var top: Variant = shell.get("_top")
	if top != null and top.has_method("refresh_keymap"):
		top.call("refresh_keymap")
	var rail: Variant = shell.get("_rail")
	if rail != null and rail.has_method("refresh_keymap"):
		rail.call("refresh_keymap")


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
	_cancel_pending()
	_rebuild_bindings()


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


func _on_font_size(v: float) -> void:
	if _applying:
		return
	var next := Settings.coerce_ui_font_size(int(round(v)))
	if Settings.ui_font_size == next:
		_sync_font_label()
		return
	Settings.ui_font_size = next
	Settings.save()
	_apply_theme()
	_sync_font_label()
	EditorFeedback.log("ui font size %d" % next)


## Font size lives in the Theme, so the theme has to be rebuilt and reseated
## on the root Control; every panel inherits from there.
func _apply_theme() -> void:
	var shell := _shell()
	if shell is Control:
		DarkTheme.apply_to(shell as Control)
	theme = DarkTheme.make()


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


func _sync_font_label() -> void:
	if _font_label:
		_font_label.text = "%d pt" % Settings.coerce_ui_font_size(Settings.ui_font_size)


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
