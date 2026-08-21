extends RefCounted
class_name EditorIcons
## Original 24×24 chrome icons. White fill so theme modulate can tint.

const DIR := "res://project/ui/icons/"

const NAMES: PackedStringArray = [
	"fly", "raise", "lower", "flatten", "smooth", "ramp", "paint", "place",
	"select", "noise", "qsel", "rsel", "wand", "clone",
	"open", "new", "save", "validate", "test", "undo", "redo", "frame",
	"search", "filter", "eyedropper", "water", "plants", "view", "team",
	"walk", "grid", "slope", "log",
]

const TOOL_ICONS := {
	"Fly": "fly",
	"Raise": "raise",
	"Lower": "lower",
	"Flatten": "flatten",
	"Smooth": "smooth",
	"Ramp": "ramp",
	"Paint": "paint",
	"Place": "place",
	"Select": "select",
	"Noise": "noise",
	"Qsel": "qsel",
	"Rsel": "rsel",
	"Wand": "wand",
	"Clone": "clone",
}

const ICON_PX := 16
const TOOL_MIN := 28


static func path_for(icon_name: String) -> String:
	return DIR.path_join("%s.svg" % icon_name)


static func texture(icon_name: String) -> Texture2D:
	var path := path_for(icon_name)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func apply_button(btn: Button, icon_name: String, keep_text: bool = false) -> void:
	if btn == null:
		return
	var tex := texture(icon_name)
	if tex == null:
		return
	btn.icon = tex
	btn.expand_icon = false
	if keep_text:
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		return
	btn.text = ""
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if btn.custom_minimum_size.x < TOOL_MIN:
		btn.custom_minimum_size.x = TOOL_MIN
	if btn.custom_minimum_size.y < TOOL_MIN:
		btn.custom_minimum_size.y = TOOL_MIN


static func apply_line_edit(edit: LineEdit, icon_name: String) -> void:
	if edit == null:
		return
	var tex := texture(icon_name)
	if tex == null:
		return
	edit.right_icon = tex


static func make_rect(icon_name: String, px: int = ICON_PX) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = "Icon_%s" % icon_name
	tr.texture = texture(icon_name)
	tr.custom_minimum_size = Vector2(px, px)
	tr.size = Vector2(px, px)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func prepend_icon(node: Control, icon_name: String) -> TextureRect:
	if node == null or node.get_parent() == null:
		return null
	var parent := node.get_parent()
	var icon := make_rect(icon_name)
	if parent is HBoxContainer:
		parent.add_child(icon)
		parent.move_child(icon, node.get_index())
		return icon
	var wrap := HBoxContainer.new()
	wrap.name = "%sHead" % node.name
	wrap.add_theme_constant_override("separation", 4)
	var idx := node.get_index()
	parent.remove_child(node)
	wrap.add_child(icon)
	wrap.add_child(node)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)
	parent.move_child(wrap, idx)
	return icon
