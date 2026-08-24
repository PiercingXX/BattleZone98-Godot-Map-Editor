extends PanelContainer
## Context-sensitive left rail: palette, brush, materials, selection.

const _CATEGORY_ORDER: PackedStringArray = [
	"craft", "building", "pilot", "scrap", "geyser", "spawn", "pickup",
	"prop", "environment", "weapon", "other",
]
const _PANEL_MIN_X := 310.0
const _SWATCH_PX := 35
const _SWATCH_BORDER := 2
const _LIST_ALL_MAX := 80

signal class_armed(rec: Dictionary)
signal selection_query_applied
signal collapsed_changed(collapsed: bool)

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
@onready var _noise_scale: HSlider = %NoiseScale
@onready var _noise_contrast: HSlider = %NoiseContrast
@onready var _noise_scale_val: Label = %NoiseScaleVal
@onready var _noise_contrast_val: Label = %NoiseContrastVal
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
var _sel_ids_sig: String = ""
var _query_edit: LineEdit
var _query_select: Button
var _query_add: Button
var _batch_team: SpinBox
var _batch_team_btn: Button
var _replace_btn: Button
var _replace_dlg: ConfirmationDialog
var _replace_search: LineEdit
var _replace_list: ItemList
var _runtime_dlg: ConfirmationDialog
var _pending_replace: Dictionary = {}
var _replace_filter: String = ""
var _copy_btn: Button
var _copy_menu: PopupMenu
var _symmetry: OptionButton
var _symmetry_row: HBoxContainer
var _terrain_section: VBoxContainer
var _wand_row: HBoxContainer
var _wand_tol: SpinBox
var _feather_spin: SpinBox
var _feather_btn: Button
var _grow_spin: SpinBox
var _grow_btn: Button
var _shrink_btn: Button
var _mat_sel_btn: Button
var _terrain_hint: Label
var _clone_row: HBoxContainer
var _clone_mats: CheckBox
var _clone_match: CheckBox
var _match_edges: CheckBox
var _match_btn: Button
var _kind_solid: Button
var _kind_cap: Button
var _kind_diag: Button
var _rot_btn: Button
var _flip_box: CheckBox
var _tile_hint: Label
var _tile_grid: GridContainer
var _tile_pick: Label
var _tile_buttons: Array = []
var _tile_sig: String = ""
var _snap_grid: OptionButton
var _snap_angle: OptionButton
var _snap_row: HBoxContainer
var _collapse: Button
var _collapsed: bool = false


func _ready() -> void:
	set_process(false)
	custom_minimum_size.x = _PANEL_MIN_X
	_install_collapse()
	_rebuild_category_items()
	_search.text_changed.connect(func(t): _filter = t.strip_edges(); _fill())
	_category.item_selected.connect(func(_i): _fill(); _ensure_filter_icon())
	_clone_safe.toggled.connect(func(_on): _fill())
	_list.item_selected.connect(_on_selected)
	_radius.value_changed.connect(_on_radius)
	_strength.value_changed.connect(_on_strength)
	_falloff.value_changed.connect(_on_falloff)
	_shape_circle.pressed.connect(func(): _on_shape("circle"))
	_shape_square.pressed.connect(func(): _on_shape("square"))
	_noise_scale.value_changed.connect(_on_noise_scale)
	_noise_contrast.value_changed.connect(_on_noise_contrast)
	_build_swatches()
	_build_paint_match()
	_build_select_tools()
	_build_snap_tools()
	_build_symmetry()
	_build_terrain_select()
	_build_clone_tools()
	_apply_chrome_icons()
	refresh_swatches()
	_sync_from_state()
	ToolState.brush_changed.connect(_sync_from_state)
	ToolState.symmetry_changed.connect(_sync_symmetry_from_state)
	ToolState.snap_changed.connect(_sync_snap_from_state)
	ToolState.tool_changed.connect(_on_tool)
	ToolState.armed_changed.connect(_on_armed)
	MapState.session_changed.connect(_on_session)
	MapState.objects_mutated.connect(_on_objects)
	MapState.selection_changed.connect(_refresh_terrain_actions)
	_fill()
	refresh_context()


func set_classes(index: Dictionary, pack_kind: String) -> void:
	_index = index
	_pack_kind = pack_kind
	_rebuild_category_items()
	_fill()
	refresh_swatches()
	refresh_context()
	if _replace_dlg != null and _replace_dlg.visible:
		_fill_replace_list()


func is_collapsed() -> bool:
	return _collapsed


func set_collapsed(on: bool) -> void:
	if _collapsed == on:
		return
	_collapsed = on
	if _collapsed:
		_hide_body()
	else:
		refresh_context()
	PanelCollapse.apply_toggle(_collapse, "Tool", not _collapsed)
	collapsed_changed.emit(on)


func _install_collapse() -> void:
	var box := get_node_or_null("Box") as VBoxContainer
	if box == null:
		return
	_collapse = PanelCollapse.make_toggle("Tool", true)
	box.add_child(_collapse)
	box.move_child(_collapse, 0)
	_collapse.toggled.connect(func(on: bool) -> void: set_collapsed(not on))


func _hide_body() -> void:
	var box := get_node_or_null("Box") as VBoxContainer
	if box == null:
		return
	for child in box.get_children():
		if child == _collapse:
			continue
		child.visible = false


func refresh_context() -> void:
	if _palette_section == null:
		return
	if _collapsed:
		_hide_body()
		return
	custom_minimum_size.x = _PANEL_MIN_X
	var show_palette := false
	var show_brush := false
	var show_mats := false
	var show_select := false
	var show_fly := false
	var show_terrain := false
	match ToolState.tool:
		"raise", "lower", "flatten", "smooth", "ramp", "noise", "clone":
			show_brush = true
		"paint":
			show_brush = true
			show_mats = true
		"place":
			show_palette = true
			show_brush = true
		"select":
			show_select = true
		"qsel":
			show_brush = true
			show_mats = true
			show_terrain = true
		"rsel":
			show_mats = true
			show_terrain = true
		"wand":
			show_mats = true
			show_terrain = true
		_:
			show_fly = true
	_palette_section.visible = show_palette
	_brush_section.visible = show_brush
	_mats_section.visible = show_mats
	_select_section.visible = show_select
	_fly_section.visible = show_fly
	if _terrain_section:
		_terrain_section.visible = show_terrain
	_set_brush_metrics_visible(show_brush and ToolState.tool != "place")
	if ToolState.tool == "qsel":
		_set_strength_visible(false)
	_set_clone_visible(ToolState.tool == "clone")
	_set_noise_visible(ToolState.tool == "noise")
	if _wand_row:
		_wand_row.visible = ToolState.tool == "wand"
	_refresh_symmetry_item()
	_refresh_terrain_actions()
	set_process(show_select)
	if show_select:
		_refresh_selection()


