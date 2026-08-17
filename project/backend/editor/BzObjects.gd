extends RefCounted
class_name BzObjects
## objects.json <-> BZN object blocks (docs/02 §4a, objects.py).
##
## Python returns tuples; GDScript returns Dictionaries. Fallible helpers
## return BzErrors.err() (check with BzErrors.is_err). GameObject mutation
## goes through BzBzn — this file does not assemble [GameObject] text.


static func objects_from_bzn(bzn: Variant, id_prefix: String = "obj") -> Dictionary:
	var file: Variant = bzn
	if typeof(bzn) == TYPE_DICTIONARY and (bzn as Dictionary).has("bznfile"):
		file = (bzn as Dictionary)["bznfile"]
	var records: Array = []
	var blocks := {}
	var objs: Array = file.objects if file != null else []
	for i in objs.size():
		var obj: Variant = objs[i]
		var obj_id: String = "%s-%04d" % [id_prefix, i + 1]
		var pos: Variant = obj.position() if obj.has_method("position") else null
		var x := 0.0
		var y := 0.0
		var z := 0.0
		if pos is Array and (pos as Array).size() >= 3:
			x = float(pos[0])
			y = float(pos[1])
			z = float(pos[2])
		var prjid_s: String = "" if obj.prjid == null else str(obj.prjid)
		var label_s: String = "" if obj.label == null else str(obj.label)
		var team_i: int = 0 if obj.team == null else int(obj.team)
		var required: bool = obj.is_user() or prjid_s.to_lower() == "player"
		var record := {
			"id": obj_id,
			"origin": "source",
			"prjid": obj.prjid,
			"x": x,
			"y": y,
			"z": z,
			"yaw_deg": obj.yaw_deg(),
			"team": team_i,
			"label": label_s,
			"up_convention": "upright",
			"pinned_y": false,
			"managed": false,
			"required": required,
		}
		records.append(record)
		blocks[obj_id] = obj
	return {"ok": true, "records": records, "blocks": blocks}


static func load_variant_objects(path: String, id_prefix: String = "obj") -> Dictionary:
	if not FileAccess.file_exists(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var loaded: Dictionary = BzBzn.read_bzn(path)
	if not bool(loaded.get("ok", false)):
		if BzErrors.is_err(loaded):
			return loaded
		var err: Variant = loaded.get("error", {})
		var code: String = "value_error"
		var message: String = "failed to read BZN: %s" % path
		var hint: String = ""
		if typeof(err) == TYPE_DICTIONARY:
			code = str((err as Dictionary).get("code", code))
			message = str((err as Dictionary).get("message", message))
			hint = str((err as Dictionary).get("hint", ""))
		return BzErrors.err(code, message, hint, path)
	var bzn: Variant = loaded.get("bznfile")
	var pair: Dictionary = objects_from_bzn(bzn, id_prefix)
	return {
		"ok": true,
		"records": pair["records"],
		"blocks": pair["blocks"],
		"bzn": bzn,
	}


static func template_text_for(prjid: String, source_dir: String, extra_bzns: Array = []) -> String:
	var wanted: String = prjid.to_lower()
	var search: Array = []
	if DirAccess.dir_exists_absolute(source_dir):
		var bzns: Array = []
		var da := DirAccess.open(source_dir)
		if da != null:
			da.include_hidden = true
			da.include_navigational = false
			da.list_dir_begin()
			var fn: String = da.get_next()
			while fn != "":
				if not da.current_is_dir() and fn.get_extension().to_lower() == "bzn":
					bzns.append(source_dir.path_join(fn))
				fn = da.get_next()
			da.list_dir_end()
		bzns.sort()
		search.append_array(bzns)
	for extra in extra_bzns:
		var extra_path: String = str(extra)
		if FileAccess.file_exists(extra_path):
			search.append(extra_path)
	for path in search:
		var loaded: Dictionary = BzBzn.read_bzn(str(path))
		if not bool(loaded.get("ok", false)):
			continue
		var bzn: Variant = loaded.get("bznfile")
		if bzn == null:
			continue
		for obj in bzn.objects:
			var got: String = "" if obj.prjid == null else str(obj.prjid)
			if got.to_lower() == wanted:
				return obj.render()
	return ""


static func apply_record_to_block(obj: Variant, record: Dictionary) -> Variant:
	obj.set_position(float(record["x"]), float(record["y"]), float(record["z"]))
	obj.set_yaw(deg_to_rad(float(record.get("yaw_deg", 0.0))))
	if record.get("team") != null:
		# Python swallows KeyError when the block has no team [1] field.
		obj.set_team(record["team"])
	var label_v: Variant = record.get("label")
	if label_v != null and str(label_v) != "":
		var seqno: int = 0 if obj.seqno == null else int(obj.seqno)
		var addr: int = 1 if obj.obj_addr == null else int(obj.obj_addr)
		obj.set_identity(seqno, addr, str(label_v))
	return obj
