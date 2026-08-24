extends PanelContainer
## Sun clock and fog — the `.trn` `[NormalView]` block, as controls.
##
## Everything here is map data except the fog checkbox, which is an editor
## visibility toggle: the distances are saved whether or not you draw them.

@onready var _box: VBoxContainer = %Box

var _time: HSlider
var _time_label: Label
var _fog_show: CheckBox
var _fog_start: HSlider
var _fog_end: HSlider
var _fog_break: HSlider
var _fog_start_val: Label
var _fog_end_val: Label
var _fog_break_val: Label
var _fog_color: ColorPickerButton
var _visibility: Label
var _syncing: bool = false
var _time_dragging: bool = false
var _fog_end_dragging: bool = false


func _ready() -> void:
	_build()
	var icon := find_child("TitleIcon", true, false)
	if icon is TextureRect and (icon as TextureRect).texture == null:
		(icon as TextureRect).texture = EditorIcons.texture("view")
	MapState.session_changed.connect(refresh)
	MapState.world_changed.connect(refresh)
	refresh()


func _build() -> void:
	_box.add_child(_heading("Sun"))
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	_box.add_child(time_row)
	_time = HSlider.new()
	_time.name = "SunTime"
	_time.min_value = 0
	_time.max_value = WorldLighting.MINUTES_PER_DAY - 1
	_time.step = 5
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time.tooltip_text = (
		"The .trn Time= value. 06:00 puts the sun on the eastern horizon, "
		+ "12:00 overhead, 18:00 on the western horizon."
	)
	_time.value_changed.connect(_on_time)
	_time.drag_started.connect(func() -> void: _time_dragging = true)
	_time.drag_ended.connect(_on_time_drag_ended)
	time_row.add_child(_time)
	_time_label = Label.new()
	_time_label.name = "SunTimeValue"
	_time_label.custom_minimum_size = Vector2(96, 0)
	time_row.add_child(_time_label)

	_box.add_child(_heading("Fog"))
	_fog_show = CheckBox.new()
	_fog_show.name = "ShowFog"
	_fog_show.text = "Preview in viewport"
	_fog_show.focus_mode = Control.FOCUS_NONE
	_fog_show.tooltip_text = (
		"Preview only, off by default — game fog is too close in to sculpt "
		+ "through. The map's fog is saved either way."
	)
	_fog_show.toggled.connect(_on_show_fog)
	_box.add_child(_fog_show)
	_fog_start = _distance_slider(
		"FogStart", "Start", "Where the fog begins."
	)
	_fog_start_val = _fog_start.get_meta("value_label") as Label
	_fog_start.value_changed.connect(func(v: float): _on_fog("fog_start_m", v))
	_fog_end = _distance_slider(
		"FogEnd", "End", "Full fog, and what VisibilityRange follows."
	)
	_fog_end_val = _fog_end.get_meta("value_label") as Label
	_fog_end.value_changed.connect(_on_fog_end_value)
	_fog_end.drag_started.connect(func() -> void: _fog_end_dragging = true)
	_fog_end.drag_ended.connect(_on_fog_end_drag_ended)
	_fog_break = _distance_slider(
		"FogBreak", "Break", "The .trn FogBreak distance, saved as written."
	)
	_fog_break_val = _fog_break.get_meta("value_label") as Label
	_fog_break.value_changed.connect(func(v: float): _on_fog("fog_break_m", v))

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	_box.add_child(color_row)
	var color_cap := Label.new()
	color_cap.text = "Colour"
	color_row.add_child(color_cap)
	_fog_color = ColorPickerButton.new()
	_fog_color.name = "FogColor"
	_fog_color.edit_alpha = false
	_fog_color.custom_minimum_size = Vector2(64, 0)
	_fog_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fog_color.tooltip_text = (
		"Redux has no fog-colour key. Saving writes the map its own .act "
		+ "palette and points [Color] Palette at it."
	)
	_fog_color.color_changed.connect(_on_fog_color)
	color_row.add_child(_fog_color)

	_visibility = Label.new()
	_visibility.name = "VisibilityNote"
	_visibility.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_visibility.add_theme_color_override("font_color", Color(0.62, 0.62, 0.64, 1))
	_box.add_child(_visibility)


func _heading(caption: String) -> Label:
	var l := Label.new()
	l.text = caption
	l.add_theme_color_override("font_color", Color(0.78, 0.80, 0.84))
	return l


