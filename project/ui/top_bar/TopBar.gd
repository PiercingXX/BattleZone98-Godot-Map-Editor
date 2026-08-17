extends PanelContainer
## Brand, map label, file actions, tools, variant, undo.

signal open_requested
signal new_requested
signal save_requested
signal save_as_requested
signal validate_requested
signal more_selected(id: int)
signal tool_selected(name: String)
signal variant_changed
signal undo_requested
signal redo_requested
signal frame_requested

const MORE_IMPORT := 0
const MORE_RENDER := 1
const MORE_INSTALL := 2
const MORE_PACK := 3
const MORE_PROBE := 4
const MORE_HELP := 5
const MORE_SAVE_AS := 6

var _setting_tool: bool = false

@onready var _map_label: Label = %MapLabel
@onready var _variant: OptionButton = %Variant
@onready var _btn_open: Button = %Open
@onready var _btn_new: Button = %New
@onready var _btn_save: Button = %Save
@onready var _btn_validate: Button = %Validate
@onready var _tools: HBoxContainer = %Tools


func _ready() -> void:
	%Open.pressed.connect(func(): open_requested.emit())
	%New.pressed.connect(func(): new_requested.emit())
	%Save.pressed.connect(func(): save_requested.emit())
	%Validate.pressed.connect(func(): validate_requested.emit())
	%Undo.pressed.connect(func(): undo_requested.emit())
	%Redo.pressed.connect(func(): redo_requested.emit())
	%Frame.pressed.connect(func(): frame_requested.emit())
	_variant.item_selected.connect(func(_i): variant_changed.emit())
	var pop: PopupMenu = %More.get_popup()
	pop.add_item("Import assets", MORE_IMPORT)
	pop.add_item("Render thumbnail", MORE_RENDER)
	pop.add_item("Install into game (addon)", MORE_INSTALL)
	pop.add_item("Assemble pack", MORE_PACK)
	pop.add_separator()
	pop.add_item("Re-probe install", MORE_PROBE)
	pop.add_item("Save As…", MORE_SAVE_AS)
	pop.add_item("Hotkeys  F1", MORE_HELP)
	pop.id_pressed.connect(func(id):
		if id == MORE_SAVE_AS:
			save_as_requested.emit()
		else:
			more_selected.emit(id)
	)
	for child in _tools.get_children():
		if child is Button:
			var tool_name := String(child.name).to_lower()
			child.pressed.connect(_on_tool_button.bind(tool_name))
	ToolState.tool_changed.connect(set_tool)


func _on_tool_button(tool_name: String) -> void:
	if _setting_tool:
		return
	tool_selected.emit(tool_name)


func set_map_label(text: String) -> void:
	_map_label.text = text


func set_busy(value: bool) -> void:
	for b in [_btn_open, _btn_new, _btn_save, _btn_validate]:
		if b:
			b.disabled = value


func set_tool(name: String) -> void:
	_setting_tool = true
	var node := _tools.get_node_or_null(name.capitalize())
	if name == "flatten":
		node = _tools.get_node_or_null("Flatten")
	if node is Button:
		(node as Button).button_pressed = true
	_setting_tool = false


func fill_variants(variants: Array, active: String) -> void:
	_variant.clear()
	for v in variants:
		var label := "DM" if str(v) == "" else str(v)
		_variant.add_item(label)
		_variant.set_item_metadata(_variant.item_count - 1, v)
		if str(v) == active:
			_variant.select(_variant.item_count - 1)


func selected_variant() -> String:
	if _variant.selected < 0:
		return ""
	return str(_variant.get_item_metadata(_variant.selected))
