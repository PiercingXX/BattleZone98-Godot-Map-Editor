extends RefCounted
class_name Keymap
## Named keyboard schemes for tool switching and shared editor actions.

## GIMP 3 default tool shortcuts → editor actions.
## The user's ~/.config/GIMP/3.2/shortcutsrc only customized gaussian-blur,
## print, and layer-delete — no tool accelerators — so stock defaults stand.
##
##   GIMP tool                 key        editor action     notes
##   Move                      M          tool.select
##   Paintbrush                P          tool.paint
##   Blur / Sharpen            Shift+U    tool.smooth
##   Warp Transform            W          tool.raise
##   Warp inverse (pair)       Shift+W    tool.lower        GIMP has no inverse-warp key; pair with raise
##   Flip (flatten analog)     Shift+F    tool.flatten
##   (ramp analog)             K          tool.ramp         R / Shift+R rotate objects when tool.select
##   Pencil                    N          tool.noise
##   Ink                       I          tool.place
##   Quick Mask analog         Q          tool.qsel         paint the terrain selection
##   Rectangle Select          R          tool.rsel         object-select still eats R to rotate
##   Fuzzy Select              U          tool.wand
##   Clone                     C          tool.clone
##   Select All                Ctrl+A     select.all
##   Select None               Ctrl+D     select.none
##   Invert Selection          Ctrl+Shift+I  select.invert
##   (cancel)                  Escape     tool.fly
##
## Godot scheme is the original number-row bindings plus the existing
## non-tool keys. Behavior for that scheme must match the pre-Keymap shell.

const SCHEME_GODOT := "godot"
const SCHEME_GIMP := "gimp"

const ACTION_FLY := "tool.fly"
const ACTION_RAISE := "tool.raise"
const ACTION_LOWER := "tool.lower"
const ACTION_FLATTEN := "tool.flatten"
const ACTION_SMOOTH := "tool.smooth"
const ACTION_RAMP := "tool.ramp"
const ACTION_PAINT := "tool.paint"
const ACTION_PLACE := "tool.place"
const ACTION_SELECT := "tool.select"
const ACTION_NOISE := "tool.noise"
const ACTION_QSEL := "tool.qsel"
const ACTION_RSEL := "tool.rsel"
const ACTION_WAND := "tool.wand"
const ACTION_CLONE := "tool.clone"
const ACTION_SELECT_ALL := "select.all"
const ACTION_DESELECT := "select.none"
const ACTION_INVERT := "select.invert"
const ACTION_FRAME := "frame"
const ACTION_TOP_DOWN := "top_down"
const ACTION_MAP_MODE := "map_mode"
const ACTION_SLOPE := "slope_overlay"
const ACTION_GRID := "grid"
const ACTION_WALK := "walk"
const ACTION_HELP := "help"
const ACTION_FOCUS := "focus"
const ACTION_UNDO := "undo"
const ACTION_REDO := "redo"
const ACTION_SAVE := "save"
const ACTION_TEAM_0 := "team.0"
const ACTION_TEAM_1 := "team.1"
const ACTION_TEAM_2 := "team.2"
const ACTION_TEAM_3 := "team.3"
const ACTION_TEAM_4 := "team.4"
const ACTION_TEAM_5 := "team.5"
const ACTION_TEAM_6 := "team.6"
const ACTION_TEAM_7 := "team.7"
const ACTION_BOOKMARK_STORE_1 := "bookmark.store.1"
const ACTION_BOOKMARK_STORE_2 := "bookmark.store.2"
const ACTION_BOOKMARK_STORE_3 := "bookmark.store.3"
const ACTION_BOOKMARK_STORE_4 := "bookmark.store.4"
const ACTION_BOOKMARK_STORE_5 := "bookmark.store.5"
const ACTION_BOOKMARK_RECALL_1 := "bookmark.recall.1"
const ACTION_BOOKMARK_RECALL_2 := "bookmark.recall.2"
const ACTION_BOOKMARK_RECALL_3 := "bookmark.recall.3"
const ACTION_BOOKMARK_RECALL_4 := "bookmark.recall.4"
const ACTION_BOOKMARK_RECALL_5 := "bookmark.recall.5"

const TOOL_ACTIONS: PackedStringArray = [
	ACTION_FLY, ACTION_RAISE, ACTION_LOWER, ACTION_FLATTEN, ACTION_SMOOTH,
	ACTION_RAMP, ACTION_PAINT, ACTION_PLACE, ACTION_SELECT, ACTION_NOISE,
	ACTION_QSEL, ACTION_RSEL, ACTION_WAND, ACTION_CLONE,
]

