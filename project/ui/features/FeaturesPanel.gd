extends PanelContainer
## Water bodies and plant regions. Selection is the active mask target.

signal collapsed_changed(collapsed: bool)

const _SCOPES: PackedStringArray = ["all", "_S", "_ST", "_SW"]
const _SELECT := Color(0.24, 0.42, 0.62, 1)
const _ROW := Color(0.16, 0.16, 0.17, 1)

@onready var _paint: Button = %PaintRegion
@onready var _add_water: Button = %AddWater
@onready var _remove_water: Button = %RemoveWater
@onready var _add_plant: Button = %AddPlant
@onready var _remove_plant: Button = %RemovePlant
@onready var _water_list: VBoxContainer = %WaterList
@onready var _plant_list: VBoxContainer = %PlantList

var _collapse: Button
var _collapsed: bool = false
var _building: bool = false
var _rebuild_queued: bool = false
var _sel_kind: String = ""
var _sel_stem: String = ""
var _field_pending: bool = false
var _field_group: String = ""
var _field_stem: String = ""
var _field_key: String = ""
var _field_before: Variant
var _field_timer: Timer


func _ready() -> void:
	_install_collapse()
	_paint.toggled.connect(_on_paint_toggled)
	_add_water.pressed.connect(_on_add_water)
	_remove_water.pressed.connect(_on_remove_water)
	_add_plant.pressed.connect(_on_add_plant)
	_remove_plant.pressed.connect(_on_remove_plant)
	_field_timer = Timer.new()
	_field_timer.one_shot = true
	_field_timer.wait_time = 0.35
	_field_timer.timeout.connect(_commit_pending_field)
	add_child(_field_timer)
	MapState.session_changed.connect(_on_session)
	MapState.features_changed.connect(_on_features_changed)
	MapState.water_changed.connect(_on_water_state)
	ToolState.mask_target_changed.connect(_on_mask_target)
	ToolState.mask_paint_changed.connect(_on_mask_paint)
	_apply_header_icons()
	_rebuild()


func is_collapsed() -> bool:
	return _collapsed


func set_collapsed(on: bool) -> void:
	if _collapsed == on:
		return
	_collapsed = on
	_apply_collapse()
	collapsed_changed.emit(on)


func _install_collapse() -> void:
	var title := find_child("Title", true, false) as Label
	if title == null:
		return
	_collapse = PanelCollapse.make_toggle("Features", true)
	var parent := title.get_parent()
	parent.add_child(_collapse)
	parent.move_child(_collapse, title.get_index())
	title.visible = false
	_collapse.toggled.connect(func(on: bool) -> void: set_collapsed(not on))


func _apply_collapse() -> void:
	var box := find_child("Box", true, false) as VBoxContainer
	if box:
		for child in box.get_children():
			if child.name == "Head":
				continue
			child.visible = not _collapsed
	custom_minimum_size.y = 40.0 if _collapsed else 160.0
	PanelCollapse.apply_toggle(_collapse, "Features", not _collapsed)


func _apply_header_icons() -> void:
	if _paint and _paint.icon == null:
		EditorIcons.apply_button(_paint, "paint", true)


func _exit_tree() -> void:
	_commit_pending_field()


func _on_session() -> void:
	_field_pending = false
	if _field_timer:
		_field_timer.stop()
	_sel_kind = ""
	_sel_stem = ""
	_rebuild()


func _on_features_changed() -> void:
	if _building or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _on_water_state(level: float) -> void:
	if _building:
		return
	var waters: Array = MapState.features.get("water", [])
	if typeof(waters) != TYPE_ARRAY or waters.is_empty():
		return
	if typeof(waters[0]) != TYPE_DICTIONARY:
		return
	var stem := str(waters[0].get("stem", ""))
	var row := _water_list.get_node_or_null("WaterRow_%s" % stem) as Control
	if row == null:
		return
	var box: SpinBox = row.find_child("Level", true, false)
	if box == null:
		return
	_building = true
	box.value = level
	_building = false