func _distance_slider(node_name: String, caption: String, tip: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var cap := Label.new()
	cap.text = caption
	row.add_child(cap)
	var s := HSlider.new()
	s.name = node_name
	s.min_value = WorldLighting.FOG_MIN_M
	s.max_value = WorldLighting.FOG_MAX_M
	s.step = 1.0
	s.tooltip_text = tip
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var val := Label.new()
	val.name = node_name + "Value"
	val.custom_minimum_size = Vector2(56, 0)
	row.add_child(val)
	s.set_meta("value_label", val)
	return s


func refresh() -> void:
	if _time == null:
		return
	_syncing = true
	var live := MapState.has_session
	var w: Dictionary = MapState.world_settings()
	if not _time_dragging:
		_time.value = WorldLighting.minutes_from_time(w.get("time", WorldLighting.TIME_DEFAULT))
	_fog_start.value = float(w.get("fog_start_m", WorldLighting.FOG_START_DEFAULT))
	if not _fog_end_dragging:
		_fog_end.value = float(w.get("fog_end_m", WorldLighting.FOG_END_DEFAULT))
	_fog_break.value = float(w.get("fog_break_m", WorldLighting.FOG_BREAK_DEFAULT))
	_fog_color.color = MapState.fog_color()
	_fog_show.set_pressed_no_signal(Settings.view_fog)
	_time.editable = live
	_fog_start.editable = live
	_fog_end.editable = live
	_fog_break.editable = live
	_fog_color.disabled = not live
	_sync_labels()
	_syncing = false


func _sync_labels() -> void:
	var minutes := int(_time.value)
	_time_label.text = "%s · %d" % [
		WorldLighting.format_clock(minutes), WorldLighting.time_from_minutes(minutes)
	]
	if _fog_start_val:
		_fog_start_val.text = "%d m" % int(_fog_start.value)
	if _fog_end_val:
		_fog_end_val.text = "%d m" % int(_fog_end.value)
	if _fog_break_val:
		_fog_break_val.text = "%d m" % int(_fog_break.value)
	_visibility.text = "VisibilityRange %d m — always FogEnd + %d." % [
		int(round(WorldLighting.visibility_range(_fog_end.value))),
		int(WorldLighting.VISIBILITY_MARGIN_M),
	]


func _on_time(_v: float) -> void:
	_sync_labels()
	if _syncing:
		return
	# Live while dragging: the light is the readout. Only the map edit waits
	# for release, so a drag is one undo-worthy change, not three hundred.
	_preview_sun()
	if not _time_dragging:
		_commit_time()


func _on_time_drag_ended(_changed: bool) -> void:
	_time_dragging = false
	_commit_time()


func _commit_time() -> void:
	if not MapState.has_session:
		refresh()
		return
	var next := WorldLighting.time_from_minutes(int(_time.value))
	if int(MapState.world_setting("time")) == next:
		return
	MapState.set_world_setting("time", next)
	EditorFeedback.log("sun time %s (Time=%d)" % [
		WorldLighting.format_clock(int(_time.value)), next
	])


func _preview_sun() -> void:
	var shell := get_tree().get_first_node_in_group("editor_shell")
	if shell != null and shell.has_method("preview_sun_minutes"):
		shell.preview_sun_minutes(int(_time.value))


func _on_fog_end_value(v: float) -> void:
	_sync_labels()
	if _syncing:
		return
	# Live-update while FogEnd stays at or past FogStart. The FogEnd < FogStart
	# clamp waits for mouse release so MapState does not pull FogStart down.
	if v < _fog_start.value:
		return
	_on_fog("fog_end_m", v)


func _on_fog_end_drag_ended(_changed: bool) -> void:
	_fog_end_dragging = false
	if _fog_end.value < _fog_start.value:
		var was := _syncing
		_syncing = true
		_fog_end.value = _fog_start.value
		_syncing = was
		_sync_labels()
	if not MapState.has_session:
		return
	_on_fog("fog_end_m", _fog_end.value)


func _on_fog(key: String, value: float) -> void:
	if _syncing:
		return
	if not MapState.has_session:
		refresh()
		return
	MapState.set_world_setting(key, value)
	refresh()


func _on_fog_color(c: Color) -> void:
	if _syncing:
		return
	if not MapState.has_session:
		refresh()
		return
	MapState.set_world_setting("fog_color", c.to_html(false))


func _on_show_fog(on: bool) -> void:
	if _syncing:
		return
	Settings.view_fog = on
	MapState.world_changed.emit()
	EditorFeedback.log("view fog %s" % ("on" if on else "off"))