const TEAM_ACTIONS: PackedStringArray = [
	ACTION_TEAM_0, ACTION_TEAM_1, ACTION_TEAM_2, ACTION_TEAM_3,
	ACTION_TEAM_4, ACTION_TEAM_5, ACTION_TEAM_6, ACTION_TEAM_7,
]

const BOOKMARK_STORE_ACTIONS: PackedStringArray = [
	ACTION_BOOKMARK_STORE_1, ACTION_BOOKMARK_STORE_2, ACTION_BOOKMARK_STORE_3,
	ACTION_BOOKMARK_STORE_4, ACTION_BOOKMARK_STORE_5,
]

const BOOKMARK_RECALL_ACTIONS: PackedStringArray = [
	ACTION_BOOKMARK_RECALL_1, ACTION_BOOKMARK_RECALL_2, ACTION_BOOKMARK_RECALL_3,
	ACTION_BOOKMARK_RECALL_4, ACTION_BOOKMARK_RECALL_5,
]

const NON_TOOL_ACTIONS: PackedStringArray = [
	ACTION_FRAME, ACTION_TOP_DOWN, ACTION_MAP_MODE, ACTION_SLOPE, ACTION_GRID, ACTION_WALK,
	ACTION_HELP, ACTION_FOCUS, ACTION_UNDO, ACTION_REDO, ACTION_SAVE,
	ACTION_SELECT_ALL, ACTION_DESELECT, ACTION_INVERT,
	ACTION_TEAM_0, ACTION_TEAM_1, ACTION_TEAM_2, ACTION_TEAM_3,
	ACTION_TEAM_4, ACTION_TEAM_5, ACTION_TEAM_6, ACTION_TEAM_7,
	ACTION_BOOKMARK_STORE_1, ACTION_BOOKMARK_STORE_2, ACTION_BOOKMARK_STORE_3,
	ACTION_BOOKMARK_STORE_4, ACTION_BOOKMARK_STORE_5,
	ACTION_BOOKMARK_RECALL_1, ACTION_BOOKMARK_RECALL_2, ACTION_BOOKMARK_RECALL_3,
	ACTION_BOOKMARK_RECALL_4, ACTION_BOOKMARK_RECALL_5,
]

const ALL_ACTIONS: PackedStringArray = [
	ACTION_FLY, ACTION_RAISE, ACTION_LOWER, ACTION_FLATTEN, ACTION_SMOOTH,
	ACTION_RAMP, ACTION_PAINT, ACTION_PLACE, ACTION_SELECT, ACTION_NOISE,
	ACTION_QSEL, ACTION_RSEL, ACTION_WAND, ACTION_CLONE,
	ACTION_FRAME, ACTION_TOP_DOWN, ACTION_MAP_MODE, ACTION_SLOPE, ACTION_GRID, ACTION_WALK,
	ACTION_HELP, ACTION_FOCUS, ACTION_UNDO, ACTION_REDO, ACTION_SAVE,
	ACTION_SELECT_ALL, ACTION_DESELECT, ACTION_INVERT,
	ACTION_TEAM_0, ACTION_TEAM_1, ACTION_TEAM_2, ACTION_TEAM_3,
	ACTION_TEAM_4, ACTION_TEAM_5, ACTION_TEAM_6, ACTION_TEAM_7,
	ACTION_BOOKMARK_STORE_1, ACTION_BOOKMARK_STORE_2, ACTION_BOOKMARK_STORE_3,
	ACTION_BOOKMARK_STORE_4, ACTION_BOOKMARK_STORE_5,
	ACTION_BOOKMARK_RECALL_1, ACTION_BOOKMARK_RECALL_2, ACTION_BOOKMARK_RECALL_3,
	ACTION_BOOKMARK_RECALL_4, ACTION_BOOKMARK_RECALL_5,
]

static var _warned: bool = false


static func normalize_scheme(name: String) -> String:
	var cleaned := name.strip_edges().to_lower()
	if cleaned == SCHEME_GIMP:
		return SCHEME_GIMP
	return SCHEME_GODOT


static func active_scheme() -> String:
	return normalize_scheme(Settings.keymap_scheme)


static func scheme_label(scheme: String = "") -> String:
	var id := normalize_scheme(scheme if not scheme.is_empty() else active_scheme())
	return "GIMP" if id == SCHEME_GIMP else "Godot"


