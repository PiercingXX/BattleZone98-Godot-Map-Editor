extends RefCounted
class_name EditorCommand
## Base class for a registry command: one named, searchable editor action.
##
## Discovery is "drop a script in a folder". CommandRegistry scans
## res://project/commands_registry/builtin and user://commands, loads every
## .gd it finds, instantiates it, and reads the members below. Extending
## this class is the typed path; any RefCounted exposing the same members
## works too, because the registry duck-types.
##
## A script may declare more than one command by exposing
## `command_list() -> Array`; the registry then registers what that returns
## and ignores the declaring instance itself.
##
## C16: a command that edits map data MUST build a project/commands/*
## command and push it onto UndoStack, exactly like the rest of the editor.
## Set `mutates_map = true` and the registry verifies an undo entry landed.

## Stable identifier. Sort key, override key, and the id tests assert on.
## Reverse-DNS-ish dotted form: "view.frame_map".
var id: String = ""
## Human label shown in the palette.
var title: String = ""
## Grouping shown beside the title. Free text; keep it short.
var category: String = "General"
## One sentence of prose. The palette shows it under the list.
var description: String = ""
## Display-only chord, e.g. "Ctrl+Shift+P". Empty when unbound. The
## registry never binds this — the shell owns input.
var shortcut: String = ""
## True when run() edits map data. The registry warns when such a command
## returns without having pushed an undo entry.
var mutates_map: bool = false


## Override when the chord depends on live state (the keymap scheme, say).
func shortcut_text() -> String:
	return shortcut


## Gate. False greys the entry out and refuses execution.
func is_enabled() -> bool:
	return true


## Do the work. `ctx` is a CommandContext carrying the shell hooks.
func run(_ctx) -> void:
	pass