func _on_mask_target() -> void:
	if _building:
		return
	_sel_kind = ToolState.mask_kind
	_sel_stem = ToolState.mask_stem
	_highlight_rows()
	_refresh_enablement()


func _on_mask_paint() -> void:
	if _paint.button_pressed != ToolState.mask_paint:
		_paint.set_pressed_no_signal(ToolState.mask_paint)
	_refresh_enablement()


func _rebuild() -> void:
	_rebuild_queued = false
	_building = true
	_clear_list(_water_list)
	_clear_list(_plant_list)
	for rec in MapState.features.get("water", []):
		if typeof(rec) == TYPE_DICTIONARY:
			_water_list.add_child(_make_water_row(rec))
	for rec in MapState.features.get("plants", []):
		if typeof(rec) == TYPE_DICTIONARY:
			_plant_list.add_child(_make_plant_row(rec))
	if not _sel_stem.is_empty():
		if MapState.find_feature(_sel_kind, _sel_stem).is_empty():
			_sel_kind = ""
			_sel_stem = ""
	if _sel_stem.is_empty() and not ToolState.mask_stem.is_empty():
		if not MapState.find_feature(ToolState.mask_kind, ToolState.mask_stem).is_empty():
			_sel_kind = ToolState.mask_kind
			_sel_stem = ToolState.mask_stem
	_building = false
	if _sel_stem.is_empty():
		if not ToolState.mask_stem.is_empty():
			ToolState.clear_mask_target()
	elif ToolState.mask_stem != _sel_stem or ToolState.mask_kind != _sel_kind:
		ToolState.set_mask_target(_sel_kind, _sel_stem)
	_highlight_rows()
	_refresh_enablement()


func _clear_list(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()


func _make_water_row(rec: Dictionary) -> Control:
	var stem := str(rec.get("stem", ""))
	var row := _row_shell("WaterRow_%s" % stem, "water", stem)
	var edit := _stem_edit(stem)
	edit.text_submitted.connect(func(t: String) -> void: _commit_stem("water", stem, t))
	edit.focus_exited.connect(func() -> void: _commit_stem("water", stem, edit.text))
	var level := SpinBox.new()
	level.name = "Level"
	level.min_value = 0.0
	level.max_value = 820.0
	level.step = 0.5
	level.value = float(rec.get("level_m", 0.0))
	level.suffix = "m"
	level.custom_minimum_size.x = 78
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level.tooltip_text = "Water surface height"
	level.value_changed.connect(func(v: float) -> void: _on_field("water", stem, "level_m", v))
	var scope := OptionButton.new()
	scope.name = "Scope"
	scope.custom_minimum_size.x = 56
	for s in _SCOPES:
		scope.add_item(s)
	_select_scope(scope, str(rec.get("variant_scope", "all")))
	scope.tooltip_text = "BZN variants that receive this water"
	scope.item_selected.connect(func(i: int) -> void: _on_scope("water", stem, i))
	var box: HBoxContainer = row.get_node("Box")
	box.add_child(edit)
	box.add_child(level)
	box.add_child(scope)
	return row


func _make_plant_row(rec: Dictionary) -> Control:
	var stem := str(rec.get("stem", ""))
	var row := _row_shell("PlantRow_%s" % stem, "plants", stem)
	var edit := _stem_edit(stem)
	edit.text_submitted.connect(func(t: String) -> void: _commit_stem("plants", stem, t))
	edit.focus_exited.connect(func() -> void: _commit_stem("plants", stem, edit.text))
	var density := SpinBox.new()
	density.name = "Density"
	density.min_value = 1.0
	density.max_value = 10000.0
	density.step = 1.0
	density.rounded = true
	density.value = int(rec.get("density", 260))
	density.custom_minimum_size.x = 72
	density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	density.tooltip_text = "Plant instances"
	density.value_changed.connect(func(v: float) -> void: _on_field("plants", stem, "density", int(v)))
	var seed := SpinBox.new()
	seed.name = "Seed"
	seed.min_value = 0.0
	seed.max_value = 2147483647.0
	seed.step = 1.0
	seed.rounded = true
	seed.value = int(rec.get("seed", 0))
	seed.custom_minimum_size.x = 64
	seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed.tooltip_text = "Plant scatter seed"
	seed.value_changed.connect(func(v: float) -> void: _on_field("plants", stem, "seed", int(v)))
	var box: HBoxContainer = row.get_node("Box")
	box.add_child(edit)
	box.add_child(density)
	box.add_child(seed)
	return row


func _row_shell(node_name: String, kind: String, stem: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select(kind, stem)
	)
	var box := HBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)
	return row


