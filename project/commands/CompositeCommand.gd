extends RefCounted
class_name CompositeCommand
## Several commands as one undo step. do() runs forward, undo() runs in
## reverse, so a paint stroke plus the autotile cascade it triggered — or an
## auto-fix that touches many objects — is a single entry in the history.
##
## Duck-typed like every other command: UndoStack needs nothing new.

var commands: Array = []
## Overrides the derived label when the caller has a better name for the step.
var label: String = ""


static func of(p_commands: Array, p_label: String = "") -> CompositeCommand:
	var cmd := CompositeCommand.new()
	cmd.label = p_label
	for c in p_commands:
		cmd.add(c)
	return cmd


func add(command: RefCounted) -> void:
	if command != null:
		commands.append(command)


func size() -> int:
	return commands.size()


func is_empty() -> bool:
	return commands.is_empty()


func describe() -> String:
	if not label.is_empty():
		return label
	var labels := _child_labels()
	if labels.is_empty():
		return "batch"
	if labels.size() == 1:
		return labels[0]
	var uniform := true
	for l in labels:
		if l != labels[0]:
			uniform = false
			break
	if uniform:
		return "%d × %s" % [labels.size(), labels[0]]
	return "%s +%d more" % [labels[0], labels.size() - 1]


func cost_bytes() -> int:
	var n := 0
	for c in commands:
		# Same default UndoStack charges a command that does not price itself.
		n += (int(c.call("cost_bytes")) if c.has_method("cost_bytes") else 1024)
	return n


func do() -> void:
	for c in commands:
		if c.has_method("do"):
			c.call("do")


func undo() -> void:
	# Reverse: a later child may depend on what an earlier one wrote.
	var i := commands.size() - 1
	while i >= 0:
		var c: RefCounted = commands[i]
		i -= 1
		if c.has_method("undo"):
			c.call("undo")


func _child_labels() -> Array:
	var out: Array = []
	for c in commands:
		out.append(UndoStack.describe_command(c))
	return out
