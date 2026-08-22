extends GridContainer
class_name PropertyGrid
## Generic editor builder: a PropertySchema dictionary in, a labelled grid of
## typed editors out. Adding a tool parameter is one dictionary entry and no
## UI code.
##
##   var grid := PropertyGrid.make(MyTool.SCHEMA)
##   grid.property_changed.connect(_on_param)
##   add_child(grid)

signal property_changed(key: String, value: Variant)

## Grid columns are label + editor; the reroll button rides inside the editor
## cell so the two-column rhythm survives a randomizable row.
const COLUMNS := 2

var _schema: Dictionary = {}
var _rows: Dictionary = {}
var _syncing: bool = false
var _rng := RandomNumberGenerator.new()
var _file_dialog: FileDialog


static func make(schema: Dictionary) -> PropertyGrid:
	var grid := PropertyGrid.new()
	grid.build(schema)
	return grid


func _init() -> void:
	name = "PropertyGrid"
	columns = COLUMNS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rng.randomize()


## Rebuild from scratch. Declaration order is row order: GDScript dictionaries
## keep insertion order, so the schema reads like the panel looks.
func build(schema: Dictionary) -> void:
	_clear()
	_schema = PropertySchema.normalize(schema)
	var section := ""
	for key in _schema.keys():
		var entry: Dictionary = _schema[key]
		var want := str(entry.get("section", ""))
		if want != section and not want.is_empty():
			section = want
			_add_section(want)
		_add_row(str(key), entry)


func schema() -> Dictionary:
	return _schema


func keys() -> PackedStringArray:
	var out: PackedStringArray = []
	for key in _schema.keys():
		out.append(str(key))
	return out


func has_key(key: String) -> bool:
	return _rows.has(key)


## Primary editor for a key — the SpinSlider, OptionButton, LineEdit. Panels
## that must reach past the schema (disable a row, add an icon) use this.
func editor_for(key: String) -> Control:
	var row: Dictionary = _rows.get(key, {})
	return row.get("control", null)


func label_for(key: String) -> Label:
	var row: Dictionary = _rows.get(key, {})
	return row.get("label", null)


func get_value(key: String) -> Variant:
	if not _rows.has(key):
		return null
	var row: Dictionary = _rows[key]
	var getter: Callable = row["get"]
	return PropertySchema.coerce(row["entry"], getter.call())


func get_values() -> Dictionary:
	var out := {}
	for key in _rows.keys():
		out[key] = get_value(str(key))
	return out


## Write one key. Silent by default: a scripted sync is not a user edit.
func set_value(key: String, value: Variant, notify: bool = false) -> void:
	if not _rows.has(key):
		return
	var row: Dictionary = _rows[key]
	var coerced: Variant = PropertySchema.coerce(row["entry"], value)
	var was := _syncing
	_syncing = true
	var setter: Callable = row["set"]
	setter.call(coerced)
	_syncing = was
	if notify:
		property_changed.emit(key, get_value(key))


func set_values(values: Dictionary) -> void:
	var was := _syncing
	_syncing = true
	for key in values.keys():
		set_value(str(key), values[key])
	_syncing = was


func reset_to_defaults() -> void:
	set_values(PropertySchema.defaults(_schema))


func set_key_enabled(key: String, on: bool) -> void:
	var row: Dictionary = _rows.get(key, {})
	var cell: Control = row.get("cell", null)
	if cell != null:
		_set_disabled(cell, not on)
	var lab: Label = row.get("label", null)
	if lab != null:
		lab.modulate.a = 1.0 if on else 0.5


func set_key_visible(key: String, on: bool) -> void:
	var row: Dictionary = _rows.get(key, {})
	if row.is_empty():
		return
	var cell: Control = row.get("cell", null)
	var lab: Label = row.get("label", null)
	if cell != null:
		cell.visible = on
	if lab != null:
		lab.visible = on


## Deterministic rerolls: seed the grid's RNG and a rebuild repeats (C6).
func set_random_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func randomize_key(key: String) -> void:
	if not _rows.has(key):
		return
	var row: Dictionary = _rows[key]
	if not bool(row["entry"].get("randomizable", false)):
		return
	set_value(key, PropertySchema.random_value(row["entry"], _rng))
	property_changed.emit(key, get_value(key))


func randomize_all() -> void:
	for key in _rows.keys():
		randomize_key(str(key))


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	_schema.clear()


func _add_section(title: String) -> void:
	var head := SectionHeader.make(title)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(head)
	var spacer := Control.new()
	spacer.name = "SectionSpacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spacer)


