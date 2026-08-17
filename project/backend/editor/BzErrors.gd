extends RefCounted
class_name BzErrors
## Structured editor-bridge errors (docs/02 §5, Python EditorError.as_dict).
##
## Python raises EditorError(code, message, hint=None, path=None). GDScript
## never throws: every failure is this payload. Empty hint/path are omitted
## to match EditorError.as_dict(); docs/02 §5 shows them present because the
## example has both set.


static func err(code: String, message: String, hint: String = "", path: String = "") -> Dictionary:
	var error := {
		"code": code,
		"message": message,
	}
	if not hint.is_empty():
		error["hint"] = hint
	if not path.is_empty():
		error["path"] = path
	return {"ok": false, "error": error}


## True when `result` is a BzErrors.err() payload (not a verb/report with ok=false).
static func is_err(result: Variant) -> bool:
	if typeof(result) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = result
	if payload.get("ok", true) != false:
		return false
	if not payload.has("error"):
		return false
	var error: Variant = payload["error"]
	if typeof(error) != TYPE_DICTIONARY:
		return false
	return (error as Dictionary).has("code")
