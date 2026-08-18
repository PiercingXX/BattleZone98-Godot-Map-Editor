extends PanelContainer
## Context-sensitive left rail: palette, brush, materials, selection.

const _CATEGORY_ORDER: PackedStringArray = [
	"craft", "building", "prop", "scrap", "geyser", "spawn", "environment", "other",
]
const _PANEL_MIN_X := 252.0

signal class_armed(rec: Dictionary)

@onready var _search: LineEdit = %Search
@onready var _category: OptionButton = %CategoryFilter
@onready var _clone_safe: CheckBox = %CloneSafe
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
@onready var _palette_section: Control = %PaletteSection
@onready var _brush_section: Control = %BrushSection
@onready var _mats_section: Control = %MatsSection
@onready var _select_section: Control = %SelectSection
@onready var _fly_section: Control = %FlySection
@onready var _select_summary: Label = %SelectSummary

var _filter: String = ""
var _index: Dictionary = {}
var _pack_kind: String = "bzp"
var _swatch_buttons: Array = []
var _syncing: bool = false
var _sel_count: int = -1


func _ready() -> void:
	set_process(false)
	custom_minimum_size.x = _PANEL_MIN_X
	_rebuild_category_items()
	_search.text_changed.connect(func(t): _filter = t.strip_edges(); _fill())
	_category.item_selected.connect(func(_i): _fill())
	_clone_safe.toggled.connect(func(_on): _fill())
	_list.item_selected.connect(_on_selected)
	_radius.value_changed.connect(_on_radius)
	_strength.value_changed.connect(_on_strength)
	_falloff.value_changed.connect(_on_falloff)
	_shape_circle.pressed.connect(func(): _on_shape("circle"))
	_shape_square.pressed.connect(func(): _on_shape("square"))
	_build_swatches()
	refresh_swatches()
	_sync_from_state()
	ToolState.brush_changed.connect(_sync_from_state)
	ToolState.tool_changed.connect(_on_tool)
	ToolState.armed_changed.connect(_on_armed)
	MapState.session_changed.connect(_on_session)
	MapState.objects_mutated.connect(_on_objects)
	_fill()
	refresh_context()


func set_classes(index: Dictionary, pack_kind: String) -> void:
	_index = index
	_pack_kind = pack_kind
	_rebuild_category_items()
	_fill()
	refresh_swatches()
	refresh_context()


func refresh_context() -> void:
	if _palette_section == null:
		return
	custom_minimum_size.x = _PANEL_MIN_X
	var show_palette := false
	var show_brush := false
	var show_mats := false
	var show_select := false
	var show_fly := false
	match ToolState.tool:
		"raise", "lower", "flatten", "smooth", "ramp", "noise":
			show_brush = true
		"paint":
			show_brush = true
			show_mats = true
		"place":
			show_palette = true
		"select":
			show_select = true
		_:
			show_fly = true
	_palette_section.visible = show_palette
	_brush_section.visible = show_brush
	_mats_section.visible = show_mats
	_select_section.visible = show_select
	_fly_section.visible = show_fly
	set_process(show_select)
	if show_select:
		_refresh_selection()


func sample_material(idx: int) -> String:
	idx = clampi(idx, 0, 15)
	ToolState.set_paint_material(idx)
	_highlight_swatch()
	var msg := "sampled mat %d (%s)" % [idx, MaterialPalette.type_name(idx)]
	EditorFeedback.log(msg)
	return msg


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
	# Recolor the borders on the styleboxes refresh_swatches() built (each
	# button owns its own) so margins and hover styling survive.
	for i in _swatch_buttons.size():
		var b: Button = _swatch_buttons[i]
		if not b.has_theme_stylebox_override("normal"):
			continue
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
		if sb == null:
			continue
		var active := i == ToolState.paint_material
		sb.border_color = Color(0.95, 0.85, 0.25) if active else Color(1, 1, 1, 0.15)


