extends Window
class_name CommandPalette
## Type-to-run list of every registered command.
##
## Two jobs. It is the front end for CommandRegistry, and it is the answer
## to "what can this editor even do?" — every verb, its category, its
## chord and a sentence of prose, in one searchable place. Entries that are
## gated off stay visible and greyed rather than vanishing, because a
## command you cannot find is worse than one you cannot press yet.
##
## Built in code, like the rest of project/ui.
##
## Coordinator wiring:
##   var palette := CommandPalette.new()
##   palette.context = ctx            # see CommandContext
##   add_child(palette)
##   # in _unhandled_input:
##   if CommandPalette.is_open_chord(event):
##       palette.open_palette()
##       get_viewport().set_input_as_handled()

signal command_invoked(id: String)

## The registry may hold hundreds of entries once users add their own, and
## re-ranking on every keystroke is visible. Coalesce instead.
const FILTER_DEBOUNCE_S := 0.25
const PAGE_STEP := 8
## Gated rows are dimmed, not ItemList-disabled: Godot refuses to select a
## disabled row, and a row you cannot highlight is a row whose description
## you cannot read.
const DIM_FG := Color(0.60, 0.60, 0.66)
const OPEN_CHORD := "Ctrl+Shift+P"

## Bound by the coordinator. A palette with no context still opens and
## still lists; commands that need a shell hook say so and stop.
var context: CommandContext = CommandContext.new()

var _registry: CommandRegistry
var _shown: Array = []
var _search: LineEdit
var _list: ItemList
var _detail: Label
var _status: Label
var _debounce: Timer


## The one chord the coordinator has to recognise for this whole feature.
static func is_open_chord(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	return k.keycode == KEY_P and k.ctrl_pressed and k.shift_pressed \
		and not k.alt_pressed


func _ready() -> void:
	title = "Commands"
	if size.x < 520:
		size = Vector2i(640, 460)
	visible = false
	close_requested.connect(_dismiss)
	_build_ui()
	if _registry == null:
		set_registry(_scan_default())
	else:
		rebuild()


## Swap in a pre-scanned registry (the coordinator scans once at boot).
func set_registry(registry: CommandRegistry) -> void:
	_registry = registry
	_report_scan_errors()
	if _list != null:
		rebuild()


func registry() -> CommandRegistry:
	if _registry == null:
		set_registry(_scan_default())
	return _registry


func open_palette() -> void:
	if _search == null:
		return
	_search.text = ""
	_debounce.stop()
	rebuild()
	popup_centered()
	_search.grab_focus()


## Ids currently listed, top-ranked first. The test seam.
func visible_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for cmd in _shown:
		out.append(str(cmd.get("id")))
	return out


## Apply the pending filter now instead of waiting out the debounce.
func flush_filter() -> void:
	if _debounce != null and not _debounce.is_stopped():
		_debounce.stop()
	rebuild()


func rebuild() -> void:
	if _list == null:
		return
	var reg := registry()
	var keep := ""
	if _list.item_count > 0:
		var picked := _list.get_selected_items()
		if not picked.is_empty() and picked[0] < _shown.size():
			keep = str(_shown[picked[0]].get("id"))
	_shown = reg.filter(_search.text if _search != null else "")
	_list.clear()
	var restore := -1
	for i in _shown.size():
		var cmd: Object = _shown[i]
		_list.add_item(_row_text(cmd), null, true)
		_list.set_item_tooltip(i, _tooltip_for(cmd))
		if not CommandRegistry.is_enabled(cmd):
			_list.set_item_custom_fg_color(i, DIM_FG)
		if str(cmd.get("id")) == keep:
			restore = i
	if _shown.is_empty():
		_list.add_item("No command matches “%s”" % _search.text, null, false)
		_list.set_item_disabled(0, true)
	else:
		_list.select(maxi(restore, 0))
	_refresh_detail()


## Invoke whatever is highlighted. False when nothing ran.
func run_selected() -> bool:
	if _shown.is_empty():
		return false
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return false
	var cmd: Object = _shown[picked[0]]
	var id := str(cmd.get("id"))
	if not registry().run_command(id, context):
		return false
	command_invoked.emit(id)
	_dismiss()
	return true


## Move the highlight without leaving the search box.
func move_selection(delta: int) -> void:
	if _shown.is_empty():
		return
	var picked := _list.get_selected_items()
	var at := 0 if picked.is_empty() else picked[0]
	var next := clampi(at + delta, 0, _shown.size() - 1)
	if next == at:
		return
	_list.select(next)
	_list.ensure_current_is_visible()
	_refresh_detail()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var col := VBoxContainer.new()
	col.name = "Body"
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Type a command…"
	_search.tooltip_text = "Fuzzy-filter every editor command (%s)" % OPEN_CHORD
	_search.clear_button_enabled = true
	_search.gui_input.connect(_on_search_gui_input)
	_search.text_changed.connect(_on_text_changed)
	_search.text_submitted.connect(func(_t: String) -> void: run_selected())
	col.add_child(_search)

	_list = ItemList.new()
	_list.name = "Results"
	_list.allow_reselect = true
	_list.focus_mode = Control.FOCUS_CLICK
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 240)
	_list.item_selected.connect(func(_i: int) -> void: _refresh_detail())
	_list.item_activated.connect(func(_i: int) -> void: run_selected())
	col.add_child(_list)

	_detail = Label.new()
	_detail.name = "Detail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 34)
	col.add_child(_detail)

	_status = Label.new()
	_status.name = "Status"
	_status.text = ""
	col.add_child(_status)

	_debounce = Timer.new()
	_debounce.name = "FilterDebounce"
	_debounce.one_shot = true
	_debounce.wait_time = FILTER_DEBOUNCE_S
	_debounce.timeout.connect(rebuild)
	add_child(_debounce)


