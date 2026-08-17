extends PanelContainer
## Validation findings. Single click selects; double-click flies.

signal finding_selected(f: Dictionary)
signal finding_activated(f: Dictionary)
signal validate_requested

@onready var _list: ItemList = %List
@onready var _validate: Button = %Validate

const _SEVERITY := {
	"error": Color(0.95, 0.38, 0.34),
	"critical": Color(0.95, 0.38, 0.34),
	"warning": Color(0.95, 0.74, 0.28),
	"warn": Color(0.95, 0.74, 0.28),
	"info": Color(0.70, 0.74, 0.80),
	"note": Color(0.70, 0.74, 0.80),
}

var _busy: bool = false
var _empty: bool = true


func _ready() -> void:
	_validate.pressed.connect(_on_validate)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(_on_activated)
	MapState.session_changed.connect(_on_session)
	Backend.call_started.connect(func(_v): _busy = true; _refresh_validate())
	Backend.call_finished.connect(func(_v, _r): _busy = false; _refresh_validate())
	Backend.call_failed.connect(func(_v, _e): _busy = false; _refresh_validate())
	_refresh_validate()
	if _list.item_count == 0:
		set_findings([], false)


func set_findings(list: Array, stale: bool) -> void:
	_list.clear()
	var prefix := ""
	if stale:
		prefix = "(stale) "
	var added := 0
	for f in list:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var sev := str(f.get("severity", ""))
		var title := str(f.get("title", ""))
		var text := "%s%s  %s" % [prefix, sev, title]
		var i := _list.add_item(text)
		_list.set_item_metadata(i, f)
		var col: Color = _SEVERITY.get(sev.to_lower(), Color(0.88, 0.88, 0.90))
		if stale:
			col = col.darkened(0.25)
			col.a = 0.7
		_list.set_item_custom_fg_color(i, col)
		added += 1
	_empty = added == 0
	if _empty:
		var msg := "Open a map, then Validate." if not MapState.has_session else "No findings. Click Validate to check this map."
		if stale and MapState.has_session:
			msg = "(stale) Findings are out of date — Validate again."
		var i := _list.add_item(msg)
		_list.set_item_metadata(i, {})
		_list.set_item_disabled(i, true)
	_refresh_validate()


func _on_session() -> void:
	if not MapState.has_session:
		set_findings([], false)
	_refresh_validate()


func _refresh_validate() -> void:
	if _validate == null:
		return
	var ok := MapState.has_session and not _busy
	_validate.disabled = not ok
	if _busy:
		_validate.tooltip_text = "Busy…"
	elif not MapState.has_session:
		_validate.tooltip_text = "Open a map first"
	else:
		_validate.tooltip_text = "Run validation (not an in-game verdict)"


func _on_validate() -> void:
	if not MapState.has_session:
		EditorFeedback.log("nothing to validate")
		return
	validate_requested.emit()


func _on_selected(index: int) -> void:
	var f = _list.get_item_metadata(index)
	if typeof(f) != TYPE_DICTIONARY or f.is_empty():
		return
	if str(f.get("object_id", "")).is_empty() and f.get("world_pos", null) == null:
		EditorFeedback.log("finding has no object or position to go to")
		return
	finding_selected.emit(f)


func _on_activated(index: int) -> void:
	var f = _list.get_item_metadata(index)
	if typeof(f) != TYPE_DICTIONARY or f.is_empty():
		return
	if str(f.get("object_id", "")).is_empty() and f.get("world_pos", null) == null:
		EditorFeedback.log("finding has no object or position to fly to")
		return
	finding_activated.emit(f)
