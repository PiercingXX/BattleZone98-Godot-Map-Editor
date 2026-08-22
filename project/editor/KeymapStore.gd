extends RefCounted
class_name KeymapStore
## User keybinding overrides on disk, one section per scheme.
##
## user:// is the platform config dir on both Linux and Windows, so no path
## separator is ever spelled here (C12). The whole per-scheme map is stored as
## one Dictionary value because action ids contain dots and would not survive
## as bare ConfigFile keys.

const PATH := "user://keymap.cfg"
const KEY_BINDINGS := "bindings"


## scheme id → {action id → chord}. Missing or unreadable file → {}.
static func load_overrides() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var out: Dictionary = {}
	for section in cfg.get_sections():
		var raw: Variant = cfg.get_value(section, KEY_BINDINGS, {})
		var table := coerce_table(raw)
		if table.is_empty():
			continue
		out[str(section)] = table
	return out


static func save_overrides(data: Dictionary) -> Error:
	var cfg := ConfigFile.new()
	for scheme in data.keys():
		var table := coerce_table(data[scheme])
		if table.is_empty():
			continue
		cfg.set_value(str(scheme), KEY_BINDINGS, table)
	if cfg.get_sections().is_empty():
		erase()
		return OK
	return cfg.save(PATH)


## Drop the file entirely; absence is the "everything is stock" state.
static func erase() -> void:
	if not FileAccess.file_exists(PATH):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Reject anything that is not a chord so a hand-edited file cannot crash boot.
static func coerce_table(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	for action in d.keys():
		var id := str(action)
		if id.is_empty():
			continue
		var bind := KeyAction.coerce_chord(d[action])
		if bind.is_empty():
			continue
		out[id] = bind
	return out