func sample_material(idx: int) -> String:
	idx = clampi(idx, 0, 15)
	ToolState.set_paint_kind("solid")
	ToolState.set_paint_material(idx)
	_highlight_swatch()
	_sync_paint_tile_from_state()
	var msg := "sampled mat %d (%s)" % [idx, MaterialPalette.type_name(idx)]
	EditorFeedback.log(msg)
	return msg


func sample_tile(word: int) -> String:
	ToolState.set_paint_from_word(word)
	_highlight_swatch()
	_sync_paint_tile_from_state()
	var msg := "sampled %s" % ToolState.paint_describe()
	EditorFeedback.log(msg)
	return msg


func refresh_swatches() -> void:
	var colors := MaterialPalette.colors()
	# 2× source so the 28 px rect stays sharp after GPU scale.
	var thumbnails := MaterialPalette.material_thumbnails(_SWATCH_PX * 2)
	for i in _swatch_buttons.size():
		var b: Button = _swatch_buttons[i]
		b.tooltip_text = "%s  (%d)" % [MaterialPalette.type_name(i), i]
		var tex: Texture2D = null
		if i < thumbnails.size() and thumbnails[i] is Texture2D:
			tex = thumbnails[i]
		var thumb := b.get_node_or_null("Thumb") as TextureRect
		if thumb:
			thumb.texture = tex
			thumb.visible = tex != null
		# Texture fills the button; stylebox is a selection ring. No atlas
		# tile → keep the TRN flat colour as the swatch.
		var bg := Color(0, 0, 0, 0) if tex != null else colors[i]
		_apply_swatch_style(b, bg)
	_highlight_swatch()
	_tile_sig = ""
	_sync_paint_tile_from_state()


func _build_swatches() -> void:
	_swatch_buttons.clear()
	for i in 16:
		var b := Button.new()
		b.custom_minimum_size = Vector2(_SWATCH_PX, _SWATCH_PX)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true
		b.pressed.connect(_on_swatch.bind(i))
		var thumb := TextureRect.new()
		thumb.name = "Thumb"
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = _SWATCH_BORDER
		thumb.offset_top = _SWATCH_BORDER
		thumb.offset_right = -_SWATCH_BORDER
		thumb.offset_bottom = -_SWATCH_BORDER
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.visible = false
		b.add_child(thumb)
		_swatches.add_child(b)
		_swatch_buttons.append(b)


func _build_paint_match() -> void:
	if _mats_section == null or _kind_solid != null:
		return
	var kinds := HBoxContainer.new()
	kinds.name = "TileKindRow"
	kinds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kg := ButtonGroup.new()
	_kind_solid = _kind_btn("Solid", kg)
	_kind_cap = _kind_btn("Cap", kg)
	_kind_diag = _kind_btn("Corner", kg)
	_kind_solid.pressed.connect(func() -> void:
		if not _syncing:
			ToolState.set_paint_kind("solid")
	)
	_kind_cap.pressed.connect(func() -> void:
		if not _syncing:
			ToolState.set_paint_kind("cap")
	)
	_kind_diag.pressed.connect(func() -> void:
		if not _syncing:
			ToolState.set_paint_kind("diag")
	)
	kinds.add_child(_kind_solid)
	kinds.add_child(_kind_cap)
	kinds.add_child(_kind_diag)
	_mats_section.add_child(kinds)
	# Solids, caps, corners and their variants are all picked the same way:
	# a grid of the tiles this world actually ships, drawn from the atlas the
	# viewport paints with. Fixed height so switching kind cannot resize the
	# rail under the cursor.
	var meet := VBoxContainer.new()
	meet.name = "TileMeetRow"
	meet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var meet_l := Label.new()
	meet_l.name = "TileChoiceLabel"
	meet_l.text = "Tiles"
	meet.add_child(meet_l)
	var scroll := ScrollContainer.new()
	scroll.name = "TileChoiceScroll"
	scroll.custom_minimum_size = Vector2(0, _SWATCH_PX * 2 + 14)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	meet.add_child(scroll)
	_tile_grid = GridContainer.new()
	_tile_grid.name = "TileChoices"
	_tile_grid.columns = 6
	_tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tile_grid)
	_mats_section.add_child(meet)
	var face := HBoxContainer.new()
	face.name = "TileFaceRow"
	_rot_btn = Button.new()
	_rot_btn.name = "PaintRotate"
	_rot_btn.focus_mode = Control.FOCUS_NONE
	_rot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rot_btn.clip_text = true
	_rot_btn.pressed.connect(func() -> void: ToolState.cycle_paint_rot())
	_flip_box = CheckBox.new()
	_flip_box.name = "PaintMirror"
	_flip_box.text = "Mirror"
	_flip_box.focus_mode = Control.FOCUS_NONE
	_flip_box.toggled.connect(func(on: bool) -> void:
		if _syncing:
			return
		ToolState.set_paint_flip(on)
	)
	face.add_child(_rot_btn)
	face.add_child(_flip_box)
	_mats_section.add_child(face)
	var vari := HBoxContainer.new()
	vari.name = "TileVariantRow"
	_tile_pick = Label.new()
	_tile_pick.name = "TileChoiceValue"
	_tile_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_pick.clip_text = true
	vari.add_child(_tile_pick)
	_mats_section.add_child(vari)
	_tile_hint = Label.new()
	_tile_hint.name = "TileHint"
	_tile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tile_hint.add_theme_color_override("font_color", Color(0.62, 0.62, 0.64, 1))
	_tile_hint.text = "The grid lists every tile this world ships for the chosen material. Alt+LMB samples the tile under the cursor."
	_mats_section.add_child(_tile_hint)
	_match_edges = CheckBox.new()
	_match_edges.name = "MatchEdges"
	_match_edges.text = "Guess from neighbours"
	_match_edges.tooltip_text = "Helper only. The game stores the tile word you assign. This recodes the halo after a solid stamp."
	_match_edges.focus_mode = Control.FOCUS_NONE
	_match_edges.button_pressed = ToolState.paint_match_edges
	_match_edges.toggled.connect(func(on: bool) -> void:
		ToolState.set_paint_match_edges(on)
	)
	_mats_section.add_child(_match_edges)
	_match_btn = Button.new()
	_match_btn.name = "MatchNow"
	_match_btn.text = "Guess now"
	_match_btn.tooltip_text = "Recode caps and corners from neighbours for the terrain selection, or the whole map. Undoable."
	_match_btn.focus_mode = Control.FOCUS_NONE
	_match_btn.pressed.connect(func() -> void:
		EditActions.rematch_material_edges(EditorFeedback.log)
	)
	_mats_section.add_child(_match_btn)
	_sync_paint_tile_from_state()


