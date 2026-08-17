extends PanelContainer
## Validation findings. Single click selects; double-click flies.

signal finding_selected(f: Dictionary)
signal finding_activated(f: Dictionary)
signal validate_requested

@onready var _list: ItemList = %List

const _SEVERITY := {
	"error": Color(0.95, 0.38, 0.34),
	"critical": Color(0.95, 0.38, 0.34),
	"warning": Color(0.95, 0.74, 0.28),
	"warn": Color(0.95, 0.74, 0.28),
	"info": Color(0.70, 0.74, 0.80),
	"note": Color(0.70, 0.74, 0.80),
}


func _ready() -> void:
	%Validate.pressed.connect(func(): validate_requested.emit())
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(_on_activated)


func set_findings(list: Array, stale: bool) -> void:
	_list.clear()
	var prefix := ""
	if stale:
		prefix = "(stale) "
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


func _on_selected(index: int) -> void:
	var f = _list.get_item_metadata(index)
	if typeof(f) == TYPE_DICTIONARY:
		finding_selected.emit(f)


func _on_activated(index: int) -> void:
	var f = _list.get_item_metadata(index)
	if typeof(f) == TYPE_DICTIONARY:
		finding_activated.emit(f)
