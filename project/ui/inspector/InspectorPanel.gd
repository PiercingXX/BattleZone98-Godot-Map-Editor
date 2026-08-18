extends PanelContainer
## Object fields, pin-height, water line.

signal apply_requested(edits: Array)
signal delete_requested
signal water_changed(level: float)

@onready var _prj: LineEdit = %Prj
@onready var _label: LineEdit = %Label
@onready var _x: SpinBox = %X
@onready var _y: SpinBox = %Y
@onready var _z: SpinBox = %Z
@onready var _yaw: SpinBox = %Yaw
@onready var _team: SpinBox = %Team
@onready var _pin: CheckBox = %PinHeight
@onready var _mode: Label = %Mode
@onready var _water: SpinBox = %Water
@onready var _apply: Button = %Apply
@onready var _delete: Button = %Delete

var _shown: Dictionary = {}
var _syncing_water: bool = false
var _syncing_fields: bool = false
var _water_before: float = -1.0
var _water_pending: bool = false
var _water_timer: Timer
var _dirty: Dictionary = {}


func _ready() -> void:
	_apply.pressed.connect(_on_apply)
	_delete.pressed.connect(_on_delete)
	_water.value_changed.connect(_on_water)
	_pin.toggled.connect(_on_pin_toggled)
	_label.text_submitted.connect(func(_t): _on_apply())
	_label.text_changed.connect(func(_t: String) -> void: _mark_dirty("label"))
	_x.value_changed.connect(func(_v: float) -> void: _mark_dirty("x"))
	_y.value_changed.connect(func(_v: float) -> void: _mark_dirty("y"))
	_z.value_changed.connect(func(_v: float) -> void: _mark_dirty("z"))
	_yaw.value_changed.connect(func(_v: float) -> void: _mark_dirty("yaw"))
	_team.value_changed.connect(func(_v: float) -> void: _mark_dirty("team"))
	MapState.water_changed.connect(_on_water_state)
	MapState.session_changed.connect(_on_session)
	_water_timer = Timer.new()
	_water_timer.one_shot = true
	_water_timer.wait_time = 0.35
	_water_timer.timeout.connect(commit_water)
	add_child(_water_timer)
	_refresh_fields()


func _exit_tree() -> void:
	commit_water()


func show_object(rec: Dictionary) -> void:
	_shown = rec.duplicate(true)
	if rec.is_empty():
		clear()
		return
	_syncing_fields = true
	_prj.text = str(rec.get("prjid", ""))
	_label.text = str(rec.get("label", ""))
	_x.value = float(rec.get("x", 0.0))
	_y.value = float(rec.get("y", 0.0))
	_z.value = float(rec.get("z", 0.0))
	_yaw.value = float(rec.get("yaw_deg", 0.0))
	_team.value = int(rec.get("team", 0))
	_pin.button_pressed = bool(rec.get("pinned_y", false))
	var extra := ""
	if MapState.selected_ids.size() > 1:
		extra = "  ·  %d selected" % MapState.selected_ids.size()
	_mode.text = "%s  ·  %s%s" % [
		rec.get("placement_mode", "bzn"),
		"required" if rec.get("required", false) else rec.get("id", ""),
		extra,
	]
	_syncing_fields = false
	_dirty.clear()
	_refresh_fields()


func clear() -> void:
	_shown = {}
	_dirty.clear()
	_syncing_fields = true
	_prj.text = ""
	_label.text = ""
	_x.value = 0.0
	_y.value = 0.0
	_z.value = 0.0
	_yaw.value = 0.0
	_team.value = 0
	_pin.button_pressed = false
	_mode.text = "nothing selected"
	_syncing_fields = false
	_refresh_fields()


func set_water(level: float) -> void:
	_syncing_water = true
	_water.value = level
	_syncing_water = false
	_refresh_fields()


