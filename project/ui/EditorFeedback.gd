extends RefCounted
class_name EditorFeedback
## UI panels log through the shell when it is in the tree.


static func log(msg: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var shell := tree.get_first_node_in_group("editor_shell")
	if shell != null and shell.has_method("_log"):
		shell.call("_log", msg)