func _kind_btn(caption: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = caption
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _fill_tile_choices() -> void:
	## One image swatch per tile the world ships for this material and kind.
	## Rebuilt only when the material or kind changes — cropping the atlas on
	## every state sync would run on each brush-radius nudge.
	if _tile_grid == null:
		return
	var sig := "%s:%d:%s" % [
		MapState.world, ToolState.paint_material, ToolState.paint_kind
	]
	if sig != _tile_sig:
		_tile_sig = sig
		for b in _tile_buttons:
			(b as Node).queue_free()
		_tile_buttons.clear()
		var swatches: Array = MaterialPalette.tile_swatches(
			ToolState.paint_material, ToolState.paint_kind, _SWATCH_PX * 2
		)
		for entry_v in swatches:
			var entry: Dictionary = entry_v
			_tile_grid.add_child(_tile_button(entry))
	_highlight_tile_choice()


func _tile_button(entry: Dictionary) -> Button:
	var trans := int(entry.get("trans", 0))
	var variant := int(entry.get("variant", 0))
	var b := Button.new()
	b.custom_minimum_size = Vector2(_SWATCH_PX, _SWATCH_PX)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.set_meta("trans", trans)
	b.set_meta("variant", variant)
	b.tooltip_text = _tile_caption(trans, variant)
	var tex: Variant = entry.get("texture")
	if tex is Texture2D:
		var thumb := TextureRect.new()
		thumb.name = "Thumb"
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = _SWATCH_BORDER
		thumb.offset_top = _SWATCH_BORDER
		thumb.offset_right = -_SWATCH_BORDER
		thumb.offset_bottom = -_SWATCH_BORDER
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.texture = tex
		b.add_child(thumb)
		_apply_swatch_style(b, Color(0, 0, 0, 0))
	else:
		# No atlas to crop: the tile stays pickable, labelled instead of drawn.
		b.text = "%d%s" % [trans, char(65 + clampi(variant, 0, 25))]
		_apply_swatch_style(b, MaterialPalette.colors()[trans & 0xF])
	b.pressed.connect(_on_tile_choice.bind(trans, variant))
	_tile_buttons.append(b)
	return b


func _tile_caption(trans: int, variant: int) -> String:
	var letter := char(65 + clampi(variant, 0, 25))
	if ToolState.paint_kind == "solid":
		return "%s — variant %s" % [MaterialPalette.type_name(ToolState.paint_material), letter]
	var kind := "corner" if ToolState.paint_kind == "diag" else "cap"
	return "%s meeting %d %s — variant %s" % [
		kind, trans, MaterialPalette.type_name(trans), letter
	]


func _on_tile_choice(trans: int, variant: int) -> void:
	if _syncing:
		return
	if ToolState.paint_kind != "solid":
		ToolState.set_paint_transition(trans)
	ToolState.set_paint_variant(variant)
	if not ToolState.is_terrain_select_tool():
		ToolState.set_tool("paint")
	_highlight_tile_choice()


func _highlight_tile_choice() -> void:
	var solid := ToolState.paint_kind == "solid"
	for b_v in _tile_buttons:
		var b: Button = b_v
		if not is_instance_valid(b):
			continue
		var active := (
			int(b.get_meta("variant", -1)) == ToolState.paint_variant
			and (solid or int(b.get_meta("trans", -1)) == ToolState.paint_transition)
		)
		var idle := Color(0.95, 0.85, 0.25) if active else Color(1, 1, 1, 0.15)
		var hot := Color(0.95, 0.85, 0.25) if active else Color(1, 1, 1, 0.55)
		for pair in [["normal", idle], ["hover", hot], ["pressed", hot], ["hover_pressed", hot]]:
			var sb := b.get_theme_stylebox(str(pair[0])) as StyleBoxFlat
			if sb:
				sb.border_color = pair[1]
	if _tile_pick:
		_tile_pick.text = _tile_caption(ToolState.paint_transition, ToolState.paint_variant)


func _apply_swatch_style(b: Button, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(_SWATCH_BORDER)
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.set_content_margin_all(_SWATCH_BORDER)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.border_color = Color(1, 1, 1, 0.55)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)


func _on_swatch(id: int) -> void:
	ToolState.set_paint_material(id)
	if not ToolState.is_terrain_select_tool():
		ToolState.set_tool("paint")
	_highlight_swatch()
	_refresh_terrain_actions()


func _highlight_swatch() -> void:
	# Recolor the borders on the styleboxes refresh_swatches() built (each
	# button owns its own) so margins and hover styling survive.
	for i in _swatch_buttons.size():
		var b: Button = _swatch_buttons[i]
		var active := i == ToolState.paint_material
		var idle := Color(0.95, 0.85, 0.25) if active else Color(1, 1, 1, 0.15)
		var hot := Color(0.95, 0.85, 0.25) if active else Color(1, 1, 1, 0.55)
		for pair in [["normal", idle], ["hover", hot], ["pressed", hot], ["hover_pressed", hot]]:
			var sb := b.get_theme_stylebox(str(pair[0])) as StyleBoxFlat
			if sb:
				sb.border_color = pair[1]


func _fill() -> void:
	_list.clear()
	var classes: Array = _index.get("classes", [])
	var q := _filter.to_lower()
	var cat := _selected_category()
	var clone_only := _clone_safe.button_pressed
	if q.is_empty() and cat.is_empty() and not clone_only and classes.size() > _LIST_ALL_MAX:
		_fill_browse_prompt(classes)
		return
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


func _fill_browse_prompt(classes: Array) -> void:
	var counts: Dictionary = {}
	for rec in classes:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var c := str(rec.get("category", "other"))
		if c.is_empty():
			c = "other"
		counts[c] = int(counts.get(c, 0)) + 1
	var hint := _list.add_item("Type to search, or pick a category  (%d classes)" % classes.size())
	_list.set_item_metadata(hint, {})
	_list.set_item_disabled(hint, true)
	for cat in _CATEGORY_ORDER:
		if not counts.has(cat):
			continue
		var i := _list.add_item("%s  (%d)" % [cat, counts[cat]])
		_list.set_item_metadata(i, {"browse_cat": cat})
		counts.erase(cat)
	var extra: Array = counts.keys()
	extra.sort()
	for cat in extra:
		var i := _list.add_item("%s  (%d)" % [str(cat), counts[cat]])
		_list.set_item_metadata(i, {"browse_cat": str(cat)})


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
	_ensure_filter_icon()


func _selected_category() -> String:
	if _category == null or _category.item_count < 1:
		return ""
	var i := _category.selected
	if i <= 0:
		return ""
	var meta = _category.get_item_metadata(i)
	return str(meta) if meta != null else ""


func _select_category(cat: String) -> void:
	if _category == null:
		return
	for i in _category.item_count:
		if str(_category.get_item_metadata(i)) == cat:
			_category.select(i)
			_fill()
			return


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
	var browse := str(rec.get("browse_cat", ""))
	if not browse.is_empty():
		_select_category(browse)
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


func _on_noise_scale(v: float) -> void:
	if _syncing:
		return
	_noise_scale_val.text = "%.1f" % v
	ToolState.set_noise_scale(v)


func _on_noise_contrast(v: float) -> void:
	if _syncing:
		return
	_noise_contrast_val.text = "%.1f" % v
	ToolState.set_noise_contrast(v)


func _build_symmetry() -> void:
	if _brush_section == null or _symmetry != null:
		return
	_symmetry_row = HBoxContainer.new()
	_symmetry_row.name = "SymmetryRow"
	_symmetry_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := Label.new()
	lab.name = "SymmetryName"
	lab.text = "Symmetry"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_symmetry = OptionButton.new()
	_symmetry.name = "Symmetry"
	_symmetry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_symmetry.focus_mode = Control.FOCUS_NONE
	for item in ToolState.SYMMETRY_ITEMS:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var i := _symmetry.item_count
		_symmetry.add_item(str(item.get("label", "")))
		_symmetry.set_item_metadata(i, str(item.get("id", ToolState.SYMMETRY_OFF)))
	_symmetry.item_selected.connect(_on_symmetry)
	_symmetry_row.add_child(lab)
	_symmetry_row.add_child(_symmetry)
	_brush_section.add_child(_symmetry_row)
	_refresh_symmetry_item()


func _on_symmetry(index: int) -> void:
	if _syncing or _symmetry == null:
		return
	if index < 0 or index >= _symmetry.item_count:
		return
	if _symmetry.is_item_disabled(index):
		_sync_symmetry_from_state()
		return
	var mode := str(_symmetry.get_item_metadata(index))
	if mode == ToolState.SYMMETRY_QUAD and not ToolState.can_use_quad():
		EditorFeedback.log("Quad symmetry needs a square map")
		_sync_symmetry_from_state()
		return
	ToolState.set_symmetry(mode)


func _set_brush_metrics_visible(on: bool) -> void:
	if _brush_section == null:
		return
	for path in ["RadiusRow", "Radius", "StrengthRow", "Strength", "FalloffRow", "Falloff", "ShapeRow"]:
		var n := _brush_section.get_node_or_null(path)
		if n:
			(n as CanvasItem).visible = on


func _set_strength_visible(on: bool) -> void:
	if _brush_section == null:
		return
	for path in ["StrengthRow", "Strength"]:
		var n := _brush_section.get_node_or_null(path)
		if n:
			(n as CanvasItem).visible = on


func _refresh_symmetry_item() -> void:
	if _symmetry == null:
		return
	var square := ToolState.can_use_quad()
	var quad_tip := (
		"Four 90° rotations around the map center"
		if square
		else "Quad symmetry needs a square map"
	)
	for i in _symmetry.item_count:
		var id := str(_symmetry.get_item_metadata(i))
		if id == ToolState.SYMMETRY_QUAD:
			_symmetry.set_item_disabled(i, not square)
			_symmetry.set_item_tooltip(i, quad_tip)
	_symmetry.tooltip_text = _symmetry_why()


func _symmetry_why() -> String:
	if ToolState.symmetry == ToolState.SYMMETRY_QUAD and not ToolState.can_use_quad():
		return "Quad symmetry needs a square map"
	return "Mirror or rotate stamps and placements around the map center"


func _sync_symmetry_from_state() -> void:
	if _symmetry == null:
		return
	var was := _syncing
	_syncing = true
	var want := ToolState.normalize_symmetry(ToolState.symmetry)
	for i in _symmetry.item_count:
		if str(_symmetry.get_item_metadata(i)) == want:
			_symmetry.select(i)
			break
	_refresh_symmetry_item()
	_syncing = was


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
	# list does not keep a highlight from the previous map. World (and its
	# atlas) can change here too, so the swatches have to follow.
	_fill()
	if ToolState.armed.is_empty():
		_list.deselect_all()
	refresh_swatches()
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
	if n != _sel_count:
		_sel_count = n
		_select_summary.text = "%d selected" % n
	_refresh_select_actions()


func _build_select_tools() -> void:
	if _select_section == null:
		return
	var qrow := HBoxContainer.new()
	qrow.name = "QueryRow"
	qrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query_edit = LineEdit.new()
	_query_edit.name = "QueryEdit"
	_query_edit.placeholder_text = "class:av* team:1"
	_query_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query_edit.tooltip_text = EditActions.OBJECT_QUERY_HELP
	_query_edit.text_changed.connect(func(_t: String) -> void: _refresh_select_actions())
	_query_edit.text_submitted.connect(func(_t: String) -> void: _on_query_select())
	_query_select = Button.new()
	_query_select.name = "QuerySelect"
	_query_select.text = "Select"
	_query_select.focus_mode = Control.FOCUS_NONE
	_query_select.pressed.connect(_on_query_select)
	_query_add = Button.new()
	_query_add.name = "QueryAdd"
	_query_add.text = "Add"
	_query_add.focus_mode = Control.FOCUS_NONE
	_query_add.pressed.connect(_on_query_add)
	qrow.add_child(_query_edit)
	qrow.add_child(_query_select)
	qrow.add_child(_query_add)
	_select_section.add_child(qrow)
	var trow := HBoxContainer.new()
	trow.name = "BatchTeamRow"
	trow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_batch_team_btn = Button.new()
	_batch_team_btn.name = "BatchTeamApply"
	_batch_team_btn.text = "Set team →"
	_batch_team_btn.focus_mode = Control.FOCUS_NONE
	_batch_team_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_batch_team_btn.pressed.connect(_on_batch_team)
	_batch_team = SpinBox.new()
	_batch_team.name = "BatchTeam"
	_batch_team.min_value = 0
	_batch_team.max_value = 15
	_batch_team.step = 1
	_batch_team.rounded = true
	_batch_team.custom_minimum_size.x = 72
	trow.add_child(_batch_team_btn)
	trow.add_child(_batch_team)
	_select_section.add_child(trow)
	_replace_btn = Button.new()
	_replace_btn.name = "ReplaceClass"
	_replace_btn.text = "Replace class…"
	_replace_btn.focus_mode = Control.FOCUS_NONE
	_replace_btn.pressed.connect(_on_replace_class)
	_select_section.add_child(_replace_btn)
	_copy_btn = Button.new()
	_copy_btn.name = "CopyToVariant"
	_copy_btn.text = "Copy to variant…"
	_copy_btn.focus_mode = Control.FOCUS_NONE
	_copy_btn.pressed.connect(_on_copy_to_variant)
	_copy_menu = PopupMenu.new()
	_copy_menu.name = "CopyToVariantMenu"
	_copy_btn.add_child(_copy_menu)
	_copy_menu.id_pressed.connect(_on_copy_variant_picked)
	_select_section.add_child(_copy_btn)
	var hint := _select_section.get_node_or_null("SelectHint") as Label
	if hint:
		hint.text = "Drag the gizmo to move/rotate. Arrows nudge 1 m (Shift 5 m). R rotate +15° (Shift+R +90°). Snap overrides the step."
		_select_section.move_child(hint, -1)
	_ensure_replace_dialog()
	_refresh_select_actions()


func _build_snap_tools() -> void:
	if _select_section == null or _snap_row != null:
		return
	_snap_row = HBoxContainer.new()
	_snap_row.name = "SnapRow"
	_snap_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var glab := Label.new()
	glab.text = "Grid"
	_snap_grid = OptionButton.new()
	_snap_grid.name = "SnapGrid"
	_snap_grid.focus_mode = Control.FOCUS_NONE
	_snap_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in [
		{"v": 0.0, "t": "Off"},
		{"v": 1.0, "t": "1 m"},
		{"v": 5.0, "t": "5 m"},
		{"v": 10.0, "t": "10 m"},
		{"v": 20.0, "t": "20 m"},
	]:
		var i := _snap_grid.item_count
		_snap_grid.add_item(str(item["t"]))
		_snap_grid.set_item_metadata(i, float(item["v"]))
	_snap_grid.item_selected.connect(_on_snap_grid)
	var alab := Label.new()
	alab.text = "Angle"
	_snap_angle = OptionButton.new()
	_snap_angle.name = "SnapAngle"
	_snap_angle.focus_mode = Control.FOCUS_NONE
	_snap_angle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in [
		{"v": 0.0, "t": "Off"},
		{"v": 15.0, "t": "15°"},
		{"v": 45.0, "t": "45°"},
		{"v": 90.0, "t": "90°"},
	]:
		var i := _snap_angle.item_count
		_snap_angle.add_item(str(item["t"]))
		_snap_angle.set_item_metadata(i, float(item["v"]))
	_snap_angle.item_selected.connect(_on_snap_angle)
	_snap_row.add_child(glab)
	_snap_row.add_child(_snap_grid)
	_snap_row.add_child(alab)
	_snap_row.add_child(_snap_angle)
	_select_section.add_child(_snap_row)
	var hint := _select_section.get_node_or_null("SelectHint")
	if hint:
		_select_section.move_child(hint, -1)
	_sync_snap_from_state()


func _on_snap_grid(index: int) -> void:
	if _syncing or _snap_grid == null:
		return
	if index < 0 or index >= _snap_grid.item_count:
		return
	var v := float(_snap_grid.get_item_metadata(index))
	ToolState.set_snap_grid(v)
	EditorFeedback.log("snap grid %s" % ("off" if v <= 0.0 else "%.0f m" % v))


func _on_snap_angle(index: int) -> void:
	if _syncing or _snap_angle == null:
		return
	if index < 0 or index >= _snap_angle.item_count:
		return
	var v := float(_snap_angle.get_item_metadata(index))
	ToolState.set_snap_angle(v)
	EditorFeedback.log("snap angle %s" % ("off" if v <= 0.0 else "%.0f°" % v))


func _sync_snap_from_state() -> void:
	if _snap_grid == null or _snap_angle == null:
		return
	var was := _syncing
	_syncing = true
	_select_snap_item(_snap_grid, ToolState.snap_grid_m)
	_select_snap_item(_snap_angle, ToolState.snap_angle)
	_snap_grid.tooltip_text = "Snap gizmo, nudges, and Place to this grid"
	_snap_angle.tooltip_text = "Snap gizmo yaw and R-rotate to this increment"
	_syncing = was


func _select_snap_item(btn: OptionButton, value: float) -> void:
	var best := 0
	var best_d := INF
	for i in btn.item_count:
		var d := absf(float(btn.get_item_metadata(i)) - value)
		if d < best_d:
			best_d = d
			best = i
	btn.select(best)


func _ensure_replace_dialog() -> void:
	if _replace_dlg != null:
		return
	_replace_dlg = ConfirmationDialog.new()
	_replace_dlg.name = "ReplaceClassDialog"
	_replace_dlg.title = "Replace class"
	_replace_dlg.ok_button_text = "Replace"
	_replace_dlg.dialog_hide_on_ok = false
	_replace_dlg.min_size = Vector2i(340, 380)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_replace_search = LineEdit.new()
	_replace_search.name = "ReplaceClassSearch"
	_replace_search.placeholder_text = "Search classes…"
	_replace_search.text_changed.connect(func(t: String) -> void:
		_replace_filter = t.strip_edges()
		_fill_replace_list()
	)
	_replace_list = ItemList.new()
	_replace_list.name = "ReplaceClassList"
	_replace_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_replace_list.custom_minimum_size = Vector2(280, 220)
	_replace_list.item_selected.connect(func(_i: int) -> void: _sync_replace_ok())
	_replace_list.item_activated.connect(func(_i: int) -> void: _commit_replace_class())
	box.add_child(_replace_search)
	box.add_child(_replace_list)
	_replace_dlg.add_child(box)
	_replace_dlg.confirmed.connect(_commit_replace_class)
	_replace_dlg.canceled.connect(func() -> void: _pending_replace = {})
	add_child(_replace_dlg)
	_runtime_dlg = ConfirmationDialog.new()
	_runtime_dlg.name = "RuntimeCloneDialog"
	_runtime_dlg.title = "Runtime class"
	_runtime_dlg.ok_button_text = "Replace anyway"
	_runtime_dlg.confirmed.connect(_commit_runtime_replace)
	_runtime_dlg.canceled.connect(func() -> void:
		_pending_replace = {}
		EditorFeedback.log("replace cancelled")
	)
	add_child(_runtime_dlg)


func _query_block_reason() -> String:
	if not MapState.has_session:
		return "open a map first"
	if _query_edit == null:
		return "enter a query"
	var parsed := EditActions.parse_object_query(_query_edit.text)
	if not bool(parsed.get("ok", false)):
		return str(parsed.get("error", "invalid query"))
	return ""


func _batch_block_reason() -> String:
	if not MapState.has_session:
		return "open a map first"
	if MapState.selected_ids.is_empty():
		return "nothing selected"
	return ""


func _replace_block_reason() -> String:
	var why := _batch_block_reason()
	if not why.is_empty():
		return why
	var classes: Variant = _index.get("classes", [])
	if typeof(classes) != TYPE_ARRAY or (classes as Array).is_empty():
		return "no classes in the palette"
	return ""


func _why_tip(reason: String, ok_tip: String) -> String:
	if reason.is_empty():
		return ok_tip
	return reason[0].to_upper() + reason.substr(1)


func _refresh_select_actions() -> void:
	var qwhy := _query_block_reason()
	if _query_select:
		_query_select.disabled = not qwhy.is_empty()
		_query_select.tooltip_text = _why_tip(qwhy, "Replace the selection with query matches")
	if _query_add:
		_query_add.disabled = not qwhy.is_empty()
		_query_add.tooltip_text = _why_tip(qwhy, "Add query matches to the selection")
	if _query_edit:
		_query_edit.tooltip_text = EditActions.OBJECT_QUERY_HELP
	var bwhy := _batch_block_reason()
	if _batch_team_btn:
		_batch_team_btn.disabled = not bwhy.is_empty()
		_batch_team_btn.tooltip_text = _why_tip(bwhy, "Set team on the current selection (one undo)")
	if _batch_team:
		_batch_team.editable = bwhy.is_empty()
		_batch_team.tooltip_text = _why_tip(bwhy, "Team 0–15")
	var rwhy := _replace_block_reason()
	if _replace_btn:
		_replace_btn.disabled = not rwhy.is_empty()
		_replace_btn.tooltip_text = _why_tip(rwhy, "Replace prjid of every selected object (one undo)")
	var cwhy := EditActions.copy_to_variant_block_reason()
	if _copy_btn:
		_copy_btn.disabled = not cwhy.is_empty()
		_copy_btn.tooltip_text = _why_tip(cwhy, "Copy the selection into another variant (new ids, one undo)")
	var sig := ",".join(MapState.selected_ids)
	if sig != _sel_ids_sig:
		_sel_ids_sig = sig
		if _batch_team and not MapState.selected_ids.is_empty():
			var rec := MapState.find_object(MapState.selected_ids[0])
			if not rec.is_empty():
				_batch_team.set_value_no_signal(int(rec.get("team", 0)))


func _on_query_select() -> void:
	var why := _query_block_reason()
	if not why.is_empty():
		EditorFeedback.log(why)
		return
	EditActions.select_by_query(_query_edit.text, false, EditorFeedback.log)
	_refresh_selection()
	selection_query_applied.emit()


func _on_query_add() -> void:
	var why := _query_block_reason()
	if not why.is_empty():
		EditorFeedback.log(why)
		return
	EditActions.select_by_query(_query_edit.text, true, EditorFeedback.log)
	_refresh_selection()
	selection_query_applied.emit()


func _on_batch_team() -> void:
	var why := _batch_block_reason()
	if not why.is_empty():
		EditorFeedback.log(why)
		return
	EditActions.set_selection_team(int(_batch_team.value), EditorFeedback.log)


func _on_copy_to_variant() -> void:
	var why := EditActions.copy_to_variant_block_reason()
	if not why.is_empty():
		EditorFeedback.log(why)
		return
	EditActions.fill_variant_picker(_copy_menu)
	if _copy_menu.get_item_count() == 0:
		EditorFeedback.log("no other variants")
		return
	var r := _copy_btn.get_global_rect()
	_copy_menu.popup(Rect2i(int(r.position.x), int(r.position.y + r.size.y), 0, 0))


func _on_copy_variant_picked(id: int) -> void:
	var idx := _copy_menu.get_item_index(id)
	if idx < 0:
		return
	var dest := str(_copy_menu.get_item_metadata(idx))
	EditActions.copy_selection_to_variant(dest, EditorFeedback.log)


func _on_replace_class() -> void:
	var why := _replace_block_reason()
	if not why.is_empty():
		EditorFeedback.log(why)
		return
	_pending_replace = {}
	_replace_filter = ""
	if _replace_search:
		_replace_search.text = ""
	_fill_replace_list()
	_replace_dlg.popup_centered()


func _fill_replace_list() -> void:
	if _replace_list == null:
		return
	_replace_list.clear()
	var classes: Array = _index.get("classes", [])
	var q := _replace_filter.to_lower()
	var added := 0
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
		var i := _replace_list.add_item(text)
		_replace_list.set_item_metadata(i, rec)
		_replace_list.set_item_disabled(i, not legal)
		added += 1
	if added == 0:
		var i := _replace_list.add_item("No classes match")
		_replace_list.set_item_metadata(i, {})
		_replace_list.set_item_disabled(i, true)
	else:
		_replace_list.sort_items_by_text()
	_sync_replace_ok()


func _sync_replace_ok() -> void:
	if _replace_dlg == null:
		return
	var ok := _replace_dlg.get_ok_button()
	if ok == null:
		return
	ok.disabled = _picked_replace_class().is_empty()


func _picked_replace_class() -> Dictionary:
	if _replace_list == null:
		return {}
	var sel := _replace_list.get_selected_items()
	if sel.is_empty():
		return {}
	var i: int = sel[0]
	if _replace_list.is_item_disabled(i):
		return {}
	var rec = _replace_list.get_item_metadata(i)
	if typeof(rec) != TYPE_DICTIONARY or rec.is_empty():
		return {}
	return rec


func _commit_replace_class() -> void:
	var rec := _picked_replace_class()
	if rec.is_empty():
		EditorFeedback.log("pick a class")
		return
	var result := EditActions.replace_selection_class(
		str(rec.get("prjid", "")), EditorFeedback.log, rec, false
	)
	if bool(result.get("needs_confirm", false)):
		_pending_replace = rec
		var mode := str(rec.get("placement_mode", "runtime"))
		_runtime_dlg.dialog_text = (
			"%s uses placement_mode=%s (not bzn). Replacing selected objects with it will save as a runtime clone, not a verified BZN template. Continue?"
			% [rec.get("prjid", ""), mode]
		)
		_runtime_dlg.popup_centered()
		return
	_replace_dlg.hide()


func _commit_runtime_replace() -> void:
	var rec := _pending_replace.duplicate(true)
	_pending_replace = {}
	if rec.is_empty():
		EditorFeedback.log("pick a class")
		return
	EditActions.replace_selection_class(
		str(rec.get("prjid", "")), EditorFeedback.log, rec, true
	)
	if _replace_dlg:
		_replace_dlg.hide()


func _build_terrain_select() -> void:
	if _terrain_section != null:
		return
	var box := get_node_or_null("Box")
	if box == null:
		return
	_terrain_section = VBoxContainer.new()
	_terrain_section.name = "TerrainSelSection"
	_terrain_section.visible = false
	_terrain_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terrain_section.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Terrain selection"
	_terrain_section.add_child(title)
	_wand_row = HBoxContainer.new()
	_wand_row.name = "WandRow"
	_wand_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wlab := Label.new()
	wlab.text = "Tolerance"
	wlab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wand_tol = SpinBox.new()
	_wand_tol.name = "WandTolerance"
	_wand_tol.min_value = 0.0
	_wand_tol.max_value = 200.0
	_wand_tol.step = 0.5
	_wand_tol.suffix = "m"
	_wand_tol.custom_minimum_size.x = 88
	_wand_tol.value = ToolState.wand_tolerance_m
	_wand_tol.value_changed.connect(func(v: float) -> void:
		ToolState.set_wand_tolerance(v)
	)
	_wand_row.add_child(wlab)
	_wand_row.add_child(_wand_tol)
	_terrain_section.add_child(_wand_row)
	var frow := HBoxContainer.new()
	frow.name = "FeatherRow"
	frow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feather_spin = SpinBox.new()
	_feather_spin.name = "FeatherRadius"
	_feather_spin.min_value = 0.0
	_feather_spin.max_value = 200.0
	_feather_spin.step = 1.0
	_feather_spin.suffix = "m"
	_feather_spin.custom_minimum_size.x = 88
	_feather_spin.value = ToolState.feather_radius_m
	_feather_spin.value_changed.connect(func(v: float) -> void:
		ToolState.set_feather_radius(v)
	)
	_feather_btn = Button.new()
	_feather_btn.name = "FeatherApply"
	_feather_btn.text = "Feather…"
	_feather_btn.focus_mode = Control.FOCUS_NONE
	_feather_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feather_btn.pressed.connect(_on_feather)
	frow.add_child(_feather_btn)
	frow.add_child(_feather_spin)
	_terrain_section.add_child(frow)
	var grow := HBoxContainer.new()
	grow.name = "GrowRow"
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grow_spin = SpinBox.new()
	_grow_spin.name = "GrowCells"
	_grow_spin.min_value = 1
	_grow_spin.max_value = 64
	_grow_spin.step = 1
	_grow_spin.rounded = true
	_grow_spin.suffix = "cells"
	_grow_spin.custom_minimum_size.x = 88
	_grow_spin.value = ToolState.grow_cells
	_grow_spin.value_changed.connect(func(v: float) -> void:
		ToolState.set_grow_cells(int(v))
	)
	_grow_btn = Button.new()
	_grow_btn.name = "GrowApply"
	_grow_btn.text = "Grow"
	_grow_btn.focus_mode = Control.FOCUS_NONE
	_grow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grow_btn.pressed.connect(_on_grow)
	_shrink_btn = Button.new()
	_shrink_btn.name = "ShrinkApply"
	_shrink_btn.text = "Shrink"
	_shrink_btn.focus_mode = Control.FOCUS_NONE
	_shrink_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shrink_btn.pressed.connect(_on_shrink)
	grow.add_child(_grow_btn)
	grow.add_child(_shrink_btn)
	grow.add_child(_grow_spin)
	_terrain_section.add_child(grow)
	_mat_sel_btn = Button.new()
	_mat_sel_btn.name = "SelectByMaterial"
	_mat_sel_btn.text = "Select by material"
	_mat_sel_btn.focus_mode = Control.FOCUS_NONE
	_mat_sel_btn.pressed.connect(_on_select_by_material)
	_terrain_section.add_child(_mat_sel_btn)
	_terrain_hint = Label.new()
	_terrain_hint.name = "TerrainSelHint"
	_terrain_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_terrain_hint.add_theme_color_override("font_color", Color(0.62, 0.62, 0.64, 1))
	_terrain_hint.text = "Empty mask = no selection = all cells editable. Ctrl+A / Ctrl+D / Ctrl+Shift+I."
	_terrain_section.add_child(_terrain_hint)
	box.add_child(_terrain_section)
	_refresh_terrain_actions()


func _build_clone_tools() -> void:
	if _brush_section == null or _clone_row != null:
		return
	_clone_row = HBoxContainer.new()
	_clone_row.name = "CloneRow"
	_clone_row.visible = false
	_clone_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clone_mats = CheckBox.new()
	_clone_mats.name = "CloneMaterials"
	_clone_mats.text = "Clone materials"
	_clone_mats.focus_mode = Control.FOCUS_NONE
	_clone_mats.button_pressed = ToolState.clone_materials
	_clone_mats.toggled.connect(func(on: bool) -> void:
		ToolState.set_clone_materials(on)
	)
	_clone_match = CheckBox.new()
	_clone_match.name = "MatchHeight"
	_clone_match.text = "Match height"
	_clone_match.tooltip_text = "Enabled: sampled absolute height. Disabled: relative to the cursor."
	_clone_match.focus_mode = Control.FOCUS_NONE
	_clone_match.button_pressed = ToolState.clone_match_height
	_clone_match.toggled.connect(func(on: bool) -> void:
		ToolState.set_clone_match_height(on)
	)
	_clone_row.add_child(_clone_mats)
	_clone_row.add_child(_clone_match)
	_brush_section.add_child(_clone_row)


func _set_clone_visible(on: bool) -> void:
	if _clone_row:
		_clone_row.visible = on
	if on and _clone_mats:
		_clone_mats.set_pressed_no_signal(ToolState.clone_materials)
		if ToolState.has_clone_source():
			_clone_mats.tooltip_text = "Also copy material tile words from the source-relative region"
		else:
			_clone_mats.tooltip_text = "Ctrl+click the ground to set the clone source first"
	if on and _clone_match:
		_clone_match.set_pressed_no_signal(ToolState.clone_match_height)


func _set_noise_visible(on: bool) -> void:
	if _brush_section == null:
		return
	for path in ["NoiseScaleRow", "NoiseScale", "NoiseContrastRow", "NoiseContrast"]:
		var n := _brush_section.get_node_or_null(path)
		if n:
			(n as CanvasItem).visible = on


func _sel_block_reason() -> String:
	if not MapState.has_session:
		return "open a map first"
	if not MapState.has_heightmap():
		return "map has no heightmap"
	if MapState.selection_empty():
		return "no selection"
	return ""


func _mat_sel_block_reason() -> String:
	if not MapState.has_session:
		return "open a map first"
	if not MapState.has_heightmap():
		return "map has no heightmap"
	if MapState.mat_grid_x < 1:
		return "map has no material grid"
	return ""


func _refresh_terrain_actions() -> void:
	if _feather_btn == null:
		return
	var why := _sel_block_reason()
	_feather_btn.disabled = not why.is_empty()
	_feather_btn.tooltip_text = _why_tip(why, "Box-blur the selection by the radius in metres")
	if _feather_spin:
		_feather_spin.editable = why.is_empty()
		_feather_spin.tooltip_text = _why_tip(why, "Feather radius in metres")
	if _grow_btn:
		_grow_btn.disabled = not why.is_empty()
		_grow_btn.tooltip_text = _why_tip(why, "Dilate the selection by N cells")
	if _shrink_btn:
		_shrink_btn.disabled = not why.is_empty()
		_shrink_btn.tooltip_text = _why_tip(why, "Erode the selection by N cells")
	if _grow_spin:
		_grow_spin.editable = why.is_empty()
		_grow_spin.tooltip_text = _why_tip(why, "Cells to grow or shrink")
	var mwhy := _mat_sel_block_reason()
	if _mat_sel_btn:
		_mat_sel_btn.disabled = not mwhy.is_empty()
		var mat := ToolState.paint_material
		_mat_sel_btn.text = "Select by material (%d)" % mat
		_mat_sel_btn.tooltip_text = _why_tip(
			mwhy,
			"Select every cell whose material tile base is %s" % MaterialPalette.type_name(mat),
		)
	if _wand_tol:
		var wwhy := "open a map first" if not MapState.has_session else ""
		_wand_tol.editable = wwhy.is_empty()
		_wand_tol.tooltip_text = _why_tip(wwhy, "Height tolerance in metres for the magic wand")


func _on_feather() -> void:
	EditActions.feather_terrain(ToolState.feather_radius_m, EditorFeedback.log)


func _on_grow() -> void:
	EditActions.grow_terrain(ToolState.grow_cells, EditorFeedback.log)


func _on_shrink() -> void:
	EditActions.shrink_terrain(ToolState.grow_cells, EditorFeedback.log)


func _on_select_by_material() -> void:
	EditActions.select_terrain_by_material(EditorFeedback.log)


func _sync_from_state() -> void:
	_syncing = true
	_radius.value = ToolState.radius_m
	_strength.value = ToolState.strength
	_falloff.value = ToolState.falloff
	_radius_val.text = "%d m" % int(ToolState.radius_m)
	_strength_val.text = "%d%%" % int(ToolState.strength * 100.0)
	_falloff_val.text = "%d%%" % int(ToolState.falloff * 100.0)
	if _noise_scale:
		_noise_scale.value = ToolState.noise_scale
	if _noise_contrast:
		_noise_contrast.value = ToolState.noise_contrast
	if _noise_scale_val:
		_noise_scale_val.text = "%.1f" % ToolState.noise_scale
	if _noise_contrast_val:
		_noise_contrast_val.text = "%.1f" % ToolState.noise_contrast
	_sync_shape_buttons()
	_highlight_swatch()
	_sync_symmetry_from_state()
	_sync_snap_from_state()
	_sync_paint_tile_from_state()
	_syncing = false


func _sync_paint_tile_from_state() -> void:
	var was := _syncing
	_syncing = true
	if _kind_solid:
		_kind_solid.button_pressed = ToolState.paint_kind == "solid"
	if _kind_cap:
		var can_cap := MaterialPalette.has_kind_for(ToolState.paint_material, "cap")
		_kind_cap.disabled = not can_cap
		_kind_cap.tooltip_text = (
			"This material has no cap tiles in the world atlas."
			if not can_cap else "Straight edge between two materials."
		)
		_kind_cap.button_pressed = ToolState.paint_kind == "cap"
	if _kind_diag:
		var can_d := MaterialPalette.has_kind_for(ToolState.paint_material, "diag")
		_kind_diag.disabled = not can_d
		_kind_diag.tooltip_text = (
			"This material has no corner tiles in the world atlas."
			if not can_d else "Diagonal corner between two materials."
		)
		_kind_diag.button_pressed = ToolState.paint_kind == "diag"
	_fill_tile_choices()
	if _rot_btn:
		if ToolState.paint_kind == "diag":
			_rot_btn.text = "Facing  %s" % ToolState.paint_diag_facing()
			_rot_btn.tooltip_text = "Stock corner tiles face left in the atlas. Rotate that tile onto the other corners."
		else:
			_rot_btn.text = "Rotate  %d°" % (ToolState.paint_rot * 90)
			_rot_btn.tooltip_text = "Rotate the cap tile."
	if _flip_box and _flip_box.button_pressed != (ToolState.paint_flip != 0):
		_flip_box.button_pressed = ToolState.paint_flip != 0
	# Keep the tile grid and Facing row in the layout on Solid so the rail
	# does not jump when the mapmaker switches to Cap or Corner.
	var pair := ToolState.paint_kind != "solid"
	if _rot_btn:
		_rot_btn.disabled = not pair
	if _flip_box:
		_flip_box.disabled = not pair
	if _match_edges and _match_edges.button_pressed != ToolState.paint_match_edges:
		_match_edges.button_pressed = ToolState.paint_match_edges
	_syncing = was


func _sync_shape_buttons() -> void:
	_shape_circle.button_pressed = ToolState.shape != "square"
	_shape_square.button_pressed = ToolState.shape == "square"


func _ensure_filter_icon() -> void:
	# OptionButton.clear()/select() reset the button icon to the selected
	# item's (none), so the filter glyph must be re-applied after both.
	if _category and _category.icon == null:
		_category.icon = EditorIcons.texture("filter")


func _apply_chrome_icons() -> void:
	if _search and _search.right_icon == null:
		EditorIcons.apply_line_edit(_search, "search")
	_ensure_filter_icon()
	if _select_summary:
		EditorIcons.prepend_icon(_select_summary, "select")
	var terrain_title := find_child("TerrainSelSection", true, false)
	if terrain_title:
		for child in terrain_title.get_children():
			if child is Label and str(child.text).begins_with("Terrain"):
				EditorIcons.prepend_icon(child, "qsel")
				break
	if _query_select:
		EditorIcons.apply_button(_query_select, "select", true)
	if _batch_team_btn:
		EditorIcons.apply_button(_batch_team_btn, "team", true)
