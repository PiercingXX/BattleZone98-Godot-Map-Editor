extends Resource
class_name KeyAction
## One rebindable editor action, plus the chord primitives everything else
## shares. Resource-backed so a scheme can ship as data and a feature can
## contribute an action at load time without editing a shipped table.
##
## Deliberately knows nothing about Keymap or KeymapRegistry: they depend on
## this file, so a back-reference would be a cycle.

## Scheme that every other scheme inherits from when it names no default.
const BASE_SCHEME := "godot"
## keycode 0 means "the user cleared this" — never matches, never clashes.
const UNBOUND := 0

@export var id: String = ""
## Short caption for the rebinding list.
@export var label: String = ""
## One line of help shown as the row tooltip.
@export var tooltip: String = ""
## Grouping caption; see KeymapRegistry.CAT_*.
@export var category: String = ""
## scheme id → chord dict. BASE_SCHEME must be present to bind at all.
@export var scheme_defaults: Dictionary = {}


static func chord(
	keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false
) -> Dictionary:
	return {
		"keycode": keycode,
		"ctrl": ctrl,
		"shift": shift,
		"alt": alt,
	}


## Empty when raw is not a chord at all; an UNBOUND chord survives.
static func coerce_chord(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = raw
	if not d.has("keycode"):
		return {}
	var code := int(d.get("keycode", UNBOUND))
	if code < 0:
		return {}
	return chord(
		code,
		bool(d.get("ctrl", false)),
		bool(d.get("shift", false)),
		bool(d.get("alt", false)),
	)


static func is_bound(bind: Dictionary) -> bool:
	return int(bind.get("keycode", UNBOUND)) != UNBOUND


static func same_chord(a: Dictionary, b: Dictionary) -> bool:
	return chord_id(a) == chord_id(b)


static func chord_id(bind: Dictionary) -> String:
	return "%d:%d:%d:%d" % [
		int(bind.get("keycode", UNBOUND)),
		1 if bool(bind.get("ctrl", false)) else 0,
		1 if bool(bind.get("shift", false)) else 0,
		1 if bool(bind.get("alt", false)) else 0,
	]


static func matches(k: InputEventKey, bind: Dictionary) -> bool:
	if not is_bound(bind):
		return false
	if k.keycode != int(bind.get("keycode", UNBOUND)):
		return false
	if k.ctrl_pressed != bool(bind.get("ctrl", false)):
		return false
	if k.shift_pressed != bool(bind.get("shift", false)):
		return false
	if k.alt_pressed != bool(bind.get("alt", false)):
		return false
	return true


static func chord_from_event(k: InputEventKey) -> Dictionary:
	return chord(k.keycode, k.ctrl_pressed, k.shift_pressed, k.alt_pressed)


## True for Ctrl / Shift / Alt / Meta held alone — never a binding by itself.
static func is_modifier_key(keycode: int) -> bool:
	match keycode:
		KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META, KEY_CAPSLOCK:
			return true
		_:
			return false


static func format_chord(bind: Dictionary) -> String:
	if not is_bound(bind):
		return "Unassigned"
	var parts := PackedStringArray()
	if bool(bind.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(bind.get("shift", false)):
		parts.append("Shift")
	if bool(bind.get("alt", false)):
		parts.append("Alt")
	parts.append(key_label(int(bind.get("keycode", UNBOUND))))
	return "+".join(parts)


static func key_label(keycode: int) -> String:
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


## Shipped chord for a scheme, falling back to BASE_SCHEME.
func default_for(scheme: String) -> Dictionary:
	if scheme_defaults.has(scheme):
		return coerce_chord(scheme_defaults[scheme])
	if scheme_defaults.has(BASE_SCHEME):
		return coerce_chord(scheme_defaults[BASE_SCHEME])
	return {}


func display_label() -> String:
	return label if not label.is_empty() else id
