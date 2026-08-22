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
##   (erode analog)            E          tool.erode        no GIMP equivalent; same chord in both schemes
##   (dilate analog)           Shift+E    tool.dilate
##   (set-height analog)       T          tool.setheight
##   (set-angle analog)        Shift+T    tool.setangle
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
const ACTION_ERODE := "tool.erode"
const ACTION_DILATE := "tool.dilate"
const ACTION_SET_HEIGHT := "tool.setheight"
const ACTION_SET_ANGLE := "tool.setangle"
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
	ACTION_ERODE, ACTION_DILATE, ACTION_SET_HEIGHT, ACTION_SET_ANGLE,
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

## The shipped set, kept for call sites that name it. KeymapRegistry.ids() is
## authoritative: an action registered at load time appears only there.
const ALL_ACTIONS: PackedStringArray = [
	ACTION_FLY, ACTION_RAISE, ACTION_LOWER, ACTION_FLATTEN, ACTION_SMOOTH,
	ACTION_RAMP, ACTION_PAINT, ACTION_PLACE, ACTION_SELECT, ACTION_NOISE,
	ACTION_QSEL, ACTION_RSEL, ACTION_WAND, ACTION_CLONE,
	ACTION_ERODE, ACTION_DILATE, ACTION_SET_HEIGHT, ACTION_SET_ANGLE,
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

## Warn about a broken shipped scheme once per process, not once per keystroke.
static var _warned: bool = false
## scheme id → {action id → chord}. Loaded lazily from KeymapStore.
static var _overrides: Dictionary = {}
static var _overrides_loaded: bool = false
static var _override_rev: int = 0
## Merged table cache, keyed by registry + override revision so a rebind or a
## late-registered action invalidates it without anyone calling a reset.
static var _merged: Dictionary = {}
static var _merged_key: String = ""


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


## Shipped defaults for the scheme with the user's overrides merged over them.
static func bindings_for(scheme: String = "") -> Dictionary:
	_warn_conflicts_once()
	return merged_bindings(scheme).duplicate(true)


static func binding_for(action: String, scheme: String = "") -> Dictionary:
	var table := bindings_for(scheme)
	if not table.has(action):
		return {}
	return table[action]


static func resolve(event: InputEvent, scheme: String = "") -> String:
	if not (event is InputEventKey):
		return ""
	var k := event as InputEventKey
	_warn_conflicts_once()
	var table := merged_bindings(scheme)
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
	return KeyAction.format_chord(bind)


## Empty when the scheme has no duplicate chords (tool vs tool, or tool vs non-tool).
static func find_conflicts(scheme: String) -> Array:
	return find_conflicts_in(bindings_for(scheme))


## Returns [{chord, actions}] for any chord claimed by more than one action.
static func find_conflicts_in(bindings: Dictionary) -> Array:
	var by_chord: Dictionary = {}
	for raw_action in bindings.keys():
		var action := str(raw_action)
		var bind: Dictionary = bindings[action]
		# A cleared binding owns no chord, so two of them are not a clash.
		if not KeyAction.is_bound(bind):
			continue
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
	return """[b]Scheme: %s[/b]

[b]Camera[/b][code]
RMB drag look        Ctrl+RMB / Alt+RMB drag orbit
Shift+RMB drag pan   MMB orbit     Shift+MMB pan
wheel zoom (to cursor; Ctrl+wheel too)
Shift+wheel truck left/right      Alt+wheel orbit step
Ctrl+move orbit (slow)   Alt+move pan camera   Shift+move grab-pan
(2D: RMB/MMB drag pans)
WASD fly     Q/E up down     Shift fast     Ctrl slow
%s frame map   %s top-down   %s 2D/3D
%s slope tint  %s walk-the-surface  %s grid[/code]

[b]Tools[/b][code]
%s fly     %s raise   %s lower   %s flatten
%s smooth  %s ramp    %s paint   %s place
%s select  %s noise   %s qsel    %s rsel
%s wand    %s clone
%s erode   %s dilate  %s set height   %s set angle
[ ] radius     Shift+[ ] strength     Esc cancel / fly
LMB sculpt / select; place stays armed (Esc stops placing)
Place: Shift+click deletes the object under the cursor
Alt+LMB eyedropper (paint): samples the tile word — solid, cap, or corner
Clone: Ctrl+click sets the source; paint copies height deltas.
Set angle: Ctrl+click anchors the plane; otherwise it starts where you do.[/code]

[b]Objects[/b][code]
arrows nudge 1 m (Shift 5 m)    R rotate +15° (Shift+R +90°)
Delete remove selected          Shift+0…7 set team on selection[/code]

[b]Terrain selection[/b][code]
QSel paints (LMB add, Alt subtract)
RSel drag (Shift add, Alt subtract, plain replace)
Wand click (Shift add, Alt subtract; tolerance in the panel)
Select-by-material uses the active swatch
%s select all   %s deselect   %s invert
Feather / Grow / Shrink live in the panel
Empty selection = everything editable; otherwise edits multiply
by the mask.[/code]

[b]Session[/b][code]
%s undo   %s redo   %s save   ` log   %s focus   %s this help
Alt+1…5 recall camera bookmark     Ctrl+Alt+1…5 store
Select + hold M and drag to measure
Autosave every 30s by default while unsaved (Preferences… sets
15s / 30s / 60s / off; a crash does not lose the session;
%s writes the map files)[/code]

[b]Other scheme (%s)[/b][code]
%s[/code]""" % [
		scheme_label(id),
		L.call(ACTION_FRAME), L.call(ACTION_TOP_DOWN), L.call(ACTION_MAP_MODE), L.call(ACTION_SLOPE), L.call(ACTION_WALK),
		L.call(ACTION_GRID),
		L.call(ACTION_FLY), L.call(ACTION_RAISE), L.call(ACTION_LOWER),
		L.call(ACTION_FLATTEN), L.call(ACTION_SMOOTH), L.call(ACTION_RAMP),
		L.call(ACTION_PAINT), L.call(ACTION_PLACE), L.call(ACTION_SELECT), L.call(ACTION_NOISE),
		L.call(ACTION_QSEL), L.call(ACTION_RSEL), L.call(ACTION_WAND), L.call(ACTION_CLONE),
		L.call(ACTION_ERODE), L.call(ACTION_DILATE),
		L.call(ACTION_SET_HEIGHT), L.call(ACTION_SET_ANGLE),
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
	return KeyAction.chord(keycode, ctrl, shift, alt)


## Every bindable action, including any a feature registered at load time.
## Prefer this over the ALL_ACTIONS constant, which is only the shipped set.
static func all_actions() -> PackedStringArray:
	return KeymapRegistry.ids()


static func categories() -> PackedStringArray:
	return KeymapRegistry.categories()


static func actions_in(category: String) -> PackedStringArray:
	return KeymapRegistry.ids_in(category)


static func action_label(action: String) -> String:
	var entry := KeymapRegistry.get_action(action)
	return entry.display_label() if entry != null else action


static func action_tooltip(action: String) -> String:
	var entry := KeymapRegistry.get_action(action)
	return entry.tooltip if entry != null else ""


static func action_category(action: String) -> String:
	var entry := KeymapRegistry.get_action(action)
	return entry.category if entry != null else ""


## Shipped chord for an action, ignoring whatever the user has bound.
static func default_binding(action: String, scheme: String = "") -> Dictionary:
	var entry := KeymapRegistry.get_action(action)
	if entry == null:
		return {}
	return entry.default_for(_scheme_id(scheme))


static func is_default(action: String, scheme: String = "") -> bool:
	return not has_override(action, scheme)


## The user's customisations for a scheme: action id → chord. A copy.
static func overrides_for(scheme: String = "") -> Dictionary:
	_ensure_overrides()
	var table: Dictionary = _overrides.get(_scheme_id(scheme), {})
	return table.duplicate(true)


static func has_override(action: String, scheme: String = "") -> bool:
	_ensure_overrides()
	var table: Dictionary = _overrides.get(_scheme_id(scheme), {})
	return table.has(action)


## Rebind an action for one scheme and persist it. Rejects unknown actions and
## malformed chords; a clash is the caller's to resolve, not ours to veto.
static func set_binding(action: String, bind: Dictionary, scheme: String = "") -> bool:
	if not KeymapRegistry.has_action(action):
		return false
	var chord := KeyAction.coerce_chord(bind)
	if chord.is_empty():
		return false
	_ensure_overrides()
	var id := _scheme_id(scheme)
	var shipped := default_binding(action, id)
	var table: Dictionary = _overrides.get(id, {})
	if not shipped.is_empty() and KeyAction.same_chord(shipped, chord):
		# Back at the shipped chord: drop the override instead of pinning it,
		# so a later change to the shipped scheme still reaches this user.
		table.erase(action)
	else:
		table[action] = chord
	_overrides[id] = table
	_write_overrides()
	return true


## Clear an action's chord. It keeps its row in Preferences and resolves to
## nothing until it is rebound or reset.
static func unbind(action: String, scheme: String = "") -> bool:
	return set_binding(action, KeyAction.chord(KeyAction.UNBOUND), scheme)


static func reset_binding(action: String, scheme: String = "") -> void:
	_ensure_overrides()
	var id := _scheme_id(scheme)
	var table: Dictionary = _overrides.get(id, {})
	if not table.has(action):
		return
	table.erase(action)
	_overrides[id] = table
	_write_overrides()


## Drop every override for one scheme; the other scheme keeps its own.
static func reset_all(scheme: String = "") -> void:
	_ensure_overrides()
	var id := _scheme_id(scheme)
	if not _overrides.has(id):
		return
	_overrides.erase(id)
	_write_overrides()


static func reset_every_scheme() -> void:
	_ensure_overrides()
	_overrides.clear()
	_write_overrides()


## Re-read the file. For tests and for a config edited underneath us.
static func reload_overrides() -> void:
	_overrides_loaded = false
	_override_rev += 1
	_ensure_overrides()


## Actions that already own `bind` in `scheme`, excluding `action` itself.
## The editor's modifiers are dense enough that silently letting the newest
## binding win would lose a key the user still needs.
static func conflicts_with(action: String, bind: Dictionary, scheme: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	if not KeyAction.is_bound(bind):
		return out
	var wanted := _chord_id(bind)
	var table := merged_bindings(scheme)
	for raw_other in table.keys():
		var other := str(raw_other)
		if other == action:
			continue
		if _chord_id(table[other]) == wanted:
			out.append(other)
	out.sort()
	return out


## One line naming what a proposed chord would steal, or "" when it is free.
static func conflict_text(action: String, bind: Dictionary, scheme: String = "") -> String:
	var clashes := conflicts_with(action, bind, scheme)
	if clashes.is_empty():
		return ""
	var named := PackedStringArray()
	for other in clashes:
		var cat := action_category(str(other))
		if cat.is_empty():
			named.append(action_label(str(other)))
		else:
			named.append("%s (%s)" % [action_label(str(other)), cat])
	return "%s is already %s" % [format_binding(bind), ", ".join(named)]


## Live table for a scheme. Shared, not copied — callers must not mutate it.
static func merged_bindings(scheme: String = "") -> Dictionary:
	var id := _scheme_id(scheme)
	_ensure_overrides()
	var key := "%d:%d" % [KeymapRegistry.revision(), _override_rev]
	if _merged_key != key:
		_merged_key = key
		_merged = {}
	if _merged.has(id):
		return _merged[id]
	var table := KeymapRegistry.defaults_for(id)
	var custom: Dictionary = _overrides.get(id, {})
	for raw_action in custom.keys():
		var action := str(raw_action)
		if table.has(action):
			table[action] = custom[action]
	_merged[id] = table
	return table


static func _scheme_id(scheme: String) -> String:
	return normalize_scheme(scheme if not scheme.is_empty() else active_scheme())


static func _ensure_overrides() -> void:
	if _overrides_loaded:
		return
	_overrides_loaded = true
	_overrides = KeymapStore.load_overrides()


static func _write_overrides() -> void:
	_override_rev += 1
	KeymapStore.save_overrides(_overrides)


static func _chord_matches(k: InputEventKey, bind: Dictionary) -> bool:
	return KeyAction.matches(k, bind)


static func _chord_id(bind: Dictionary) -> String:
	return KeyAction.chord_id(bind)


static func _key_label(keycode: int) -> String:
	return KeyAction.key_label(keycode)


static func _warn_conflicts_once() -> void:
	if _warned:
		return
	_warned = true
	# Shipped schemes only: a user override is allowed to clash (Preferences
	# says so out loud), but a scheme we ship must not.
	for scheme in [SCHEME_GODOT, SCHEME_GIMP]:
		var table := KeymapRegistry.defaults_for(scheme)
		for clash in find_conflicts_in(table):
			var actions: PackedStringArray = clash.get("actions", PackedStringArray())
			push_warning("Keymap scheme '%s' chord clash: %s" % [scheme, ", ".join(actions)])
		for raw_action in KeymapRegistry.ids():
			var action := str(raw_action)
			if not table.has(action):
				push_warning("Keymap scheme '%s' missing action %s" % [scheme, action])
			elif action.begins_with("tool."):
				# Tool chords must not collide with non-tool keys in the same scheme.
				var tool_id := _chord_id(table[action])
				for raw_other in table.keys():
					var other := str(raw_other)
					if other.begins_with("tool.") or other == action:
						continue
					if _chord_id(table[other]) == tool_id:
						push_warning("Keymap scheme '%s' tool %s clashes with %s" % [
							scheme, action, other,
						])
