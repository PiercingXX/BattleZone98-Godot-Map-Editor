extends Window
## Probe results: installs, warnings, pick a game root.

signal install_chosen(path: String)

@onready var _list: ItemList = %List
@onready var _current: Label = %Current
@onready var _use: Button = %Use

var _paths: Array[String] = []


func _ready() -> void:
	close_requested.connect(hide)
	_use.pressed.connect(_on_use)
	_list.item_selected.connect(func(_i): _use.disabled = _selected_path().is_empty())
	_use.disabled = true


func show_probe(result: Dictionary) -> void:
	_list.clear()
	_paths.clear()
	var installs: Array = result.get("installs", [])
	for item in installs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var kind := str(item.get("kind", ""))
		var path := str(item.get("path", ""))
		var extra := ""
		if kind == "workshop_item":
			extra = "  [%s %s]" % [item.get("id", ""), item.get("source", "")]
			if str(item.get("id", "")) == "3406347034" and Settings.last_map_dir.is_empty():
				Settings.last_map_dir = path
				Settings.save()
		var i := _list.add_item("%s  %s%s" % [kind, path, extra])
		_list.set_item_metadata(i, item)
		_paths.append(path if kind == "game" else "")
	for warning in result.get("warnings", []):
		var wi := _list.add_item("warning: %s" % warning)
		_list.set_item_metadata(wi, {})
		_paths.append("")
	var root := Settings.game_root
	_current.text = "Using: %s" % (root if not root.is_empty() else "(none)")
	_use.disabled = true
	popup_centered()


func _selected_path() -> String:
	var i := _list.get_selected_items()
	if i.is_empty():
		return ""
	var meta = _list.get_item_metadata(i[0])
	if typeof(meta) != TYPE_DICTIONARY:
		return ""
	if str(meta.get("kind", "")) != "game":
		return ""
	return str(meta.get("path", ""))


func _on_use() -> void:
	var path := _selected_path()
	if path.is_empty():
		return
	install_chosen.emit(path)
	hide()
