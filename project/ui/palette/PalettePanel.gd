extends PanelContainer
## Class search, brush controls, material swatches.

signal class_armed(rec: Dictionary)

@onready var _search: LineEdit = %Search
@onready var _list: ItemList = %ClassList
@onready var _radius: HSlider = %Radius
@onready var _strength: HSlider = %Strength
@onready var _falloff: HSlider = %Falloff
@onready var _radius_val: Label = %RadiusVal
@onready var _strength_val: Label = %StrengthVal
@onready var _falloff_val: Label = %FalloffVal
@onready var _shape_circle: Button = %ShapeCircle
@onready var _shape_square: Button = %ShapeSquare
@onready var _swatches: GridContainer = %Swatches

var _filter: String = ""
var _index: Dictionary = {}
var _pack_kind: String = "bzp"
var _swatch_buttons: Array = []
var _syncing: bool = false


func _ready() -> void:
	_search.text_changed.connect(func(t): _filter = t; _fill())
	_list.item_selected.connect(_on_selected)
	_radius.value_changed.connect(_on_radius)
	_strength.value_changed.connect(_on_strength)
	_falloff.value_changed.connect(_on_falloff)
	_shape_circle.pressed.connect(func(): _on_shape("circle"))
	_shape_square.pressed.connect(func(): _on_shape("square"))
	_build_swatches()
	_sync_from_state()
	ToolState.brush_changed.connect(_sync_from_state)
	ToolState.tool_changed.connect(func(_n): _highlight_swatch())


func set_classes(index: Dictionary, pack_kind: String) -> void:
	_index = index
	_pack_kind = pack_kind
	_fill()
	refresh_swatches()


func refresh_swatches() -> void:
	var colors := MaterialPalette.colors()
	for i in _swatch_buttons.size():
		var b: Button = _swatch_buttons[i]
		b.tooltip_text = "%s  (%d)" % [MaterialPalette.type_name(i), i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[i]
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.15)
		sb.set_content_margin_all(2)
		b.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.border_color = Color(1, 1, 1, 0.55)
		b.add_theme_stylebox_override("hover", hover)
	_highlight_swatch()


func _build_swatches() -> void:
	_swatch_buttons.clear()
	for i in 16:
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_swatch.bind(i))
		_swatches.add_child(b)
		_swatch_buttons.append(b)


func _on_swatch(id: int) -> void:
	ToolState.set_paint_material(id)
	ToolState.set_tool("paint")
	_highlight_swatch()


func _highlight_swatch() -> void:
	var colors := MaterialPalette.colors()
	for i in _swatch_buttons.size():
		var b: Button = _swatch_buttons[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[i] if i < colors.size() else Color.GRAY
		sb.set_border_width_all(2)
		var active := i == ToolState.paint_material
		sb.border_color = Color(0.95, 0.85, 0.25) if active else Color(1, 1, 1, 0.15)
		b.add_theme_stylebox_override("normal", sb)


func _fill() -> void:
	_list.clear()
	var classes: Array = _index.get("classes", [])
	var q := _filter.to_lower()
	for rec in classes:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var prjid := str(rec.get("prjid", ""))
		var label := str(rec.get("label", prjid))
		if q != "" and q not in prjid.to_lower() and q not in label.to_lower():
			continue
		var source := str(rec.get("source", "game"))
		var legal := source == "game" or _pack_kind == "bzp"
		var mode := str(rec.get("placement_mode", "runtime"))
		var text := "%s  [%s]  %s" % [prjid, rec.get("category", ""), mode]
		if not legal:
			text += "  (other pack — unavailable)"
		var i := _list.add_item(text)
		_list.set_item_metadata(i, rec)
		_list.set_item_disabled(i, not legal)
	_list.sort_items_by_text()


func _on_selected(index: int) -> void:
	var rec = _list.get_item_metadata(index)
	if typeof(rec) != TYPE_DICTIONARY:
		return
	if _list.is_item_disabled(index):
		return
	class_armed.emit(rec)


func _on_radius(v: float) -> void:
	if _syncing:
		return
	_radius_val.text = "%d m" % int(v)
	ToolState.set_radius(v)


func _on_strength(v: float) -> void:
	if _syncing:
		return
	_strength_val.text = "%d%%" % int(v * 100.0)
	ToolState.set_strength(v)


func _on_falloff(v: float) -> void:
	if _syncing:
		return
	_falloff_val.text = "%d%%" % int(v * 100.0)
	ToolState.set_falloff(v)


func _on_shape(shape: String) -> void:
	if _syncing:
		return
	ToolState.set_shape(shape)
	_sync_shape_buttons()


func _sync_from_state() -> void:
	_syncing = true
	_radius.value = ToolState.radius_m
	_strength.value = ToolState.strength
	_falloff.value = ToolState.falloff
	_radius_val.text = "%d m" % int(ToolState.radius_m)
	_strength_val.text = "%d%%" % int(ToolState.strength * 100.0)
	_falloff_val.text = "%d%%" % int(ToolState.falloff * 100.0)
	_sync_shape_buttons()
	_highlight_swatch()
	_syncing = false


func _sync_shape_buttons() -> void:
	_shape_circle.button_pressed = ToolState.shape != "square"
	_shape_square.button_pressed = ToolState.shape == "square"