func is_field_dirty(field: String) -> bool:
	if _shown.is_empty():
		return false
	# Prefer a live compare so scripted widget writes (and change-then-revert)
	# match what Apply will actually send. Signals still mark _dirty.
	match field:
		"label":
			return _label.text != str(_shown.get("label", ""))
		"x":
			return not is_equal_approx(_x.value, float(_shown.get("x", 0.0)))
		"y":
			return not is_equal_approx(_y.value, float(_shown.get("y", 0.0)))
		"z":
			return not is_equal_approx(_z.value, float(_shown.get("z", 0.0)))
		"yaw":
			return not is_equal_approx(_yaw.value, float(_shown.get("yaw_deg", 0.0)))
		"team":
			return int(_team.value) != int(_shown.get("team", 0))
		"pin":
			return _pin.button_pressed != bool(_shown.get("pinned_y", false))
	return bool(_dirty.get(field, false))


func _on_session() -> void:
	if not MapState.has_session:
		clear()
		_water_pending = false
		if _water_timer:
			_water_timer.stop()
	set_water(MapState.water_level())
	_refresh_fields()


func _on_water(v: float) -> void:
	if _syncing_water:
		return
	if not MapState.has_session:
		EditorFeedback.log("open a map to set water")
		set_water(MapState.water_level())
		return
	if not _water_pending:
		_water_before = MapState.water_level()
		_water_pending = true
	MapState.set_water_level(v)
	water_changed.emit(v)
	_water_timer.start()


func commit_water() -> void:
	if not _water_pending:
		return
	_water_pending = false
	if _water_timer:
		_water_timer.stop()
	if not MapState.has_session:
		return
	var after := MapState.water_level()
	if is_equal_approx(_water_before, after):
		return
	var cmd := WaterCommand.new()
	cmd.before = _water_before
	cmd.after = after
	UndoStack.push(cmd, true)


func _on_water_state(level: float) -> void:
	set_water(level)


func _on_pin_toggled(_on: bool) -> void:
	if _syncing_fields:
		return
	if _shown.is_empty():
		return
	_mark_dirty("pin")
	if not _pin.button_pressed and MapState.field != null:
		_syncing_fields = true
		_y.value = MapState.field.height_at(float(_x.value), float(_z.value))
		_syncing_fields = false
	_refresh_fields()


func _on_delete() -> void:
	if _shown.is_empty():
		EditorFeedback.log("nothing selected")
		return
	if bool(_shown.get("required", false)):
		EditorFeedback.log("player object is undeletable")
		return
	delete_requested.emit()


func _on_apply() -> void:
	if _shown.is_empty():
		EditorFeedback.log("nothing selected")
		return
	if not MapState.has_session:
		EditorFeedback.log("open a map first")
		return
	var ids := _apply_ids()
	var multi := ids.size() > 1
	if multi and not _any_dirty():
		EditorFeedback.log("no inspector changes to apply")
		return
	var edits: Array = []
	for id in ids:
		var rec := _record_for_apply(id, multi)
		if rec.is_empty():
			continue
		var before := rec.duplicate(true)
		var after := _compose_after(before, multi)
		if not _edits_match(before, after):
			edits.append({"before": before, "after": after})
	if edits.is_empty():
		EditorFeedback.log("no inspector changes to apply")
		return
	apply_requested.emit(edits)
	_shown = edits[0]["after"].duplicate(true)
	_dirty.clear()
	var n := edits.size()
	EditorFeedback.log("applied inspector edits to %d object%s" % [n, "s" if n != 1 else ""])


func _apply_ids() -> Array[String]:
	var ids: Array[String] = MapState.selected_ids.duplicate()
	if ids.is_empty():
		var sid := str(_shown.get("id", ""))
		if not sid.is_empty():
			ids.append(sid)
	return ids


func _record_for_apply(id: String, multi: bool) -> Dictionary:
	var rec := MapState.find_object(id)
	if not rec.is_empty():
		return rec
	if not multi and str(_shown.get("id", "")) == id:
		return _shown
	if not multi and MapState.selected_ids.is_empty():
		return _shown
	return {}


