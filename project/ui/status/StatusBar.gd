extends PanelContainer
## Single owner of the status label, plus cursor / map / fps / log.

signal log_toggled(on: bool)

var _kind: String = "info"

@onready var _cursor: Label = %Cursor
@onready var _map: Label = %MapInfo
@onready var _status: Label = %Status
@onready var _debug: Label = %Debug
@onready var _log: Button = %Log


func _ready() -> void:
	_log.toggled.connect(func(on): log_toggled.emit(on))
	set_status("info", "starting")


func set_status(kind: String, text: String) -> void:
	if kind == "transient" and _kind in ["busy", "error"]:
		return
	_kind = kind
	_status.text = text
	if kind == "error":
		_status.add_theme_color_override("font_color", Color(0.95, 0.35, 0.32))
	else:
		_status.remove_theme_color_override("font_color")


func set_cursor(text: String) -> void:
	_cursor.text = text


func set_map_info(text: String) -> void:
	_map.text = text


func set_debug(text: String) -> void:
	_debug.text = text


func set_log_visible(on: bool) -> void:
	_log.set_pressed_no_signal(on)
