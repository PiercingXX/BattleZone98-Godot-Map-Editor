extends PanelContainer
## Collapsible undo-stack list. Click a step to undo/redo to that point.

@onready var _toggle: Button = %Toggle
@onready var _list: ItemList = %List

var _syncing: bool = false


func _ready() -> void:
	_toggle.toggled.connect(_on_toggle)
	_list.item_clicked.connect(_on_item_clicked)
	UndoStack.changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if UndoStack.changed.is_connected(refresh):
		UndoStack.changed.disconnect(refresh)


func _on_toggle(on: bool) -> void:
	_list.visible = on
	_toggle.text = "History ▾" if on else "History ▸"


func _on_item_clicked(index: int, _at: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or _syncing:
		return
	if index < 0 or index >= UndoStack.command_count():
		return
	if _list.is_item_disabled(index):
		return
	UndoStack.jump_to(index)


func refresh() -> void:
	if _list == null:
		return
	_syncing = true
	_list.clear()
	var n := UndoStack.command_count()
	if n == 0:
		var i := _list.add_item("No edits yet.")
		_list.set_item_disabled(i, true)
		_syncing = false
		return
	var cur := UndoStack.current_index()
	for i in n:
		var label := UndoStack.describe_command(UndoStack.command_at(i))
		if label.is_empty():
			label = "edit"
		var idx := _list.add_item(label)
		if i == cur:
			_list.set_item_custom_bg_color(idx, Color(0.24, 0.42, 0.62, 0.85))
			_list.select(idx)
		elif i > cur:
			_list.set_item_custom_fg_color(idx, Color(0.62, 0.62, 0.64, 1))
	_syncing = false
