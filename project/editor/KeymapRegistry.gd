extends RefCounted
class_name KeymapRegistry
## The editor's action table. Every keybinding — shipped or user — resolves
## through here, and the table is open: a new tool or the command palette
## registers its action at load time instead of editing a closed list.
##
##   KeymapRegistry.register(
##       "palette.open", "Command palette", "Search every editor command",
##       KeymapRegistry.CAT_SESSION, KeyAction.chord(KEY_P, true),
##       {Keymap.SCHEME_GIMP: KeyAction.chord(KEY_SLASH)})
##
## Registering the same id twice replaces the entry and keeps its position,
## so a hot-reload does not duplicate rows in Preferences.

const CAT_TOOLS := "Tools"
const CAT_SELECTION := "Selection"
const CAT_VIEW := "View"
const CAT_SESSION := "Session"
const CAT_TEAMS := "Teams"
const CAT_BOOKMARKS := "Bookmarks"

## Preferred display order. Categories outside it follow, in first-seen order.
const CATEGORY_ORDER: PackedStringArray = [
	CAT_TOOLS, CAT_SELECTION, CAT_VIEW, CAT_SESSION, CAT_TEAMS, CAT_BOOKMARKS,
]

const _GIMP := "gimp"

static var _actions: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()
static var _revision: int = 0
static var _seeding: bool = false
static var _seeded: bool = false


## Bumped by every table change so callers can cache a merged binding map.
static func revision() -> int:
	_ensure_seeded()
	return _revision


static func register(
	id: String,
	label: String,
	tooltip: String,
	category: String,
	default_chord: Dictionary,
	scheme_chords: Dictionary = {}
) -> KeyAction:
	var action := KeyAction.new()
	action.id = id
	action.label = label
	action.tooltip = tooltip
	action.category = category
	var defaults := {KeyAction.BASE_SCHEME: KeyAction.coerce_chord(default_chord)}
	for scheme in scheme_chords.keys():
		defaults[str(scheme)] = KeyAction.coerce_chord(scheme_chords[scheme])
	action.scheme_defaults = defaults
	return register_action(action)


## Register a prebuilt resource — the path a shipped or user .tres takes.
static func register_action(action: KeyAction) -> KeyAction:
	if action == null or action.id.is_empty():
		return null
	if not _seeding:
		_ensure_seeded()
	if not _actions.has(action.id):
		_order.append(action.id)
	_actions[action.id] = action
	_revision += 1
	return action


static func unregister(id: String) -> void:
	_ensure_seeded()
	if not _actions.has(id):
		return
	_actions.erase(id)
	var kept := PackedStringArray()
	for known in _order:
		if str(known) != id:
			kept.append(str(known))
	_order = kept
	_revision += 1


static func has_action(id: String) -> bool:
	_ensure_seeded()
	return _actions.has(id)


static func get_action(id: String) -> KeyAction:
	_ensure_seeded()
	return _actions.get(id, null)


static func ids() -> PackedStringArray:
	_ensure_seeded()
	return _order.duplicate()


static func actions() -> Array[KeyAction]:
	_ensure_seeded()
	var out: Array[KeyAction] = []
	for id in _order:
		out.append(_actions[str(id)])
	return out


static func categories() -> PackedStringArray:
	_ensure_seeded()
	var seen := PackedStringArray()
	for wanted in CATEGORY_ORDER:
		for id in _order:
			var action: KeyAction = _actions[str(id)]
			if action.category == str(wanted) and not str(wanted) in seen:
				seen.append(str(wanted))
				break
	for id in _order:
		var action: KeyAction = _actions[str(id)]
		if not action.category.is_empty() and not action.category in seen:
			seen.append(action.category)
	return seen


static func ids_in(category: String) -> PackedStringArray:
	_ensure_seeded()
	var out := PackedStringArray()
	for id in _order:
		var action: KeyAction = _actions[str(id)]
		if action.category == category:
			out.append(action.id)
	return out


## Shipped bindings for a scheme: action id → chord.
static func defaults_for(scheme: String) -> Dictionary:
	_ensure_seeded()
	var out: Dictionary = {}
	for id in _order:
		var action: KeyAction = _actions[str(id)]
		var bind := action.default_for(scheme)
		if bind.is_empty():
			continue
		out[action.id] = bind
	return out


static func _ensure_seeded() -> void:
	if _seeded:
		return
	_seeded = true
	_seeding = true
	_seed_tools()
	_seed_selection()
	_seed_view()
	_seed_session()
	_seed_teams()
	_seed_bookmarks()
	_seeding = false