func _compose_after(before: Dictionary, multi: bool) -> Dictionary:
	var after := before.duplicate(true)
	if not multi:
		after["label"] = _label.text
		after["x"] = _x.value
		after["z"] = _z.value
		after["yaw_deg"] = _yaw.value
		after["team"] = int(_team.value)
		after["pinned_y"] = _pin.button_pressed
		if _pin.button_pressed:
			after["y"] = _y.value
		else:
			after["y"] = _terrain_y(float(after["x"]), float(after["z"]))
			_syncing_fields = true
			_y.value = float(after["y"])
			_syncing_fields = false
		return after
	if is_field_dirty("x"):
		after["x"] = _x.value
	if is_field_dirty("z"):
		after["z"] = _z.value
	if is_field_dirty("yaw"):
		after["yaw_deg"] = _yaw.value
	if is_field_dirty("team"):
		after["team"] = int(_team.value)
	if is_field_dirty("pin"):
		after["pinned_y"] = _pin.button_pressed
	# y applies only when pin height is on, and only if the user edited it.
	if _pin.button_pressed and is_field_dirty("y"):
		after["y"] = _y.value
		after["pinned_y"] = true
	elif not bool(after.get("pinned_y", false)):
		if is_field_dirty("x") or is_field_dirty("z") or (is_field_dirty("pin") and not _pin.button_pressed):
			after["y"] = _terrain_y(float(after["x"]), float(after["z"]))
	return after


func _terrain_y(x: float, z: float) -> float:
	if MapState.field == null:
		return 0.0
	return MapState.field.height_at(x, z)


func _any_dirty() -> bool:
	for field in ["label", "x", "y", "z", "yaw", "team", "pin"]:
		if is_field_dirty(field):
			return true
	return false


func _mark_dirty(field: String) -> void:
	if _syncing_fields or _shown.is_empty():
		return
	_dirty[field] = true


func _edits_match(a: Dictionary, b: Dictionary) -> bool:
	return (
		str(a.get("label", "")) == str(b.get("label", ""))
		and is_equal_approx(float(a.get("x", 0.0)), float(b.get("x", 0.0)))
		and is_equal_approx(float(a.get("y", 0.0)), float(b.get("y", 0.0)))
		and is_equal_approx(float(a.get("z", 0.0)), float(b.get("z", 0.0)))
		and is_equal_approx(float(a.get("yaw_deg", 0.0)), float(b.get("yaw_deg", 0.0)))
		and int(a.get("team", 0)) == int(b.get("team", 0))
		and bool(a.get("pinned_y", false)) == bool(b.get("pinned_y", false))
	)


func _refresh_fields() -> void:
	var has := not _shown.is_empty()
	var session := MapState.has_session
	var multi := MapState.selected_ids.size() > 1
	var label_ok := has and not multi
	_label.editable = label_ok
	if not has:
		_label.tooltip_text = "Nothing selected"
	elif multi:
		_label.tooltip_text = "Label applies to one object at a time"
	else:
		_label.tooltip_text = "Object label"
	_x.editable = has
	_z.editable = has
	_yaw.editable = has
	_team.editable = has
	var locked := "Nothing selected"
	_x.tooltip_text = "" if has else locked
	_z.tooltip_text = "" if has else locked
	_yaw.tooltip_text = "" if has else locked
	_team.tooltip_text = "" if has else locked
	_pin.disabled = not has
	_pin.tooltip_text = "Keep Y off the terrain" if has else locked
	_y.editable = has and _pin.button_pressed
	if not has:
		_y.tooltip_text = locked
	elif not _pin.button_pressed:
		_y.tooltip_text = "Pin height to edit Y"
	else:
		_y.tooltip_text = "Pinned height"
	_apply.disabled = not has
	if not has:
		_apply.tooltip_text = "Nothing selected"
	elif multi:
		_apply.tooltip_text = "Apply changed fields to all %d selected" % MapState.selected_ids.size()
	else:
		_apply.tooltip_text = "Apply position / label / team"
	var required := has and bool(_shown.get("required", false))
	_delete.disabled = not has or required
	if required:
		_delete.tooltip_text = "Player object is undeletable"
	elif has:
		_delete.tooltip_text = "Delete selected  (Del)"
	else:
		_delete.tooltip_text = "Nothing selected"
	_water.editable = session
	_water.tooltip_text = "Water line (−1 = none)" if session else "Open a map first"
	if _prj:
		_prj.editable = false
