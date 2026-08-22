extends ShellActionCommand
## The hotkey window, reachable by name instead of by remembering F1.
## Modifier semantics are the least discoverable thing in the editor, so
## this one stays enabled with no map open.


func _init() -> void:
	super(
		Keymap.ACTION_HELP,
		"help.hotkeys",
		"Hotkey list",
		"Help",
		"Open the hotkey and modifier reference for the active scheme.",
		false,
	)
