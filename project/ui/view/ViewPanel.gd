extends PanelContainer
## Bottom-right visibility panel: every view filter as a checkbox, GIMP
## layers-style, replacing the old top-bar eye dropdown.

signal view_changed

## key → caption, in display order. Simple keys route through
## Settings.set_view_group; ghosts/balance/aipaths have special handling.
const SIMPLE: Array = [
	["geysers", "Geysers"],
	["scrap", "Scrap"],
	["spawns", "Spawns"],
	["buildings", "Buildings"],
	["units", "Units"],
	["props", "Props"],
	["water", "Water"],
	["plants", "Plants"],
	["sky", "Sky"],
]

var _checks: Dictionary = {}

@onready var _grid: GridContainer = %Checks


func _ready() -> void:
	for pair in SIMPLE:
		_add_check(str(pair[0]), str(pair[1]))
	_add_check("labels", "Labels")
	_add_check("ghosts", "Ghost variants")
	_add_check("balance", "Balance")
	_add_check("aipaths", "AI paths")
	var icon := find_child("TitleIcon", true, false)
	if icon is TextureRect and (icon as TextureRect).texture == null:
		(icon as TextureRect).texture = EditorIcons.texture("view")
	MapState.session_changed.connect(refresh)
	MapState.features_changed.connect(refresh)
	refresh()


func _add_check(key: String, caption: String) -> void:
	var cb := CheckBox.new()
	cb.name = "View" + key.capitalize()
	cb.text = caption
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(_on_toggled.bind(key))
	_grid.add_child(cb)
	_checks[key] = cb


func _on_toggled(on: bool, key: String) -> void:
	match key:
		"labels":
			if Settings.view_labels == on:
				return
			Settings.view_labels = on
			EditorFeedback.log("view labels %s" % ("on" if on else "off"))
		"ghosts":
			if ObjectMarkers.ghost_other_variants == on:
				return
			ObjectMarkers.ghost_other_variants = on
			Settings.view_ghost_variants = on
			EditorFeedback.log("view ghost_other_variants %s" % ("on" if on else "off"))
		"balance":
			if not MapState.has_session:
				refresh()
				return
			if BalanceOverlay.enabled == on:
				return
			BalanceOverlay.enabled = on
			Settings.view_balance = on
			EditorFeedback.log("view balance %s" % ("on" if on else "off"))
		"aipaths":
			if not MapState.has_session:
				refresh()
				return
			if AiPathOverlay.enabled == on:
				return
			AiPathOverlay.enabled = on
			Settings.view_aipaths = on
			EditorFeedback.log("view aipaths %s" % ("on" if on else "off"))
		_:
			if Settings.view_flag(key) == on:
				return
			Settings.set_view_group(key, on)
			# Say how many objects the toggle touches: a category that is
			# empty on this map otherwise looks like a dead checkbox.
			EditorFeedback.log("view %s %s (%d on this map)" % [
				key, "on" if on else "off", _count_in_group(key),
			])
	Settings.save()
	view_changed.emit()
	refresh()


func _count_in_group(key: String) -> int:
	var n := 0
	var recs: Variant = MapState.objects.get(MapState.active_variant, [])
	if typeof(recs) != TYPE_ARRAY:
		return 0
	for rec in recs:
		if typeof(rec) == TYPE_DICTIONARY \
				and ObjectMarkers.classify_record(rec) == key:
			n += 1
	return n


func refresh() -> void:
	for pair in SIMPLE:
		var key := str(pair[0])
		_set_check(key, Settings.view_flag(key), true, "")
	_set_check("plants", Settings.view_plants, _plants_overlay_ready(), "no plant regions")
	_set_check("labels", Settings.view_labels, true, "")
	_set_check(
		"ghosts", ObjectMarkers.ghost_other_variants, true,
		"Draw other BZN variants as unpickable ghosts"
	)
	_set_check("balance", BalanceOverlay.enabled, MapState.has_session, "Open a map first")
	_set_check("aipaths", AiPathOverlay.enabled, MapState.has_session, "Open a map first")


func _set_check(key: String, on: bool, enabled: bool, disabled_tip: String) -> void:
	var cb: CheckBox = _checks.get(key)
	if cb == null:
		return
	cb.set_pressed_no_signal(on)
	cb.disabled = not enabled
	cb.tooltip_text = disabled_tip if not enabled else ""


func _plants_overlay_ready() -> bool:
	var plants: Variant = MapState.features.get("plants", [])
	var has_regions := typeof(plants) == TYPE_ARRAY and not (plants as Array).is_empty()
	if not has_regions:
		return false
	var shell := _shell()
	if shell == null:
		return false
	var terrain: Object = shell.get("_terrain")
	if terrain == null:
		return false
	return (
		terrain.has_method("set_plants_overlay")
		or terrain.has_method("set_show_plants")
		or terrain.has_method("set_plants_visible")
	)


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")
