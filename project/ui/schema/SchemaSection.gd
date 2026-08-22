extends VBoxContainer
class_name SchemaSection
## The whole thing in one node: a titled, collapsible block containing a
## tool's documentation and the editors generated from the same declaration.
## This is all a panel has to instantiate.
##
##   var sec := SchemaSection.make(ToolDocs.get_doc("raise"))
##   sec.property_changed.connect(_on_param_changed)
##   add_child(sec)

signal property_changed(key: String, value: Variant)
signal collapsed_changed(collapsed: bool)

var _header: SectionHeader
var _docs: ToolDocView
var _grid: PropertyGrid
var _doc: ToolDoc


## Documentation and editors from one ToolDoc: they cannot disagree because
## they are the same dictionary.
static func make(doc: ToolDoc, compact_docs: bool = true) -> SchemaSection:
	var sec := SchemaSection.new()
	sec._build(doc.title(), doc.schema, doc, compact_docs)
	return sec


## For a block of parameters that is not a tool (view options, export
## settings): a title and a schema, no prose.
static func from_schema(title: String, schema: Dictionary) -> SchemaSection:
	var sec := SchemaSection.new()
	sec._build(title, schema, null, true)
	return sec


func _init() -> void:
	name = "SchemaSection"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)


func _build(title: String, schema: Dictionary, doc: ToolDoc,
		compact_docs: bool) -> void:
	_doc = doc
	_header = SectionHeader.make(title, true)
	_header.toggled_open.connect(_on_toggled)
	add_child(_header)
	if doc != null:
		_docs = ToolDocView.make(doc, compact_docs)
		add_child(_docs)
	_grid = PropertyGrid.make(schema)
	_grid.property_changed.connect(
		func(key: String, value: Variant) -> void:
			property_changed.emit(key, value)
	)
	add_child(_grid)


func grid() -> PropertyGrid:
	return _grid


func docs_view() -> ToolDocView:
	return _docs


func header() -> SectionHeader:
	return _header


func tool_doc() -> ToolDoc:
	return _doc


func get_values() -> Dictionary:
	return _grid.get_values()


func set_values(values: Dictionary) -> void:
	_grid.set_values(values)


func set_docs_visible(on: bool) -> void:
	if _docs != null:
		_docs.visible = on


func set_collapsed(on: bool) -> void:
	_header.set_open(not on)


func is_collapsed() -> bool:
	return not _header.is_open()


func _on_toggled(open: bool) -> void:
	if _docs != null:
		_docs.visible = open
	_grid.visible = open
	collapsed_changed.emit(not open)