static func other_scheme(scheme: String = "") -> String:
	var id := normalize_scheme(scheme if not scheme.is_empty() else active_scheme())
	return SCHEME_GODOT if id == SCHEME_GIMP else SCHEME_GIMP


static func bindings_for(scheme: String = "") -> Dictionary:
	_warn_conflicts_once()
	var id := normalize_scheme(scheme if not scheme.is_empty() else active_scheme())
	if id == SCHEME_GIMP:
		return _gimp_bindings()
	return _godot_bindings()


static func binding_for(action: String, scheme: String = "") -> Dictionary:
	var table := bindings_for(scheme)
	if not table.has(action):
		return {}
	return table[action]


static func resolve(event: InputEvent, scheme: String = "") -> String:
	if not (event is InputEventKey):
		return ""
	var k := event as InputEventKey
	var table := bindings_for(scheme)
	for raw_action in table.keys():
		var action := str(raw_action)
		var bind: Dictionary = table[action]
		if _chord_matches(k, bind):
			return action
	return ""


static func format_action(action: String, scheme: String = "") -> String:
	var bind := binding_for(action, scheme)
	if bind.is_empty():
		return ""
	return format_binding(bind)


static func format_binding(bind: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if bool(bind.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(bind.get("shift", false)):
		parts.append("Shift")
	if bool(bind.get("alt", false)):
		parts.append("Alt")
	parts.append(_key_label(int(bind.get("keycode", 0))))
	return "+".join(parts)


## Empty when the scheme has no duplicate chords (tool vs tool, or tool vs non-tool).
static func find_conflicts(scheme: String) -> Array:
	return find_conflicts_in(bindings_for(scheme))


## Returns [{chord, actions}] for any chord claimed by more than one action.
static func find_conflicts_in(bindings: Dictionary) -> Array:
	var by_chord: Dictionary = {}
	for raw_action in bindings.keys():
		var action := str(raw_action)
		var bind: Dictionary = bindings[action]
		var chord := _chord_id(bind)
		if not by_chord.has(chord):
			by_chord[chord] = PackedStringArray()
		var listed: PackedStringArray = by_chord[chord]
		listed.append(action)
		by_chord[chord] = listed
	var out: Array = []
	for chord in by_chord.keys():
		var actions: PackedStringArray = by_chord[chord]
		if actions.size() < 2:
			continue
		actions.sort()
		out.append({"chord": str(chord), "actions": actions})
	return out


static func help_text(scheme: String = "") -> String:
	var id := normalize_scheme(scheme if not scheme.is_empty() else active_scheme())
	var L := func(action: String) -> String:
		return format_action(action, id)
	var other := other_scheme(id)
	var other_tools := PackedStringArray()
	for action in TOOL_ACTIONS:
		var short := action.get_slice(".", 1)
		other_tools.append("%s %s" % [format_action(action, other), short])
	return """[code]Scheme: %s

RMB look     mouse wheel zoom     MMB orbit
WASD fly     Q/E up down     Shift fast     Ctrl slow
%s frame map     %s top-down     %s 2D/3D     %s slope tint     %s walk-the-surface
%s grid     Delete remove selected
%s fly   %s raise   %s lower   %s flatten   %s smooth   %s ramp
%s paint   %s place   %s select   %s noise
%s qsel   %s rsel   %s wand   %s clone
Select: arrows nudge 1 m (Shift 5 m)     R rotate +15° (Shift+R +90°) when object-select
Terrain select: QSel paints (LMB add, Alt subtract). RSel drag (Shift add, Alt subtract, plain replace). Wand click (Shift add, Alt subtract; tolerance in the panel). Select-by-material uses the active swatch.
%s select all     %s deselect     %s invert     Feather / Grow / Shrink in the panel
Empty selection = everything editable. While a selection exists, sculpt and paint multiply by the mask.
Clone: Ctrl+click sets the source; paint copies height deltas (optional materials).
[ ] radius     Shift+[ ] strength     Esc cancel / fly
%s undo     %s redo     %s save     ` log     %s focus     %s this
Shift+0…7 set team on the selection
Alt+1…5 recall camera bookmark     Ctrl+Alt+1…5 store
Select + hold M and drag to measure
LMB sculpt / place / select     Shift+click keep placing
Alt+LMB eyedropper (paint)
Autosave     every 30s by default while unsaved (Preferences… sets 15s / 30s / 60s / off; a crash does not lose the session; %s writes the map files)
Other scheme (%s): %s[/code]""" % [
		scheme_label(id),
		L.call(ACTION_FRAME), L.call(ACTION_TOP_DOWN), L.call(ACTION_MAP_MODE), L.call(ACTION_SLOPE), L.call(ACTION_WALK),
		L.call(ACTION_GRID),
		L.call(ACTION_FLY), L.call(ACTION_RAISE), L.call(ACTION_LOWER),
		L.call(ACTION_FLATTEN), L.call(ACTION_SMOOTH), L.call(ACTION_RAMP),
		L.call(ACTION_PAINT), L.call(ACTION_PLACE), L.call(ACTION_SELECT), L.call(ACTION_NOISE),
		L.call(ACTION_QSEL), L.call(ACTION_RSEL), L.call(ACTION_WAND), L.call(ACTION_CLONE),
		L.call(ACTION_SELECT_ALL), L.call(ACTION_DESELECT), L.call(ACTION_INVERT),
		L.call(ACTION_UNDO), L.call(ACTION_REDO), L.call(ACTION_SAVE), L.call(ACTION_FOCUS),
		L.call(ACTION_HELP),
		L.call(ACTION_SAVE),
		scheme_label(other), "   ".join(other_tools),
	]


static func team_from_action(action: String) -> int:
	if not action.begins_with("team."):
		return -1
	return int(action.get_slice(".", 1))


static func bookmark_slot(action: String) -> int:
	if not action.begins_with("bookmark."):
		return 0
	var n := int(action.get_slice(".", 2))
	if n < 1 or n > 5:
		return 0
	return n


static func is_bookmark_store(action: String) -> bool:
	return action.begins_with("bookmark.store.")


static func is_bookmark_recall(action: String) -> bool:
	return action.begins_with("bookmark.recall.")


static func make_binding(keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false) -> Dictionary:
	return {
		"keycode": keycode,
		"ctrl": ctrl,
		"shift": shift,
		"alt": alt,
	}


static func _godot_bindings() -> Dictionary:
	# Exact pre-Keymap shell: 1–8 tools, 9 select, 0 noise, F / Space / H / G / V,
	# F1, Ctrl+Z, Ctrl+Shift+Z, Ctrl+S.
	return {
		ACTION_FLY: make_binding(KEY_1),
		ACTION_RAISE: make_binding(KEY_2),
		ACTION_LOWER: make_binding(KEY_3),
		ACTION_FLATTEN: make_binding(KEY_4),
		ACTION_SMOOTH: make_binding(KEY_5),
		ACTION_RAMP: make_binding(KEY_6),
		ACTION_PAINT: make_binding(KEY_7),
		ACTION_PLACE: make_binding(KEY_8),
		ACTION_SELECT: make_binding(KEY_9),
		ACTION_NOISE: make_binding(KEY_0),
		ACTION_QSEL: make_binding(KEY_B),
		ACTION_RSEL: make_binding(KEY_R),
		ACTION_WAND: make_binding(KEY_U),
		ACTION_CLONE: make_binding(KEY_C),
		ACTION_SELECT_ALL: make_binding(KEY_A, true),
		ACTION_DESELECT: make_binding(KEY_D, true),
		ACTION_INVERT: make_binding(KEY_I, true, true),
		ACTION_FRAME: make_binding(KEY_F),
		ACTION_TOP_DOWN: make_binding(KEY_SPACE),
		ACTION_MAP_MODE: make_binding(KEY_KP_7),
		ACTION_SLOPE: make_binding(KEY_H),
		ACTION_GRID: make_binding(KEY_G),
		ACTION_WALK: make_binding(KEY_V),
		ACTION_HELP: make_binding(KEY_F1),
		ACTION_FOCUS: make_binding(KEY_TAB),
		ACTION_UNDO: make_binding(KEY_Z, true),
		ACTION_REDO: make_binding(KEY_Z, true, true),
		ACTION_SAVE: make_binding(KEY_S, true),
		ACTION_TEAM_0: make_binding(KEY_0, false, true),
		ACTION_TEAM_1: make_binding(KEY_1, false, true),
		ACTION_TEAM_2: make_binding(KEY_2, false, true),
		ACTION_TEAM_3: make_binding(KEY_3, false, true),
		ACTION_TEAM_4: make_binding(KEY_4, false, true),
		ACTION_TEAM_5: make_binding(KEY_5, false, true),
		ACTION_TEAM_6: make_binding(KEY_6, false, true),
		ACTION_TEAM_7: make_binding(KEY_7, false, true),
		ACTION_BOOKMARK_STORE_1: make_binding(KEY_1, true, false, true),
		ACTION_BOOKMARK_STORE_2: make_binding(KEY_2, true, false, true),
		ACTION_BOOKMARK_STORE_3: make_binding(KEY_3, true, false, true),
		ACTION_BOOKMARK_STORE_4: make_binding(KEY_4, true, false, true),
		ACTION_BOOKMARK_STORE_5: make_binding(KEY_5, true, false, true),
		ACTION_BOOKMARK_RECALL_1: make_binding(KEY_1, false, false, true),
		ACTION_BOOKMARK_RECALL_2: make_binding(KEY_2, false, false, true),
		ACTION_BOOKMARK_RECALL_3: make_binding(KEY_3, false, false, true),
		ACTION_BOOKMARK_RECALL_4: make_binding(KEY_4, false, false, true),
		ACTION_BOOKMARK_RECALL_5: make_binding(KEY_5, false, false, true),
	}


static func _gimp_bindings() -> Dictionary:
	var table := _godot_bindings()
	table[ACTION_FLY] = make_binding(KEY_ESCAPE)
	table[ACTION_RAISE] = make_binding(KEY_W)
	table[ACTION_LOWER] = make_binding(KEY_W, false, true)
	table[ACTION_FLATTEN] = make_binding(KEY_F, false, true)
	table[ACTION_SMOOTH] = make_binding(KEY_U, false, true)
	table[ACTION_RAMP] = make_binding(KEY_K)
	table[ACTION_PAINT] = make_binding(KEY_P)
	table[ACTION_PLACE] = make_binding(KEY_I)
	table[ACTION_SELECT] = make_binding(KEY_M)
	table[ACTION_NOISE] = make_binding(KEY_N)
	table[ACTION_QSEL] = make_binding(KEY_Q)
	table[ACTION_RSEL] = make_binding(KEY_R)
	table[ACTION_WAND] = make_binding(KEY_U)
	table[ACTION_CLONE] = make_binding(KEY_C)
	return table


static func _chord_matches(k: InputEventKey, bind: Dictionary) -> bool:
	if k.keycode != int(bind.get("keycode", 0)):
		return false
	if k.ctrl_pressed != bool(bind.get("ctrl", false)):
		return false
	if k.shift_pressed != bool(bind.get("shift", false)):
		return false
	if k.alt_pressed != bool(bind.get("alt", false)):
		return false
	return true


static func _chord_id(bind: Dictionary) -> String:
	return "%d:%d:%d:%d" % [
		int(bind.get("keycode", 0)),
		1 if bool(bind.get("ctrl", false)) else 0,
		1 if bool(bind.get("shift", false)) else 0,
		1 if bool(bind.get("alt", false)) else 0,
	]


static func _key_label(keycode: int) -> String:
	match keycode:
		KEY_ESCAPE:
			return "Esc"
		KEY_QUOTELEFT:
			return "`"
		KEY_SPACE:
			return "Space"
		KEY_TAB:
			return "Tab"
		KEY_KP_7:
			return "KP 7"
		_:
			var named := OS.get_keycode_string(keycode)
			return named if not named.is_empty() else "?"


static func _warn_conflicts_once() -> void:
	if _warned:
		return
	_warned = true
	for scheme in [SCHEME_GODOT, SCHEME_GIMP]:
		var table: Dictionary = _godot_bindings() if scheme == SCHEME_GODOT else _gimp_bindings()
		for clash in find_conflicts_in(table):
			var actions: PackedStringArray = clash.get("actions", PackedStringArray())
			push_warning("Keymap scheme '%s' chord clash: %s" % [scheme, ", ".join(actions)])
		for action in ALL_ACTIONS:
			if not table.has(action):
				push_warning("Keymap scheme '%s' missing action %s" % [scheme, action])
			elif str(action).begins_with("tool."):
				# Tool chords must not collide with non-tool keys in the same scheme.
				var tool_id := _chord_id(table[action])
				for non_tool in NON_TOOL_ACTIONS:
					if not table.has(non_tool):
						continue
					if _chord_id(table[non_tool]) == tool_id:
						push_warning("Keymap scheme '%s' tool %s clashes with %s" % [
							scheme, action, non_tool,
						])
