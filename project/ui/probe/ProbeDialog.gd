extends Window
## Probe results: installs, warnings, pick a game root.

signal install_chosen(path: String)

@onready var _list: ItemList = %List
@onready var _current: Label = %Current
@onready var _use: Button = %Use
@onready var _browse: Button = %Browse
@onready var _hint: Label = %Hint
@onready var _dialog: FileDialog = %BrowseDialog


func _ready() -> void:
	close_requested.connect(hide)
	_use.pressed.connect(_on_use)
	_browse.pressed.connect(_on_browse)
	_list.item_selected.connect(func(_i): _use.disabled = _selected_path().is_empty())
	_list.item_activated.connect(func(_i):
		if not _selected_path().is_empty():
			_on_use()
	)
	_dialog.dir_selected.connect(_on_dir)
	_use.disabled = true


func show_probe(result: Dictionary) -> void:
	_list.clear()
	var installs: Array = result.get("installs", [])
	var games := 0
	for item in installs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var kind := str(item.get("kind", ""))
		var path := str(item.get("path", ""))
		var src := str(item.get("source", ""))
		var extra := ""
		if kind == "workshop_item":
			extra = "  [%s %s]" % [item.get("id", ""), src]
			if str(item.get("id", "")) == "3406347034" and Settings.last_map_dir.is_empty():
				Settings.last_map_dir = path
				Settings.save()
		elif not src.is_empty():
			extra = "  [%s]" % src
		if kind == "game":
			games += 1
		var i := _list.add_item("%s  %s%s" % [kind, path, extra])
		_list.set_item_metadata(i, item)
	for warning in result.get("warnings", []):
		var wi := _list.add_item("warning: %s" % warning)
		_list.set_item_metadata(wi, {})
	if installs.is_empty() and result.get("warnings", []).is_empty():
		var ei := _list.add_item("No installs found on this machine.")
		_list.set_item_metadata(ei, {})
		_list.set_item_disabled(ei, true)
	if _hint:
		if games == 0:
			_hint.text = "No game install found. Select a game row, or Browse to the Battlezone 98 Redux folder."
		else:
			_hint.text = "Found installs. Select a game entry and click Use this install — or double-click it."
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
		EditorFeedback.log("select a game install, or Browse")
		return
	install_chosen.emit(path)
	_current.text = "Using: %s" % path
	hide()


func _on_browse() -> void:
	if not Settings.game_root.is_empty():
		_dialog.current_dir = Settings.game_root
	_dialog.popup_centered_ratio(0.5)


func _on_dir(path: String) -> void:
	if path.is_empty():
		return
	install_chosen.emit(path)
	_current.text = "Using: %s" % path
	hide()
