extends RefCounted
class_name CommandRegistry
## Scans command scripts out of a built-in folder and a user folder and
## turns them into a searchable, deterministically ordered list.
##
## The extensibility story is deliberately the boring one the field settled
## on: no embedded language, no manifest format. Drop a .gd in
## user://commands and it shows up in the palette next boot.
##
## Failure is per-file and explicit (C15). A script that will not parse,
## will not instantiate, or does not honour the EditorCommand shape is
## skipped, its reason is appended to `errors`, and the scan continues.
## What cannot be contained is a runtime error inside a well-formed
## _init(): GDScript has no catch, so such a script yields a
## half-constructed object. It is then rejected by the same shape check,
## but the engine has already printed its own error first.
##
## TRUST: there is no sandbox. A script in user://commands is ordinary
## GDScript running in-process with the editor's full authority — the same
## file, network and OS access the editor itself has. Treat that folder
## exactly like a folder of executables: only put scripts there you would
## be willing to run.

const BUILTIN_DIR := "res://project/commands_registry/builtin"
## user:// resolves to ~/.local/share/godot/app_userdata/<name> on Linux
## and %APPDATA%\Godot\app_userdata\<name> on Windows, so this is the one
## place a path stays portable without touching a separator (C12).
const USER_DIR := "user://commands"

## Registered commands, sorted by id. Never contains a null.
var commands: Array = []
## One line per rejected file, in scan order. Empty after a clean scan.
var errors: Array[String] = []
## One "<id> (<path>)" line per id a later root took over from an
## earlier one. An override is a decision, so it is never silent.
var overrides: Array[String] = []

var _by_id: Dictionary = {}


## Built-in first, user second, so a user script with the same id wins.
static func default_roots() -> PackedStringArray:
	return PackedStringArray([BUILTIN_DIR, USER_DIR])


## Best-effort: a folder that exists is a folder the user can find.
static func ensure_user_dir() -> bool:
	if DirAccess.dir_exists_absolute(USER_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(USER_DIR) == OK


func scan(roots: PackedStringArray = default_roots()) -> void:
	commands.clear()
	errors.clear()
	overrides.clear()
	_by_id.clear()
	for root in roots:
		_scan_root(str(root))
	# Registration order must not depend on filesystem enumeration order,
	# or the palette reshuffles between machines.
	var ids: Array[String] = []
	for key in _by_id.keys():
		ids.append(str(key))
	ids.sort()
	for id in ids:
		commands.append(_by_id[id])


## Say out loud what the scan rejected. The palette calls this; so should
## any headless caller, or a skipped plugin vanishes without a word.
func log_errors(ctx: CommandContext = null) -> void:
	var context := ctx if ctx != null else CommandContext.new()
	for line in errors:
		context.log_line("command scan: %s" % line)
	for line in overrides:
		context.log_line("command override: %s" % line)


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for cmd in commands:
		out.append(_str_member(cmd, "id"))
	return out


func get_command(id: String) -> Object:
	var found: Variant = _by_id.get(id)
	return found if found is Object else null


func size() -> int:
	return commands.size()


## Run one command by id. Returns false when it is unknown or gated off;
## the reason is logged, never swallowed.
func run_command(id: String, ctx: CommandContext) -> bool:
	var cmd := get_command(id)
	var context := ctx if ctx != null else CommandContext.new()
	if cmd == null:
		context.log_line("no such command: %s" % id)
		return false
	if not is_enabled(cmd):
		context.log_line("%s is unavailable right now" % display_title(cmd))
		return false
	var before := UndoStack.command_count()
	cmd.call("run", context)
	# C16 is not honour-system: a command that says it edits the map and
	# pushes nothing has bypassed the undo stack, and that is a defect.
	if bool(_member(cmd, "mutates_map", false)) \
			and UndoStack.command_count() == before:
		context.log_line(
			"%s edited the map without an undo entry" % display_title(cmd)
		)
	return true


static func is_enabled(cmd: Object) -> bool:
	if cmd == null:
		return false
	if not cmd.has_method("is_enabled"):
		return true
	return bool(cmd.call("is_enabled"))


static func display_title(cmd: Object) -> String:
	var title := _str_member(cmd, "title")
	return title if not title.is_empty() else _str_member(cmd, "id")


static func shortcut_for(cmd: Object) -> String:
	if cmd == null:
		return ""
	if cmd.has_method("shortcut_text"):
		return str(cmd.call("shortcut_text"))
	return _str_member(cmd, "shortcut")


## Ranked fuzzy match over the whole registry. Empty query keeps the
## registration order; otherwise best score first, id ascending on ties so
## the list is stable.
func filter(query: String) -> Array:
	var needle := query.strip_edges()
	if needle.is_empty():
		return commands.duplicate()
	var scored: Array = []
	for cmd in commands:
		var s := score(needle, cmd)
		if s < 0:
			continue
		scored.append({"cmd": cmd, "score": s, "id": _str_member(cmd, "id")})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return str(a["id"]) < str(b["id"])
	)
	var out: Array = []
	for row in scored:
		out.append(row["cmd"])
	return out


