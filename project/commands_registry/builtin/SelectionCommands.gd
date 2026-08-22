extends RefCounted
## Terrain-mask selection verbs. These edit the selection mask, which is
## session state and never written to the map, so C16 does not apply and
## `mutates_map` stays false.


func command_list() -> Array:
	return [
		_Selection.new(
			"select.all_terrain", "Select all terrain",
			Keymap.ACTION_SELECT_ALL,
			"Set every heightfield cell fully selected.",
			"all",
		),
		_Selection.new(
			"select.none_terrain", "Deselect terrain",
			Keymap.ACTION_DESELECT,
			"Clear the mask, which makes every cell editable again.",
			"none",
		),
		_Selection.new(
			"select.invert_terrain", "Invert terrain selection",
			Keymap.ACTION_INVERT,
			"Swap selected and unselected cells, feathering included.",
			"invert",
		),
	]


class _Selection:
	extends EditorCommand

	var action: String = ""
	var mode: String = ""

	func _init(
		command_id: String,
		label: String,
		action_id: String,
		prose: String,
		which: String,
	) -> void:
		id = command_id
		title = label
		action = action_id
		mode = which
		description = prose
		category = "Selection"

	func shortcut_text() -> String:
		return Keymap.format_action(action)

	func is_enabled() -> bool:
		if mode == "none":
			return not MapState.selection_empty()
		return MapState.has_session and MapState.has_heightmap()

	func run(ctx) -> void:
		var log := func(msg: String) -> void: ctx.log_line(msg)
		match mode:
			"none":
				EditActions.deselect_terrain(log)
			"invert":
				EditActions.invert_terrain(log)
			_:
				EditActions.select_all_terrain(log)
