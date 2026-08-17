extends RefCounted
class_name BzValidate
## `bzmap editor validate` — run the existing validators on a session.
##
## Port of backend/bzmap/editor/validate.py. Payload shape is docs/02 §3
## "validate". `report.json` is written to the session directory.
##
## Python raises EditorError; this returns BzErrors.err(...). Dirty sessions
## are materialized via BzSave.save_session (same as the Python verb).


static func validate_session(
	session_dir: String, tier: String = "1,2", game_root: String = ""
) -> Dictionary:
	## Validate the session. Materializes to a temp dir when anything is dirty.
	var paths: Dictionary = _session_paths(session_dir)
	if not FileAccess.file_exists(str(paths["manifest"])):
		return BzErrors.err(
			"no_session",
			"no manifest.json in %s" % session_dir,
			"",
			session_dir
		)

	var dirty := {}
	if FileAccess.file_exists(str(paths["dirty"])):
		var raw: Variant = _read_json(str(paths["dirty"]))
		if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).get("ok", true) == false \
				and (raw as Dictionary).has("error"):
			return raw
		if typeof(raw) == TYPE_DICTIONARY:
			dirty = raw

	# Unused today: tiers other than 1 still go through validate_map (Tier 1).
	# Tier 2 layout validators need a LayoutGraph the session does not have.
	var _tier: String = tier

	var target: String = ""
	if _session_is_clean(dirty) and DirAccess.dir_exists_absolute(str(paths["source"])):
		target = str(paths["source"])
	else:
		var tmp: String = _mkdtemp("bzmap-validate-")
		var saved: Dictionary = _materialize(session_dir, tmp)
		if BzErrors.is_err(saved):
			return saved
		target = tmp

	var ref: String = game_root
	var problems: PackedStringArray = BzCheckFormats.validate_map(target, ref)
	var findings: Array = []
	for i in problems.size():
		findings.append(_finding(problems[i], i + 1))
	var errors: Array = []
	for f in findings:
		if str((f as Dictionary).get("severity", "")) == "error":
			errors.append(f)
	var payload := {
		"ok": errors.is_empty(),
		"findings": findings,
	}
	_write_json(str(paths["report"]), payload)
	return payload


static func _finding(problem: Variant, index: int) -> Dictionary:
	var text: String = str(problem)
	var severity := "error"
	if text.begins_with("[warning]"):
		severity = "warning"
		text = text.substr("[warning]".length()).strip_edges()
	elif text.begins_with("[error]"):
		text = text.substr("[error]".length()).strip_edges()
	return {
		"id": "V%d" % index,
		"severity": severity,
		"title": text.substr(0, 96),
		"detail": text,
		"world_pos": null,
		"object_id": null,
		"variant": null,
	}


static func _session_is_clean(dirty: Dictionary) -> bool:
	if dirty.get("terrain") or dirty.get("materials") or dirty.get("features"):
		return false
	var meta: Variant = dirty.get("meta")
	if meta:
		return false
	return not _objects_dirty(dirty)


static func _objects_dirty(dirty: Dictionary) -> bool:
	## Private copy of BzSave._objects_dirty (that file is another agent's).
	var objects: Variant = dirty.get("objects")
	if objects == null:
		return false
	if typeof(objects) == TYPE_BOOL:
		return bool(objects)
	if typeof(objects) == TYPE_DICTIONARY:
		for v in (objects as Dictionary).values():
			if v:
				return true
		return false
	return bool(objects)


static func _materialize(session_dir: String, out_dir: String) -> Dictionary:
	## Python calls save_session. Loaded by path so a mid-port BzSave
	## compile error cannot take this verb down with it.
	var script: Script = load("res://project/backend/editor/BzSave.gd")
	if script != null and script.has_method("save_session"):
		var result: Variant = script.call("save_session", session_dir, out_dir)
		if typeof(result) == TYPE_DICTIONARY:
			return result
	return BzErrors.err(
		"save_unavailable",
		"dirty session requires BzSave to materialize a map directory",
		"validate a clean session (residue/source present, dirty.json all false) or wait for BzSave"
	)


static func _session_paths(session_dir: String) -> Dictionary:
	## Private copy of BzSession.session_paths — class_name lookup for
	## BzSession has been flaky while that file is still being edited.
	var root: String = session_dir
	var residue: String = root.path_join("residue")
	return {
		"root": root,
		"manifest": root.path_join("manifest.json"),
		"terrain": root.path_join("terrain.r16"),
		"materials": root.path_join("materials.u16"),
		"objects": root.path_join("objects.json"),
		"features": root.path_join("features.json"),
		"meta": root.path_join("meta.json"),
		"dirty": root.path_join("dirty.json"),
		"report": root.path_join("report.json"),
		"masks": root.path_join("masks"),
		"residue": residue,
		"source": residue.path_join("source"),
		"hg2_header": residue.path_join("hg2_header.json"),
		"hg2_flags": residue.path_join("hg2_flags.u8"),
	}


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return BzErrors.err("invalid_json", "failed to parse JSON: %s" % path, "", path)
	return parsed


static func _write_json(path: String, payload: Variant) -> void:
	var text: String = JSON.stringify(payload, "  ")
	if not text.ends_with("\n"):
		text += "\n"
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


static func _mkdtemp(prefix: String) -> String:
	var root: String = OS.get_temp_dir()
	var name: String = "%s%d-%d" % [prefix, Time.get_ticks_usec(), randi()]
	var path: String = root.path_join(name)
	DirAccess.make_dir_recursive_absolute(path)
	return path