func _stem_edit(stem: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = "Stem"
	edit.max_length = 8
	edit.text = stem
	edit.custom_minimum_size.x = 58
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.tooltip_text = "Feature stem (≤8 alphanumeric)"
	edit.focus_entered.connect(func() -> void:
		var row := edit.get_parent().get_parent()
		if row.name.begins_with("WaterRow_"):
			_select("water", stem)
		elif row.name.begins_with("PlantRow_"):
			_select("plants", stem)
	)
	return edit


func _select(kind: String, stem: String) -> void:
	if _building:
		_sel_kind = kind
		_sel_stem = stem
		return
	if _sel_kind == kind and _sel_stem == stem:
		_highlight_rows()
		_refresh_enablement()
		return
	_commit_pending_field()
	_sel_kind = kind
	_sel_stem = stem
	ToolState.set_mask_target(kind, stem)
	_highlight_rows()
	_refresh_enablement()


func _highlight_rows() -> void:
	for child in _water_list.get_children():
		_tint_row(child as Control, _sel_kind == "water" and child.name == "WaterRow_%s" % _sel_stem)
	for child in _plant_list.get_children():
		_tint_row(child as Control, _sel_kind == "plants" and child.name == "PlantRow_%s" % _sel_stem)


func _tint_row(row: Control, on: bool) -> void:
	if row == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = _SELECT if on else _ROW
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	row.add_theme_stylebox_override("panel", sb)


func _on_add_water() -> void:
	if not _can_add():
		EditorFeedback.log(_add_block_reason())
		return
	_commit_pending_field()
	var rec := MapState.add_water_feature()
	if rec.is_empty():
		EditorFeedback.log("could not allocate a water stem")
		return
	var cmd := FeatureCommand.new()
	cmd.kind = FeatureCommand.Kind.ADD
	cmd.group = "water"
	cmd.record = rec.duplicate(true)
	cmd.mask_bytes = MapState.get_mask(str(rec.get("stem", ""))).duplicate()
	UndoStack.push(cmd, true)
	EditorFeedback.log("added water body %s" % rec.get("stem", ""))
	_select("water", str(rec.get("stem", "")))


func _on_add_plant() -> void:
	if not _can_add():
		EditorFeedback.log(_add_block_reason())
		return
	_commit_pending_field()
	var rec := MapState.add_plant_feature()
	if rec.is_empty():
		EditorFeedback.log("could not allocate a plant stem")
		return
	var cmd := FeatureCommand.new()
	cmd.kind = FeatureCommand.Kind.ADD
	cmd.group = "plants"
	cmd.record = rec.duplicate(true)
	cmd.mask_bytes = MapState.get_mask(str(rec.get("stem", ""))).duplicate()
	UndoStack.push(cmd, true)
	EditorFeedback.log("added plant region %s" % rec.get("stem", ""))
	_select("plants", str(rec.get("stem", "")))


func _on_remove_water() -> void:
	if _sel_kind != "water" or _sel_stem.is_empty():
		EditorFeedback.log("select a water body to remove")
		return
	_remove_selected("water")


func _on_remove_plant() -> void:
	if _sel_kind != "plants" or _sel_stem.is_empty():
		EditorFeedback.log("select a plant region to remove")
		return
	_remove_selected("plants")


func _remove_selected(group: String) -> void:
	_commit_pending_field()
	var stem := _sel_stem
	var rec := MapState.find_feature(group, stem).duplicate(true)
	var mask := MapState.get_mask(stem).duplicate()
	if rec.is_empty():
		EditorFeedback.log("no such feature")
		return
	var cmd := FeatureCommand.new()
	cmd.kind = FeatureCommand.Kind.REMOVE
	cmd.group = group
	cmd.record = rec
	cmd.mask_bytes = mask
	MapState.remove_feature(group, stem)
	UndoStack.push(cmd, true)
	var label := "water body" if group == "water" else "plant region"
	EditorFeedback.log("removed %s %s" % [label, stem])
	_sel_kind = ""
	_sel_stem = ""


func _on_field(group: String, stem: String, key: String, value: Variant) -> void:
	if _building:
		return
	if not MapState.has_session:
		EditorFeedback.log("open a map first")
		return
	_select(group, stem)
	if not _field_pending:
		var rec := MapState.find_feature(group, stem)
		_field_before = rec.get(key)
		_field_group = group
		_field_stem = stem
		_field_key = key
		_field_pending = true
	MapState.set_feature_field(group, stem, key, value)
	_field_timer.start()


func _commit_pending_field() -> void:
	if not _field_pending:
		return
	_field_pending = false
	if _field_timer:
		_field_timer.stop()
	var rec := MapState.find_feature(_field_group, _field_stem)
	if rec.is_empty():
		return
	var after: Variant = rec.get(_field_key)
	if _same(_field_before, after):
		return
	var before_rec := rec.duplicate(true)
	before_rec[_field_key] = _field_before
	var cmd := FeatureCommand.new()
	cmd.kind = FeatureCommand.Kind.EDIT
	cmd.group = _field_group
	cmd.stem_before = _field_stem
	cmd.stem_after = _field_stem
	cmd.before = before_rec
	cmd.after = rec.duplicate(true)
	cmd.mask_before = MapState.get_mask(_field_stem).duplicate()
	cmd.mask_after = cmd.mask_before.duplicate()
	UndoStack.push(cmd, true)
	EditorFeedback.log("set %s %s to %s" % [_field_stem, _field_key, str(after)])


func _on_scope(group: String, stem: String, index: int) -> void:
	if _building:
		return
	if index < 0 or index >= _SCOPES.size():
		return
	_commit_pending_field()
	_select(group, stem)
	var rec := MapState.find_feature(group, stem)
	if rec.is_empty():
		return
	var scope := _SCOPES[index]
	if str(rec.get("variant_scope", "all")) == scope:
		return
	var before := rec.duplicate(true)
	MapState.set_feature_field(group, stem, "variant_scope", scope)
	var cmd := FeatureCommand.new()
	cmd.kind = FeatureCommand.Kind.EDIT
	cmd.group = group
	cmd.stem_before = stem
	cmd.stem_after = stem
	cmd.before = before
	cmd.after = rec.duplicate(true)
	cmd.mask_before = MapState.get_mask(stem).duplicate()
	cmd.mask_after = cmd.mask_before.duplicate()
	UndoStack.push(cmd, true)
	EditorFeedback.log("set %s variant_scope to %s" % [stem, scope])


func _commit_stem(group: String, old_stem: String, typed: String) -> void:
	if _building:
		return
	var cleaned := typed.strip_edges()
	var row_name := ("WaterRow_%s" if group == "water" else "PlantRow_%s") % old_stem
	var row := (_water_list if group == "water" else _plant_list).get_node_or_null(row_name)
	var edit: LineEdit = row.find_child("Stem", true, false) if row else null
	if cleaned == old_stem:
		if edit:
			edit.text = old_stem
		return
	_commit_pending_field()
	var err := MapState.validate_feature_stem(cleaned, old_stem)
	if not err.is_empty():
		EditorFeedback.log(err)
		if edit:
			edit.text = old_stem
		return
	var before := MapState.find_feature(group, old_stem).duplicate(true)
	if before.is_empty():
		return
	var mask := MapState.get_mask(old_stem).duplicate()
	err = MapState.rename_feature(group, old_stem, cleaned)
	if not err.is_empty():
		EditorFeedback.log(err)
		if edit:
			edit.text = old_stem
		return
	var after := MapState.find_feature(group, cleaned).duplicate(true)
	var cmd := FeatureCommand.new()
	cmd.kind = FeatureCommand.Kind.EDIT
	cmd.group = group
	cmd.stem_before = old_stem
	cmd.stem_after = cleaned
	cmd.before = before
	cmd.after = after
	cmd.mask_before = mask
	cmd.mask_after = MapState.get_mask(cleaned).duplicate()
	UndoStack.push(cmd, true)
	EditorFeedback.log("renamed %s to %s" % [old_stem, cleaned])
	_sel_kind = group
	_sel_stem = cleaned


func _on_paint_toggled(on: bool) -> void:
	if _building:
		return
	if on and not _can_paint():
		_paint.set_pressed_no_signal(false)
		EditorFeedback.log(_paint_block_reason())
		return
	ToolState.set_mask_paint(on)
	if on:
		EditorFeedback.log("painting %s mask  LMB add  Alt+LMB erase" % ToolState.mask_stem)
	else:
		EditorFeedback.log("mask paint off")


func _refresh_enablement() -> void:
	var session := MapState.has_session
	var grid := MapState.has_heightmap()
	var add_ok := session and grid
	_add_water.disabled = not add_ok
	_add_plant.disabled = not add_ok
	_add_water.tooltip_text = "Add a water body" if add_ok else _add_block_reason()
	_add_plant.tooltip_text = "Add a plant region" if add_ok else _add_block_reason()
	var water_sel := session and _sel_kind == "water" and not _sel_stem.is_empty()
	var plant_sel := session and _sel_kind == "plants" and not _sel_stem.is_empty()
	_remove_water.disabled = not water_sel
	_remove_plant.disabled = not plant_sel
	if not session:
		_remove_water.tooltip_text = "Open a map first"
		_remove_plant.tooltip_text = "Open a map first"
	elif not water_sel:
		_remove_water.tooltip_text = "Select a water body to remove"
	else:
		_remove_water.tooltip_text = "Remove %s" % _sel_stem
	if not session:
		pass
	elif not plant_sel:
		_remove_plant.tooltip_text = "Select a plant region to remove"
	else:
		_remove_plant.tooltip_text = "Remove %s" % _sel_stem
	var paint_ok := _can_paint()
	if not paint_ok and _paint.button_pressed:
		_paint.set_pressed_no_signal(false)
		if ToolState.mask_paint:
			ToolState.set_mask_paint(false)
	_paint.disabled = not paint_ok
	_paint.tooltip_text = "Paint this feature's region" if paint_ok else _paint_block_reason()


func _can_add() -> bool:
	return MapState.has_session and MapState.has_heightmap()


func _can_paint() -> bool:
	return MapState.has_session and MapState.has_heightmap() and not _sel_stem.is_empty()


func _add_block_reason() -> String:
	if not MapState.has_session:
		return "Open a map first"
	if not MapState.has_heightmap():
		return "Map has no heightmap"
	return "Cannot add a feature"


func _paint_block_reason() -> String:
	if not MapState.has_session:
		return "Open a map first"
	if not MapState.has_heightmap():
		return "Map has no heightmap"
	if _sel_stem.is_empty():
		return "Select a water body or plant region"
	return "Cannot paint a region"


func _select_scope(box: OptionButton, scope: String) -> void:
	var want := scope.strip_edges()
	if want.is_empty():
		want = "all"
	for i in _SCOPES.size():
		if _SCOPES[i] == want:
			box.select(i)
			return
	box.select(0)


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b
