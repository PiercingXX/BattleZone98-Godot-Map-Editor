extends RefCounted
class_name LogRouter
## Classifies shell log lines (level + whether they also toast).


const LEVEL_INFO := "info"
const LEVEL_WARNING := "warning"
const LEVEL_ERROR := "error"

const COLOR_INFO := "9a9aa0"
const COLOR_WARNING := "e0a23a"
const COLOR_ERROR := "f25851"


static func infer_level(text: String, level: String = "") -> String:
	var explicit := level.strip_edges().to_lower()
	if explicit == LEVEL_ERROR or explicit == LEVEL_WARNING or explicit == LEVEL_INFO:
		return explicit
	var raw := text.strip_edges()
	var lower := raw.to_lower()
	if raw.begins_with("ERROR") or lower.begins_with("error"):
		return LEVEL_ERROR
	if lower.begins_with("warning") or lower.begins_with("hint:"):
		return LEVEL_WARNING
	return LEVEL_INFO


static func should_toast(text: String, level: String = "") -> bool:
	var lv := infer_level(text, level)
	if lv == LEVEL_ERROR:
		return true
	var raw := text.strip_edges()
	var lower := raw.to_lower()
	if lower.begins_with("opened "):
		return true
	if lower.begins_with("saved ") and " files to " in lower:
		return true
	if lower.begins_with("package addon"):
		return true
	if _is_screenshot_path(raw):
		return true
	if " classes" in lower and " unresolved" in lower:
		return true
	if lower.begins_with("test pass") or lower.begins_with("test fail"):
		return true
	if lower.begins_with("no verdict"):
		return true
	if lower.begins_with("test cancelled") or lower.begins_with("test aborted"):
		return true
	if lower.begins_with("could not launch steam"):
		return true
	return false


static func route(text: String, level: String = "", toast: bool = false) -> Dictionary:
	var lv := infer_level(text, level)
	return {
		"text": text,
		"level": lv,
		"toast": toast or should_toast(text, lv),
	}


static func bbcode_line(text: String, level: String = "") -> String:
	var lv := infer_level(text, level)
	var hex := COLOR_INFO
	if lv == LEVEL_ERROR:
		hex = COLOR_ERROR
	elif lv == LEVEL_WARNING:
		hex = COLOR_WARNING
	return "[color=#%s]%s[/color]" % [hex, escape_bbcode(text)]


static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


static func _is_screenshot_path(text: String) -> bool:
	var n := text.strip_edges().replace("\\", "/")
	var lower := n.to_lower()
	if not lower.ends_with(".png"):
		return false
	if lower.begins_with("screenshot failed") or lower.begins_with("screenshot:"):
		return false
	return "/screenshots/" in n or lower.begins_with("screenshot ")