func _fill() -> void:
	_list.clear()
	var classes: Array = _index.get("classes", [])
	var q := _filter.to_lower()
	var cat := _selected_category()
	var clone_only := _clone_safe.button_pressed
	var added := 0
	for rec in classes:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var prjid := str(rec.get("prjid", ""))
		var label := str(rec.get("label", prjid))
		if q != "" and q not in prjid.to_lower() and q not in label.to_lower():
			continue
		if cat != "" and str(rec.get("category", "")) != cat:
			continue
		if clone_only and rec.get("template_verified") != true:
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
		added += 1
	if added == 0:
		var empty := _empty_message(classes.size())
		var i := _list.add_item(empty)
		_list.set_item_metadata(i, {})
		_list.set_item_disabled(i, true)
	else:
		_list.sort_items_by_text()
		_restore_armed_selection()


func _rebuild_category_items() -> void:
	var present: Dictionary = {}
	for rec in _index.get("classes", []):
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var cat := str(rec.get("category", ""))
		if cat != "":
			present[cat] = true
	var prev := _selected_category()
	_category.clear()
	_category.add_item("All")
	_category.set_item_metadata(0, "")
	for cat in _CATEGORY_ORDER:
		if present.has(cat):
			var i := _category.item_count
			_category.add_item(cat)
			_category.set_item_metadata(i, cat)
			present.erase(cat)
	var extra: Array = present.keys()
	extra.sort()
	for cat in extra:
		var i := _category.item_count
		_category.add_item(str(cat))
		_category.set_item_metadata(i, str(cat))
	var pick := 0
	for i in _category.item_count:
		if str(_category.get_item_metadata(i)) == prev:
			pick = i
			break
	_category.select(pick)


func _selected_category() -> String:
	if _category == null or _category.item_count < 1:
		return ""
	var i := _category.selected
	if i <= 0:
		return ""
	var meta = _category.get_item_metadata(i)
	return str(meta) if meta != null else ""


func _empty_message(total: int) -> String:
	if total == 0:
		if Settings.game_root.is_empty():
			return "No classes. More → Re-probe, then Import assets."
		return "No classes. More → Import assets."
	var parts: PackedStringArray = []
	var cat := _selected_category()
	if cat != "":
		parts.append("category: %s" % cat)
	if _clone_safe.button_pressed:
		parts.append("clone-safe")
	if not _filter.is_empty():
		if parts.is_empty():
			return "No classes match “%s”" % _filter
		parts.append("“%s”" % _filter)
	if not parts.is_empty():
		return "no matches — %s" % ", ".join(parts)
	return "No classes."


func _restore_armed_selection() -> void:
	var armed_id := str(ToolState.armed.get("prjid", ""))
	if armed_id.is_empty():
		return
	for i in _list.item_count:
		var rec = _list.get_item_metadata(i)
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("prjid", "")) == armed_id:
			_list.select(i)
			_list.ensure_current_is_visible()
			return


func _on_selected(index: int) -> void:
	var rec = _list.get_item_metadata(index)
	if typeof(rec) != TYPE_DICTIONARY or rec.is_empty():
		return
	if _list.is_item_disabled(index):
		return
	if not MapState.has_session:
		EditorFeedback.log("open a map before placing")
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


func _on_tool(name: String) -> void:
	refresh_context()
	_highlight_swatch()
	if name == "place" and ToolState.armed.is_empty():
		EditorFeedback.log("pick a class in the palette")


func _on_armed() -> void:
	if ToolState.armed.is_empty():
		_list.deselect_all()
	else:
		_restore_armed_selection()
	refresh_context()


func _on_session() -> void:
	# ToolState clears the armed class on session_changed; rebuild so the
	# list does not keep a highlight from the previous map.
	_fill()
	if ToolState.armed.is_empty():
		_list.deselect_all()
	refresh_context()


func _on_objects() -> void:
	if ToolState.tool == "select":
		_refresh_selection()


func _process(_delta: float) -> void:
	_refresh_selection()


func _refresh_selection() -> void:
	if _select_summary == null:
		return
	var n := MapState.selected_ids.size()
	if n == _sel_count:
		return
	_sel_count = n
	_select_summary.text = "%d selected" % n


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