func _add_row(key: String, entry: Dictionary) -> void:
	var lab := Label.new()
	lab.name = "Label_%s" % key
	lab.text = str(entry.get("label", key))
	lab.tooltip_text = PropertySchema.tooltip_for(entry)
	lab.mouse_filter = Control.MOUSE_FILTER_STOP
	lab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(lab)

	var made := _make_editor(key, entry)
	var control: Control = made["control"]
	control.name = "Edit_%s" % key
	control.tooltip_text = PropertySchema.tooltip_for(entry)
	var cell: Control = control
	if bool(entry.get("randomizable", false)):
		var box := HBoxContainer.new()
		box.name = "Cell_%s" % key
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 4)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(control)
		var btn := Button.new()
		btn.name = "Random_%s" % key
		btn.text = "Rnd"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(40, 0)
		btn.tooltip_text = "Randomize %s" % entry.get("label", key)
		btn.pressed.connect(func() -> void: randomize_key(key))
		box.add_child(btn)
		cell = box
	else:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(cell)

	_rows[key] = {
		"entry": entry,
		"control": control,
		"cell": cell,
		"label": lab,
		"get": made["get"],
		"set": made["set"],
	}
	var setter: Callable = made["set"]
	_syncing = true
	setter.call(entry["default"])
	_syncing = false


func _emit_changed(key: String) -> void:
	if _syncing:
		return
	property_changed.emit(key, get_value(key))


## One place that knows which Godot control edits which TYPE_*. Returns the
## control plus its getter/setter so nothing downstream branches on type.
func _make_editor(key: String, entry: Dictionary) -> Dictionary:
	var type := int(entry.get("type", TYPE_FLOAT))
	var usage := str(entry.get("usage", ""))
	if usage == PropertySchema.USAGE_ENUM:
		return _make_enum(key, entry)
	match type:
		TYPE_BOOL:
			return _make_bool(key)
		TYPE_INT, TYPE_FLOAT:
			return _make_number(key, entry)
		TYPE_STRING:
			if usage == PropertySchema.USAGE_FILE \
					or usage == PropertySchema.USAGE_DIR:
				return _make_file(key, entry)
			if usage == PropertySchema.USAGE_MULTILINE:
				return _make_multiline(key)
			return _make_line(key)
		TYPE_VECTOR2:
			if usage == PropertySchema.USAGE_BAND:
				return _make_band(key, entry)
			return _make_vector(key, entry, 2, false)
		TYPE_VECTOR2I:
			return _make_vector(key, entry, 2, true)
		TYPE_VECTOR3:
			return _make_vector(key, entry, 3, false)
		TYPE_COLOR:
			return _make_color(key)
	return _make_line(key)


func _make_bool(key: String) -> Dictionary:
	var box := CheckBox.new()
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(_on: bool) -> void: _emit_changed(key))
	var getter := func() -> Variant:
		return box.button_pressed
	var setter := func(v: Variant) -> void:
		box.set_pressed_no_signal(bool(v))
	return {"control": box, "get": getter, "set": setter}


func _make_number(key: String, entry: Dictionary) -> Dictionary:
	var rounded := int(entry.get("type", TYPE_FLOAT)) == TYPE_INT
	var r: Dictionary = entry.get("range", {})
	var ctl: SpinSlider
	if bool(entry.get("bounded", false)):
		ctl = SpinSlider.make(
			float(r.get("min", 0.0)), float(r.get("max", 1.0)),
			float(r.get("step", 0.0)), 0.0,
			str(entry.get("suffix", "")), rounded
		)
	else:
		ctl = SpinSlider.make_unbounded(
			float(r.get("step", 1.0)), 0.0,
			str(entry.get("suffix", "")), rounded
		)
	ctl.value_changed.connect(func(_v: float) -> void: _emit_changed(key))
	var getter := func() -> Variant:
		return ctl.get_value()
	var setter := func(v: Variant) -> void:
		ctl.set_value_silent(float(v))
	return {"control": ctl, "get": getter, "set": setter}


func _make_enum(key: String, entry: Dictionary) -> Dictionary:
	var items := PropertySchema.enum_items(entry)
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.clip_text = true
	for i in items.size():
		opt.add_item(str(items[i]["label"]), i)
	opt.item_selected.connect(func(_i: int) -> void: _emit_changed(key))
	var getter := func() -> Variant:
		var idx := opt.selected
		if idx < 0 or idx >= items.size():
			return entry.get("default")
		return items[idx]["value"]
	var setter := func(v: Variant) -> void:
		var want: Variant = PropertySchema.coerce(entry, v)
		for i in items.size():
			if PropertySchema.values_equal(items[i]["value"], want):
				opt.selected = i
				return
		opt.selected = 0 if items.size() > 0 else -1
	return {"control": opt, "get": getter, "set": setter}


func _make_line(key: String) -> Dictionary:
	var edit := LineEdit.new()
	edit.text_changed.connect(func(_t: String) -> void: _emit_changed(key))
	var getter := func() -> Variant:
		return edit.text
	var setter := func(v: Variant) -> void:
		edit.text = str(v)
	return {"control": edit, "get": getter, "set": setter}


func _make_multiline(key: String) -> Dictionary:
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 72)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text_changed.connect(func() -> void: _emit_changed(key))
	var getter := func() -> Variant:
		return edit.text
	var setter := func(v: Variant) -> void:
		edit.text = str(v)
	return {"control": edit, "get": getter, "set": setter}