static func _seed_tools() -> void:
	# Godot chords are the number row; GIMP chords mirror GIMP 3's stock tool
	# accelerators. Both are shipped defaults — neither may drift.
	var rows: Array = [
		["tool.fly", "Fly", "Camera only — no editing", KEY_1, KEY_ESCAPE, false],
		["tool.raise", "Raise", "Pull terrain up under the brush", KEY_2, KEY_W, false],
		["tool.lower", "Lower", "Push terrain down under the brush", KEY_3, KEY_W, true],
		["tool.flatten", "Flatten", "Level terrain toward the first height hit", KEY_4, KEY_F, true],
		["tool.smooth", "Smooth", "Average heights inside the brush", KEY_5, KEY_U, true],
		["tool.ramp", "Ramp", "Drag a graded ramp between two points", KEY_6, KEY_K, false],
		["tool.paint", "Paint", "Stamp the armed material tile", KEY_7, KEY_P, false],
		["tool.place", "Place", "Place the armed object class", KEY_8, KEY_I, false],
		["tool.select", "Select", "Pick and move objects", KEY_9, KEY_M, false],
		["tool.noise", "Noise", "Perturb heights inside the brush", KEY_0, KEY_N, false],
		["tool.qsel", "Quick select", "Paint the terrain selection mask", KEY_B, KEY_Q, false],
		["tool.rsel", "Rect select", "Drag a rectangular terrain selection", KEY_R, KEY_R, false],
		["tool.wand", "Wand", "Select similar terrain by tolerance", KEY_U, KEY_U, false],
		["tool.clone", "Clone", "Copy height deltas from a source point", KEY_C, KEY_C, false],
	]
	for row in rows:
		register(
			str(row[0]), str(row[1]), str(row[2]), CAT_TOOLS,
			KeyAction.chord(int(row[3])),
			{_GIMP: KeyAction.chord(int(row[4]), false, bool(row[5]))},
		)
	# The morphological and plane kernels have no GIMP analog to mirror, so
	# they take the same free chord in both schemes rather than inventing a
	# second one. Shift pairs each kernel with its inverse.
	var pairs: Array = [
		["tool.erode", "Erode", "Shave ridges down toward their neighbours", KEY_E, false],
		["tool.dilate", "Grow", "Swell terrain out toward its high neighbours", KEY_E, true],
		["tool.setheight", "Set height", "Drive cells to the target height", KEY_T, false],
		["tool.setangle", "Set angle", "Drive cells onto a sloped plane", KEY_T, true],
	]
	for row in pairs:
		register(
			str(row[0]), str(row[1]), str(row[2]), CAT_TOOLS,
			KeyAction.chord(int(row[3]), false, bool(row[4])),
		)


static func _seed_selection() -> void:
	register(
		"select.all", "Select all", "Select every terrain cell",
		CAT_SELECTION, KeyAction.chord(KEY_A, true),
	)
	register(
		"select.none", "Deselect", "Clear the terrain selection mask",
		CAT_SELECTION, KeyAction.chord(KEY_D, true),
	)
	register(
		"select.invert", "Invert selection", "Swap selected and unselected cells",
		CAT_SELECTION, KeyAction.chord(KEY_I, true, true),
	)


static func _seed_view() -> void:
	register(
		"frame", "Frame map", "Fit the whole map in the viewport",
		CAT_VIEW, KeyAction.chord(KEY_F),
	)
	register(
		"top_down", "Top-down", "Snap the camera straight down",
		CAT_VIEW, KeyAction.chord(KEY_SPACE),
	)
	register(
		"map_mode", "2D / 3D", "Toggle the flat north-up map view",
		CAT_VIEW, KeyAction.chord(KEY_KP_7),
	)
	register(
		"slope_overlay", "Slope tint", "Shade terrain by gradient",
		CAT_VIEW, KeyAction.chord(KEY_H),
	)
	register(
		"grid", "Grid", "Show the cell grid",
		CAT_VIEW, KeyAction.chord(KEY_G),
	)
	register(
		"walk", "Walk the surface", "Keep the camera at eye height",
		CAT_VIEW, KeyAction.chord(KEY_V),
	)


static func _seed_session() -> void:
	register(
		"help", "Hotkey reference", "Open the keyboard reference",
		CAT_SESSION, KeyAction.chord(KEY_F1),
	)
	register(
		"focus", "Focus mode", "Hide the docks and fill with the viewport",
		CAT_SESSION, KeyAction.chord(KEY_TAB),
	)
	register(
		"undo", "Undo", "Step back through the undo stack",
		CAT_SESSION, KeyAction.chord(KEY_Z, true),
	)
	register(
		"redo", "Redo", "Step forward through the undo stack",
		CAT_SESSION, KeyAction.chord(KEY_Z, true, true),
	)
	register(
		"save", "Save", "Write the map files",
		CAT_SESSION, KeyAction.chord(KEY_S, true),
	)


static func _seed_teams() -> void:
	for team in range(8):
		register(
			"team.%d" % team, "Set team %d" % team,
			"Assign team %d to the selected objects" % team,
			CAT_TEAMS, KeyAction.chord(_digit_key(team), false, true),
		)


static func _seed_bookmarks() -> void:
	for slot in range(1, 6):
		register(
			"bookmark.store.%d" % slot, "Store camera %d" % slot,
			"Remember the camera in slot %d" % slot,
			CAT_BOOKMARKS, KeyAction.chord(_digit_key(slot), true, false, true),
		)
	for slot in range(1, 6):
		register(
			"bookmark.recall.%d" % slot, "Recall camera %d" % slot,
			"Fly back to the camera in slot %d" % slot,
			CAT_BOOKMARKS, KeyAction.chord(_digit_key(slot), false, false, true),
		)


static func _digit_key(n: int) -> int:
	return KEY_0 if n <= 0 else KEY_0 + n
