extends PanelContainer
## GIMP-style vertical toolbox on the left edge: icon-only tool buttons.

signal tool_selected(name: String)

const CAPTIONS := {
	"Flatten": "Flat",
	"Qsel": "QSel",
	"Rsel": "RSel",
}
const ACTIONS := {
	"Fly": Keymap.ACTION_FLY,
	"Raise": Keymap.ACTION_RAISE,
	"Lower": Keymap.ACTION_LOWER,
	"Flatten": Keymap.ACTION_FLATTEN,
	"Smooth": Keymap.ACTION_SMOOTH,
	"Ramp": Keymap.ACTION_RAMP,
	"Paint": Keymap.ACTION_PAINT,
	"Place": Keymap.ACTION_PLACE,
	"Select": Keymap.ACTION_SELECT,
	"Noise": Keymap.ACTION_NOISE,
	"Qsel": Keymap.ACTION_QSEL,
	"Rsel": Keymap.ACTION_RSEL,
	"Wand": Keymap.ACTION_WAND,
	"Clone": Keymap.ACTION_CLONE,
}
## Rail order mirrors the workflow: navigate, sculpt, paint, place, select.
const ORDER: PackedStringArray = [
	"Fly", "Raise", "Lower", "Flatten", "Smooth", "Ramp", "Noise",
	"Paint", "Clone", "Place", "Select", "Qsel", "Rsel", "Wand",
]

var _setting_tool: bool = false

@onready var _tools: VBoxContainer = %Tools


func _ready() -> void:
	_install_buttons()
	refresh_keymap()
	ToolState.tool_changed.connect(set_tool)
	set_tool(ToolState.tool)


func _install_buttons() -> void:
	if _tools == null:
		return
	var group := ButtonGroup.new()
	for id in ORDER:
		if _tools.get_node_or_null(id) != null:
			continue
		var b := Button.new()
		b.name = id
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.theme_type_variation = "ToolButton"
		b.button_group = group
		EditorIcons.apply_button(b, str(EditorIcons.TOOL_ICONS.get(id, "fly")), false)
		b.pressed.connect(_on_tool_button.bind(id.to_lower()))
		_tools.add_child(b)


func _on_tool_button(tool_name: String) -> void:
	if _setting_tool:
		return
	tool_selected.emit(tool_name)


func set_tool(name: String) -> void:
	if _tools == null:
		return
	_setting_tool = true
	var node := _tools.get_node_or_null(name.capitalize())
	if node is Button:
		(node as Button).button_pressed = true
	_setting_tool = false


func refresh_keymap() -> void:
	if _tools == null:
		return
	for id in ACTIONS:
		var node := _tools.get_node_or_null(str(id))
		if not (node is Button):
			continue
		var caption := str(CAPTIONS.get(str(id), str(id)))
		(node as Button).tooltip_text = "%s  (%s)" % [
			caption, Keymap.format_action(str(ACTIONS[id])),
		]