## Best of the title / id / category matches. -1 when nothing matches.
static func score(query: String, cmd: Object) -> int:
	var best := -1
	best = maxi(best, match_score(query, _str_member(cmd, "title")))
	# id and category are secondary: a title hit should outrank them.
	best = maxi(best, match_score(query, _str_member(cmd, "id")) - 20)
	best = maxi(best, match_score(query, _str_member(cmd, "category")) - 40)
	return best


## Subsequence match with word-boundary and contiguity bonuses. -1 = miss.
static func match_score(query: String, text: String) -> int:
	var q := query.strip_edges().to_lower()
	var t := text.to_lower()
	if q.is_empty():
		return 0
	if t.is_empty():
		return -1
	var total := 0
	var at := 0
	var prev := -2
	for i in q.length():
		var ch := q[i]
		if ch == " ":
			# Spaces separate terms; they never have to match a character.
			continue
		var hit := t.find(ch, at)
		if hit < 0:
			return -1
		total += 10
		if hit == prev + 1:
			total += 15
		if _is_word_start(t, hit):
			total += 30
		prev = hit
		at = hit + 1
	var flat := q.replace(" ", "")
	var sub := t.find(flat)
	if sub >= 0:
		total += 50
		if sub == 0:
			total += 100
		elif _is_word_start(t, sub):
			total += 40
	# Length only breaks ties: "Frame map" beats "Frame map selection".
	return total + maxi(0, 20 - t.length())


static func _is_word_start(text: String, i: int) -> bool:
	if i <= 0:
		return true
	var before := text[i - 1]
	return before == " " or before == "." or before == "_" or before == "-"


func _scan_root(root: String) -> void:
	if root == USER_DIR:
		ensure_user_dir()
	var dir := DirAccess.open(root)
	if dir == null:
		# A missing user folder is the normal case, not an error.
		if root != USER_DIR:
			errors.append("command root unreadable: %s" % root)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			# An exported build serves scripts as .gd, .gdc (binary tokens)
			# or a .remap stub. load() wants the logical .gd path in every
			# case, so normalise before deduping.
			var logical := _logical_script_name(fn)
			if not logical.is_empty() and not names.has(logical):
				names.append(logical)
		fn = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		_load_file(root.path_join(name))


static func _logical_script_name(file_name: String) -> String:
	var name := file_name
	if name.to_lower().ends_with(".remap"):
		name = name.substr(0, name.length() - 6)
	if name.to_lower().ends_with(".gdc"):
		name = name.substr(0, name.length() - 1)
	if name.to_lower().ends_with(".gd"):
		return name
	return ""


func _load_file(path: String) -> void:
	var res: Variant = load(path)
	var script := res as GDScript
	if script == null:
		errors.append("not a GDScript: %s" % path)
		return
	if not script.can_instantiate():
		errors.append("does not compile: %s" % path)
		return
	var made: Variant = script.new()
	if made == null:
		errors.append("could not instantiate: %s" % path)
		return
	if made is Node:
		# Nodes would leak: nothing here ever adds them to a tree.
		errors.append("command must be a RefCounted, not a Node: %s" % path)
		(made as Node).free()
		return
	if not (made is Object):
		errors.append("command script produced no object: %s" % path)
		return
	var declared: Array = [made]
	if (made as Object).has_method("command_list"):
		var listed: Variant = (made as Object).call("command_list")
		if listed is Array:
			declared = listed as Array
		else:
			errors.append("command_list() did not return an Array: %s" % path)
			return
	for entry in declared:
		_register(entry, path)


func _register(cmd: Variant, path: String) -> void:
	if not (cmd is Object) or cmd == null:
		errors.append("command entry is not an object: %s" % path)
		return
	var obj := cmd as Object
	if not obj.has_method("run"):
		errors.append("command has no run(): %s" % path)
		return
	var id := _str_member(obj, "id").strip_edges()
	if id.is_empty():
		errors.append("command has no id: %s" % path)
		return
	if _by_id.has(id):
		overrides.append("%s (%s)" % [id, path])
	_by_id[id] = obj


static func _member(obj: Object, name: String, fallback: Variant) -> Variant:
	if obj == null:
		return fallback
	var value: Variant = obj.get(name)
	return fallback if value == null else value


static func _str_member(obj: Object, name: String) -> String:
	var value: Variant = _member(obj, name, "")
	return str(value)