func _on_text_changed(_text: String) -> void:
	_debounce.start(FILTER_DEBOUNCE_S)


func _on_search_gui_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_DOWN:
			move_selection(1)
		KEY_UP:
			move_selection(-1)
		KEY_PAGEDOWN:
			move_selection(PAGE_STEP)
		KEY_PAGEUP:
			move_selection(-PAGE_STEP)
		KEY_ENTER, KEY_KP_ENTER:
			flush_filter()
			run_selected()
		KEY_ESCAPE:
			_dismiss()
		_:
			return
	# Arrows and Enter belong to the list, never to the caret, or the
	# search box would eat them and the highlight would never move.
	_search.accept_event()


func _row_text(cmd: Object) -> String:
	var parts := PackedStringArray([CommandRegistry.display_title(cmd)])
	var group := str(cmd.get("category"))
	if not group.is_empty():
		parts.append(group)
	var chord := CommandRegistry.shortcut_for(cmd)
	if not chord.is_empty():
		parts.append(chord)
	return "  ·  ".join(parts)


func _tooltip_for(cmd: Object) -> String:
	var prose := str(cmd.get("description"))
	if CommandRegistry.is_enabled(cmd):
		return prose
	return "Unavailable right now.  " + prose


func _refresh_detail() -> void:
	if _detail == null:
		return
	if _shown.is_empty():
		_detail.text = ""
		return
	var picked := _list.get_selected_items()
	if picked.is_empty():
		_detail.text = ""
		return
	var cmd: Object = _shown[picked[0]]
	var prose := str(cmd.get("description"))
	if not CommandRegistry.is_enabled(cmd):
		prose = "Unavailable right now.  " + prose
	_detail.text = prose


func _report_scan_errors() -> void:
	if _registry == null or _status == null:
		return
	if _registry.errors.is_empty():
		_status.text = "%d commands" % _registry.size()
		return
	# Never silent: a plugin that did not load has to be visible somewhere
	# other than the engine log.
	_status.text = "%d commands, %d script(s) skipped" % [
		_registry.size(), _registry.errors.size(),
	]
	_registry.log_errors(context)


func _scan_default() -> CommandRegistry:
	var reg := CommandRegistry.new()
	reg.scan()
	return reg


func _dismiss() -> void:
	hide()
