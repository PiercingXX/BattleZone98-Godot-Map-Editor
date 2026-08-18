extends VBoxContainer
class_name LogConsole
## Filterable BBCode console. `.text` is the full plain log (no tags).

const FILTER_ALL := "all"
const FILTER_WARNING := "warning"
const FILTER_ERROR := "error"

var _entries: Array = []
var _filter: String = FILTER_ALL
var _body: RichTextLabel
var _btn_all: Button
var _btn_warn: Button
var _btn_err: Button
var _copy: Button
var _ready_ui: bool = false

var text: String:
	get:
		return _joined_plain()
	set(value):
		_replace_from_plain(value)

var scroll_vertical: int = 0:
	set(value):
		scroll_vertical = value
		_scroll_to(value)


func _ready() -> void:
	_build_ui()
	_rebuild()


func append_line(msg: String, level: String = "") -> void:
	var lv := LogRouter.infer_level(msg, level)
	_entries.append({"text": msg, "level": lv})
	_rebuild()
	_scroll_to(_entries.size())


func get_line_count() -> int:
	return _entries.size()


func set_filter(name: String) -> void:
	var next := name.strip_edges().to_lower()
	if next != FILTER_ALL and next != FILTER_WARNING and next != FILTER_ERROR:
		next = FILTER_ALL
	if _filter == next:
		_sync_filter_buttons()
		return
	_filter = next
	_sync_filter_buttons()
	_rebuild()


func current_filter() -> String:
	return _filter


func visible_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for entry in _entries:
		if _passes(str(entry.get("level", LogRouter.LEVEL_INFO))):
			lines.append(str(entry.get("text", "")))
	return "\n".join(lines)


func copy_visible() -> String:
	var clipped := visible_text()
	DisplayServer.clipboard_set(clipped)
	return clipped


func _build_ui() -> void:
	if _ready_ui:
		return
	_ready_ui = true
	add_theme_constant_override("separation", 4)
	var bar := HBoxContainer.new()
	bar.name = "LogToolbar"
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	var group := ButtonGroup.new()
	_btn_all = _make_filter_button("All", FILTER_ALL, group)
	_btn_warn = _make_filter_button("Warnings", FILTER_WARNING, group)
	_btn_err = _make_filter_button("Errors", FILTER_ERROR, group)
	bar.add_child(_btn_all)
	bar.add_child(_btn_warn)
	bar.add_child(_btn_err)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_copy = Button.new()
	_copy.name = "Copy"
	_copy.text = "Copy"
	_copy.tooltip_text = "Copy the visible log lines"
	_copy.pressed.connect(_on_copy)
	bar.add_child(_copy)
	_body = RichTextLabel.new()
	_body.name = "Body"
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.scroll_following = true
	_body.selection_enabled = true
	_body.focus_mode = Control.FOCUS_CLICK
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, 96)
	add_child(_body)
	_sync_filter_buttons()


func _make_filter_button(caption: String, id: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.name = caption
	b.text = caption
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): set_filter(id))
	return b


func _on_copy() -> void:
	copy_visible()


func _joined_plain() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for entry in _entries:
		lines.append(str(entry.get("text", "")))
	return "\n".join(lines)


func _replace_from_plain(value: String) -> void:
	_entries.clear()
	if not value.is_empty():
		for line in value.split("\n"):
			_entries.append({
				"text": line,
				"level": LogRouter.infer_level(line, ""),
			})
	_rebuild()


func _passes(level: String) -> bool:
	match _filter:
		FILTER_ERROR:
			return level == LogRouter.LEVEL_ERROR
		FILTER_WARNING:
			return level == LogRouter.LEVEL_WARNING or level == LogRouter.LEVEL_ERROR
		_:
			return true


func _rebuild() -> void:
	if _body == null:
		return
	_body.clear()
	for entry in _entries:
		var lv := str(entry.get("level", LogRouter.LEVEL_INFO))
		if not _passes(lv):
			continue
		_body.append_text(LogRouter.bbcode_line(str(entry.get("text", "")), lv))
		_body.append_text("\n")
	_scroll_to(_entries.size())


func _scroll_to(line: int) -> void:
	if _body == null:
		return
	var last := maxi(_body.get_line_count() - 1, 0)
	_body.scroll_to_line(clampi(line, 0, last))


func _sync_filter_buttons() -> void:
	if _btn_all:
		_btn_all.set_pressed_no_signal(_filter == FILTER_ALL)
	if _btn_warn:
		_btn_warn.set_pressed_no_signal(_filter == FILTER_WARNING)
	if _btn_err:
		_btn_err.set_pressed_no_signal(_filter == FILTER_ERROR)
