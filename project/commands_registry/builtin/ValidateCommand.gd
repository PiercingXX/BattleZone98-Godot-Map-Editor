extends EditorCommand
## Run the backend validators over the current map. Read-only: it persists
## the session and reports findings, so there is nothing to undo.


func _init() -> void:
	id = "map.validate"
	title = "Run validation"
	category = "Map"
	description = "Persist the session and run every validator; results " \
		+ "land in the Findings panel."


func is_enabled() -> bool:
	return MapState.has_session


func run(ctx) -> void:
	ctx.call_hook(CommandContext.HOOK_VALIDATE)