func _make_file(key: String, entry: Dictionary) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var edit := LineEdit.new()
	edit.name = "Path"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "path"
	edit.text_changed.connect(func(_t: String) -> void: _emit_changed(key))
	row.add_child(edit)
	var browse := Button.new()
	browse.name = "Browse"
	browse.text = "..."
	browse.focus_mode = Control.FOCUS_NONE
	browse.custom_minimum_size = Vector2(32, 0)
	browse.pressed.connect(func() -> void: _open_file_dialog(key, entry, edit))
	row.add_child(browse)
	var getter := func() -> Variant:
		return edit.text
	var setter := func(v: Variant) -> void:
		edit.text = str(v)
	return {"control": row, "get": getter, "set": setter}


func _make_band(key: String, entry: Dictionary) -> Dictionary:
	var r: Dictionary = entry.get("range", {})
	var lo := float(r.get("min", 0.0))
	var hi := float(r.get("max", 1.0))
	var band := RangeSlider.make(lo, hi, float(r.get("step", 0.0)), lo, hi)
	band.range_changed.connect(
		func(_a: float, _b: float) -> void: _emit_changed(key))
	var getter := func() -> Variant:
		return band.band()
	var setter := func(v: Variant) -> void:
		var vec := Vector2(lo, hi)
		if typeof(v) == TYPE_VECTOR2:
			vec = v
		band.set_band(vec.x, vec.y)
	return {"control": band, "get": getter, "set": setter}


func _make_vector(key: String, entry: Dictionary, dims: int,
		integral: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var r: Dictionary = entry.get("range", {})
	var boxes: Array[SpinBox] = []
	var axes := ["x", "y", "z"]
	for i in dims:
		var spin := SpinBox.new()
		spin.name = "Axis_%s" % axes[i]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.min_value = float(r.get("min", -PropertySchema.UNBOUNDED))
		spin.max_value = float(r.get("max", PropertySchema.UNBOUNDED))
		spin.step = float(r.get("step", 1.0 if integral else 0.001))
		spin.rounded = integral
		spin.prefix = "%s " % axes[i]
		spin.value_changed.connect(func(_v: float) -> void: _emit_changed(key))
		row.add_child(spin)
		boxes.append(spin)
	var getter := func() -> Variant:
		if dims == 3:
			return Vector3(boxes[0].value, boxes[1].value, boxes[2].value)
		if integral:
			return Vector2i(int(boxes[0].value), int(boxes[1].value))
		return Vector2(boxes[0].value, boxes[1].value)
	var setter := func(v: Variant) -> void:
		var vals := PackedFloat64Array([0.0, 0.0, 0.0])
		match typeof(v):
			TYPE_VECTOR3:
				vals = PackedFloat64Array([v.x, v.y, v.z])
			TYPE_VECTOR2, TYPE_VECTOR2I:
				vals = PackedFloat64Array([v.x, v.y])
		for i in mini(dims, vals.size()):
			boxes[i].set_value_no_signal(vals[i])
	return {"control": row, "get": getter, "set": setter}


func _make_color(key: String) -> Dictionary:
	var btn := ColorPickerButton.new()
	btn.custom_minimum_size = Vector2(60, 0)
	btn.color_changed.connect(func(_c: Color) -> void: _emit_changed(key))
	var getter := func() -> Variant:
		return btn.color
	var setter := func(v: Variant) -> void:
		btn.color = v if typeof(v) == TYPE_COLOR else Color.WHITE
	return {"control": btn, "get": getter, "set": setter}


## Built on first use: a FileDialog is a Window, and the grid must construct
## headless with no game installed (C15).
func _open_file_dialog(key: String, entry: Dictionary, edit: LineEdit) -> void:
	if not is_inside_tree():
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = false
		add_child(_file_dialog)
	var dir_mode := str(entry.get("usage", "")) == PropertySchema.USAGE_DIR
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if dir_mode \
		else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PropertySchema.file_filters(entry)
	for conn in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(conn["callable"])
	for conn in _file_dialog.dir_selected.get_connections():
		_file_dialog.dir_selected.disconnect(conn["callable"])
	var apply := func(path: String) -> void:
		edit.text = path
		_emit_changed(key)
	_file_dialog.file_selected.connect(apply)
	_file_dialog.dir_selected.connect(apply)
	_file_dialog.popup_centered_ratio(0.6)


func _set_disabled(node: Control, off: bool) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = off
	elif node is Range:
		(node as Range).editable = not off
	elif node is LineEdit:
		(node as LineEdit).editable = not off
	elif node is TextEdit:
		(node as TextEdit).editable = not off
	elif node is SpinSlider:
		(node as SpinSlider).slider().editable = not off
		(node as SpinSlider).spin_box().editable = not off
	elif node is RangeSlider:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE if off \
			else Control.MOUSE_FILTER_STOP
	for child in node.get_children():
		if child is Control:
			_set_disabled(child as Control, off)
