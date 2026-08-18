extends Control
class_name StartScreen
## Viewport-area overlay shown when no session is open.

signal new_requested
signal open_requested
signal gallery_requested
signal recent_open_requested(path: String)
signal template_requested(trn: String)

const HINTS: PackedStringArray = [
	"Open a map to start editing.",
	"Probe finds your Battlezone install.",
	"F1 lists hotkeys.",
]

@onready var _title: Label = %Title
@onready var _version: Label = %Version
@onready var _new: Button = %New
@onready var _open: Button = %Open
@onready var _gallery: Button = %Gallery
@onready var _hints: VBoxContainer = %Hints
@onready var _recents: VBoxContainer = %Recents
@onready var _templates: HBoxContainer = %Templates
@onready var _recents_empty: Label = %RecentsEmpty
@onready var _templates_empty: Label = %TemplatesEmpty


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	_title.text = str(ProjectSettings.get_setting(
		"application/config/name", "BattleZone 98 Godot Map Editor"
	))
	var ver := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	_version.text = ("v%s" % ver) if not ver.is_empty() else ""
	_new.pressed.connect(func() -> void: new_requested.emit())
	_open.pressed.connect(func() -> void: open_requested.emit())
	_gallery.pressed.connect(func() -> void: gallery_requested.emit())
	_new.tooltip_text = "New map"
	_open.tooltip_text = "Open a map"
	_gallery.tooltip_text = "Browse maps in the gallery"
	EditorIcons.apply_button(_new, "new", true)
	EditorIcons.apply_button(_open, "open", true)
	EditorIcons.apply_button(_gallery, "view", true)
	_fill_hints()
	if not Backend.call_started.is_connected(_on_backend_busy):
		Backend.call_started.connect(_on_backend_busy)
	if not Backend.call_finished.is_connected(_on_backend_idle):
		Backend.call_finished.connect(_on_backend_idle)
	if not Backend.call_failed.is_connected(_on_backend_fail):
		Backend.call_failed.connect(_on_backend_fail)
	refresh()


func show_start() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	refresh()


func hide_start() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh() -> void:
	if _hints:
		_hints.visible = StartRecents.is_first_run()
	_fill_recents()
	_fill_templates()
	_refresh_busy()


func _fill_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		child.queue_free()
	for line in HINTS:
		var lab := Label.new()
		lab.text = line
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_color_override("font_color", Color(0.62, 0.62, 0.64, 1))
		_hints.add_child(lab)


func _fill_recents() -> void:
	if _recents == null:
		return
	for child in _recents.get_children():
		child.queue_free()
	var entries := StartRecents.entries_from_settings()
	if _recents_empty:
		_recents_empty.visible = entries.is_empty() and not StartRecents.is_first_run()
		if _recents_empty.visible:
			_recents_empty.text = "No recent maps."
	for rec in entries:
		_recents.add_child(_make_recent_row(rec))


func _make_recent_row(rec: Dictionary) -> Button:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 48
	var path := str(rec.get("path", ""))
	var exists := bool(rec.get("exists", false))
	btn.disabled = not exists
	btn.tooltip_text = "file moved" if not exists else path
	btn.text = str(rec.get("caption", path.get_file()))
	var thumb_path := str(rec.get("thumb_path", ""))
	if not thumb_path.is_empty():
		var tex := _load_thumb(thumb_path)
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 56)
	btn.pressed.connect(func() -> void:
		if path.is_empty() or not FileAccess.file_exists(path):
			EditorFeedback.log("file moved")
			return
		recent_open_requested.emit(path)
	)
	return btn


func _fill_templates() -> void:
	if _templates == null:
		return
	for child in _templates.get_children():
		child.queue_free()
	var list: Array = SessionIO.list_templates()
	if _templates_empty:
		_templates_empty.visible = list.is_empty()
	for rec in list:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var name := str(rec.get("name", ""))
		var trn := str(rec.get("trn", ""))
		if name.is_empty() or trn.is_empty():
			continue
		var btn := Button.new()
		btn.text = name
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = "New map from template %s" % name
		btn.pressed.connect(func() -> void: template_requested.emit(trn))
		_templates.add_child(btn)


func _refresh_busy() -> void:
	var busy := Backend.busy
	_set_action(_new, not busy, "New map", "Busy…")
	_set_action(_open, not busy, "Open a map", "Busy…")
	_set_action(_gallery, not busy, "Browse maps in the gallery", "Busy…")
	if _templates:
		for child in _templates.get_children():
			if child is Button:
				_set_action(child as Button, not busy, (child as Button).text, "Busy…")


func _set_action(btn: Button, on: bool, tip: String, why: String) -> void:
	if btn == null:
		return
	btn.disabled = not on
	btn.tooltip_text = tip if on else why


func _on_backend_busy(_verb: String) -> void:
	_refresh_busy()


func _on_backend_idle(_verb: String, _result: Dictionary) -> void:
	_refresh_busy()


func _on_backend_fail(_verb: String, _error: Dictionary) -> void:
	_refresh_busy()


static func _load_thumb(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)
