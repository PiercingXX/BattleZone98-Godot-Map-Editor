extends PanelContainer
## Object fields, pin-height, water line.

signal apply_requested(before: Dictionary, after: Dictionary)
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

var _shown: Dictionary = {}
var _syncing_water: bool = false


func _ready() -> void:
	%Apply.pressed.connect(_on_apply)
	%Delete.pressed.connect(func(): delete_requested.emit())
	_water.value_changed.connect(_on_water)
	MapState.water_changed.connect(_on_water_state)


func show_object(rec: Dictionary) -> void:
	_shown = rec.duplicate(true)
	if rec.is_empty():
		clear()
		return
	_prj.text = str(rec.get("prjid", ""))
	_label.text = str(rec.get("label", ""))
	_x.value = float(rec.get("x", 0.0))
	_y.value = float(rec.get("y", 0.0))
	_z.value = float(rec.get("z", 0.0))
	_yaw.value = float(rec.get("yaw_deg", 0.0))
	_team.value = int(rec.get("team", 0))
	_pin.button_pressed = bool(rec.get("pinned_y", false))
	_mode.text = "%s  ·  %s" % [
		rec.get("placement_mode", "bzn"),
		"required" if rec.get("required", false) else rec.get("id", ""),
	]


func clear() -> void:
	_shown = {}
	_prj.text = ""
	_label.text = ""
	_mode.text = "nothing selected"


func set_water(level: float) -> void:
	_syncing_water = true
	_water.value = level
	_syncing_water = false


func _on_water(v: float) -> void:
	if _syncing_water:
		return
	water_changed.emit(v)


func _on_water_state(level: float) -> void:
	set_water(level)


func _on_apply() -> void:
	if _shown.is_empty():
		return
	var before := _shown.duplicate(true)
	var after := before.duplicate(true)
	after["label"] = _label.text
	after["x"] = _x.value
	after["z"] = _z.value
	after["yaw_deg"] = _yaw.value
	after["team"] = int(_team.value)
	after["pinned_y"] = _pin.button_pressed
	if _pin.button_pressed:
		after["y"] = _y.value
	else:
		after["y"] = MapState.field.height_at(float(_x.value), float(_z.value))
		_y.value = float(after["y"])
	apply_requested.emit(before, after)
	_shown = after.duplicate(true)
