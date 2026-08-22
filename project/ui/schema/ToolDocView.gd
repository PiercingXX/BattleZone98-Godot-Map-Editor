extends VBoxContainer
class_name ToolDocView
## Renders a ToolDoc inline, beside the controls it describes. Nothing here
## reads the game install or the filesystem, so a panel documents itself on a
## machine with no Battlezone on it (C15).

var _doc: ToolDoc
var _compact: bool = true
var _meta: Label
var _body: RichTextLabel
var _params: VBoxContainer


## compact = the prose only; the per-parameter detail already rides on each
## editor as a tooltip. Pass false for a help window that has room.
static func make(doc: ToolDoc, compact: bool = true) -> ToolDocView:
	var view := ToolDocView.new()
	view._compact = compact
	view.set_doc(doc)
	return view


func _init() -> void:
	name = "ToolDocView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_meta = Label.new()
	_meta.name = "Meta"
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_meta)
	_body = RichTextLabel.new()
	_body.name = "Body"
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_params = VBoxContainer.new()
	_params.name = "Params"
	_params.add_theme_constant_override("separation", 6)
	add_child(_params)


func doc() -> ToolDoc:
	return _doc


func set_doc(value: ToolDoc) -> void:
	_doc = value
	_refresh()


func set_compact(on: bool) -> void:
	if _compact == on:
		return
	_compact = on
	_refresh()


func body_text() -> String:
	return _body.get_parsed_text()


func _refresh() -> void:
	for child in _params.get_children():
		_params.remove_child(child)
		child.queue_free()
	if _doc == null:
		_meta.text = ""
		_body.text = ""
		return
	_meta.text = _doc.header_line()
	_meta.add_theme_color_override("font_color", ThemeProbe.dim_text(self))
	_body.text = _doc.description
	_body.visible = not _doc.description.is_empty()
	_params.visible = not _compact
	if _compact:
		return
	for p in _doc.params():
		_params.add_child(_param_block(p))


func _param_block(p: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "Param_%s" % p["key"]
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.name = "Head"
	var range_bit := str(p["range_text"])
	head.text = "%s  (%s%s)  ·  cost %s" % [
		p["label"], p["type_name"],
		"" if range_bit.is_empty() else ", " + range_bit,
		p["cost"],
	]
	box.add_child(head)
	if not str(p["description"]).is_empty():
		var body := Label.new()
		body.name = "Body"
		body.text = str(p["description"])
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_color", ThemeProbe.dim_text(self))
		box.add_child(body)
	if not str(p["warning"]).is_empty():
		var warn := Label.new()
		warn.name = "Warning"
		warn.text = "Warning: %s" % p["warning"]
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override(
			"font_color",
			ThemeProbe.color(self, "font_color", "WarningLabel",
				Color(0.86, 0.62, 0.24, 1))
		)
		box.add_child(warn)
	return box
