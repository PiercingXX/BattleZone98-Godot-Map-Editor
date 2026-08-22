extends HBoxContainer
class_name SectionHeader
## Labelled divider for a panel column: caption, hairline rule, optional
## collapse arrow. Colours come from the theme chain (ThemeProbe), never
## from a literal here.

signal toggled_open(open: bool)

var caption: String = "":
	set(value):
		caption = value
		if _label != null:
			_label.text = value

var _collapsible: bool = false
var _label: Label
var _rule: Panel
var _toggle: Button
var _open: bool = true


static func make(text: String, collapsible: bool = false) -> SectionHeader:
	var head := SectionHeader.new()
	head._collapsible = collapsible
	head.caption = text
	head._build()
	return head


func _init() -> void:
	name = "SectionHeader"
	add_theme_constant_override("separation", 8)


func _ready() -> void:
	_build()
	_restyle()


## Built lazily so the node is constructible headless and cheap to discard.
func _build() -> void:
	if _label != null:
		return
	if _collapsible:
		_toggle = Button.new()
		_toggle.name = "Toggle"
		_toggle.flat = true
		_toggle.focus_mode = Control.FOCUS_NONE
		_toggle.custom_minimum_size = Vector2(18, 0)
		_toggle.pressed.connect(func() -> void: set_open(not _open))
		add_child(_toggle)
	_label = Label.new()
	_label.name = "Caption"
	_label.text = caption
	add_child(_label)
	_rule = Panel.new()
	_rule.name = "Rule"
	_rule.custom_minimum_size = Vector2(8, 1)
	_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_sync_toggle()


func is_open() -> bool:
	return _open


func set_open(on: bool) -> void:
	if _open == on:
		return
	_open = on
	_sync_toggle()
	toggled_open.emit(on)


func _sync_toggle() -> void:
	if _toggle != null:
		_toggle.text = "v" if _open else ">"
		_toggle.tooltip_text = "Collapse section" if _open else "Expand section"


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _label != null:
		_restyle()


func _restyle() -> void:
	if _label == null:
		return
	var tint := ThemeProbe.dim_text(self)
	_label.add_theme_color_override("font_color", tint)
	_label.add_theme_font_size_override(
		"font_size", maxi(10, ThemeProbe.font_size(self, "font_size", "Label", 13) - 1)
	)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint.r, tint.g, tint.b, 0.28)
	_rule.add_theme_stylebox_override("panel", box)
