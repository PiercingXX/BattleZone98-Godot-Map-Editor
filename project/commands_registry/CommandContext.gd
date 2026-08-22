extends RefCounted
class_name CommandContext
## The injection seam between registry commands and the editor shell.
##
## Commands never reach into scenes/main.gd. Anything owned by the shell is
## reached through a named hook the coordinator binds once at boot; anything
## reachable from an autoload or a static class (MapState, Settings,
## EditActions, UndoStack) commands call directly.
##
## Wiring, in the shell's _wire():
##
##   var ctx := CommandContext.new()
##   ctx.bind(CommandContext.HOOK_LOG, _log)
##   ctx.bind(CommandContext.HOOK_ACTION, _apply_keymap_action)
##   ctx.bind(CommandContext.HOOK_VALIDATE, _io.validate)
##   ctx.bind(CommandContext.HOOK_REFRESH_VIEW, func() -> void:
##       _apply_view_settings()
##       _viewp.refresh()          # else the View checkboxes go stale
##   )
##
## Every hook is optional. An unbound hook is not a crash: call_hook logs
## "unavailable here" and returns false, so a command degrades explicitly
## (C15) and the palette stays usable in a headless or partial shell.

## func(msg: String) -> void — append one line to the editor log.
const HOOK_LOG := "log"
## func(action: String) -> void — run one Keymap.ACTION_* id. Covers frame,
## top-down, 2D toggle, help and the rest of the shell-owned verbs.
const HOOK_ACTION := "action"
## func() -> void — persist the session and start a validation run.
const HOOK_VALIDATE := "validate"
## func() -> void — re-apply view filters to the live scene after a
## command has changed Settings / overlay flags. Must also re-sync the
## View panel's checkboxes, which read those flags rather than own them.
const HOOK_REFRESH_VIEW := "refresh_view"

## Every hook name the built-in commands use. The coordinator can assert
## against this list; nothing forbids binding extra names for user scripts.
const KNOWN_HOOKS: PackedStringArray = [
	HOOK_LOG, HOOK_ACTION, HOOK_VALIDATE, HOOK_REFRESH_VIEW,
]

var _hooks: Dictionary = {}


func bind(name: String, fn: Callable) -> void:
	var key := name.strip_edges()
	if key.is_empty():
		return
	if not fn.is_valid():
		_hooks.erase(key)
		return
	_hooks[key] = fn


func unbind(name: String) -> void:
	_hooks.erase(name.strip_edges())


func has_hook(name: String) -> bool:
	var fn: Variant = _hooks.get(name.strip_edges())
	return fn is Callable and (fn as Callable).is_valid()


func hook_names() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _hooks.keys():
		out.append(str(key))
	out.sort()
	return out


## Fire a hook. Returns false when it is not bound, after saying so — the
## caller reports "unavailable here" instead of half-running.
func call_hook(name: String, args: Array = []) -> bool:
	if not has_hook(name):
		log_line("command hook '%s' is unavailable here" % name)
		return false
	var fn: Callable = _hooks[name.strip_edges()]
	fn.callv(args)
	return true


## Log through the shell when it is wired, through EditorFeedback when it
## is not. Never silent.
func log_line(msg: String) -> void:
	if _hooks.has(HOOK_LOG):
		var fn: Callable = _hooks[HOOK_LOG]
		if fn.is_valid():
			fn.call(msg)
			return
	EditorFeedback.log(msg)
