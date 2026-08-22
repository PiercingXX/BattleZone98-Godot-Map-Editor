extends EditorCommand
class_name ShellActionCommand
## A registry command that forwards to one Keymap action id.
##
## The shell already routes every chord through a single dispatcher, so the
## cheapest honest seam for camera / help / view verbs is to hand that
## dispatcher the action id rather than duplicate its body here. The chord
## shown in the palette is read live, so it follows the keymap scheme.

var action: String = ""
## When true the command greys out until a map is open.
var needs_session: bool = true


func _init(
	action_id: String = "",
	command_id: String = "",
	label: String = "",
	group: String = "General",
	prose: String = "",
	session_required: bool = true,
) -> void:
	action = action_id
	id = command_id
	title = label
	category = group
	description = prose
	needs_session = session_required


func shortcut_text() -> String:
	return Keymap.format_action(action)


func is_enabled() -> bool:
	return MapState.has_session if needs_session else true


func run(ctx) -> void:
	ctx.call_hook(CommandContext.HOOK_ACTION, [action])
