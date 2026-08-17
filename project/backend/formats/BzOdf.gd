extends RefCounted
class_name BzOdf
## ``.odf`` per-map settings writer (``[SBPMapSettings]``).
##
## Port of ``backend/bzmap/formats/odf.py``. This is the map-settings ODF
## that game-mode Lua reads via ``OpenODF(GetMapTRNFilename())`` — not the
## per-object GameObjectClass ODF of F8 §4. ``KNOWN_SCRAP_PRJIDS`` is the
## corpus-measured expansion of ``classLabel = "scrap"``.

const _EOL := "\r\n"

## Frozen corpus set from odf.py. Compared case-insensitively via is_scrap_prjid.
const KNOWN_SCRAP_PRJIDS := ["npscr1", "npscr2", "npscr3", "sscr_1", "blc-pell"]


static func write_odf(
	path: String,
	control_points: Variant = null,
	scrap_include_spawn_points: bool = true
) -> void:
	## Write an ``.odf`` settings file. ``control_points`` is an optional
	## array of ``[name, x, z]`` triples rendered as CP<n>Name / CP<n>X / CP<n>Z.
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[SBPMapSettings]")
	lines.append("")
	if _has_control_points(control_points):
		var cps: Array = control_points
		for i in cps.size():
			var triple: Variant = cps[i]
			var name := str(triple[0])
			var x := _py_str(triple[1])
			var z := _py_str(triple[2])
			var n := i + 1
			lines.append("CP%dName = %s" % [n, name])
			lines.append("CP%dX = %s" % [n, x])
			lines.append("CP%dZ = %s" % [n, z])
	lines.append("")
	lines.append("[ScrapImpactZone]")
	lines.append("SIZ_IncludeSpawnPoints = %d" % (1 if scrap_include_spawn_points else 0))
	var text := _EOL.join(lines) + _EOL
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("write_odf failed: %s" % path)
		return
	f.store_buffer(text.to_utf8_buffer())


static func is_scrap_prjid(prjid: String) -> bool:
	## True when ``prjid`` is a known scrap class (see KNOWN_SCRAP_PRJIDS).
	var needle := prjid.to_lower()
	for item in KNOWN_SCRAP_PRJIDS:
		if item == needle:
			return true
	return false


static func _has_control_points(control_points: Variant) -> bool:
	if control_points == null:
		return false
	if control_points is Array:
		return not (control_points as Array).is_empty()
	return false


static func _py_str(value: Variant) -> String:
	if value == null:
		return "None"
	var t := typeof(value)
	if t == TYPE_BOOL:
		return "True" if value else "False"
	if t == TYPE_FLOAT:
		var f := float(value)
		if is_nan(f):
			return "nan"
		if is_inf(f):
			return "-inf" if f < 0.0 else "inf"
		var as_int := int(f)
		if float(as_int) == f:
			return "%d.0" % as_int
		return str(f)
	return str(value)
