extends RefCounted
class_name BzTrn
## ``.trn`` terrain INI reader/writer — ordered, comment-preserving.
##
## Port of ``backend/bzmap/formats/trn.py``. The source file is kept verbatim
## and only rewritten lines are touched, so an untouched config round-trips
## byte-for-byte when the source uses CRLF (write always emits CRLF).

const _EOL := "\r\n"
const _TRN_TEMPLATE := "elysium.trn"
# ``[Size]`` origin values for a standalone map. Matches trn.py _STANDALONE_SIZE.
const _STANDALONE_SIZE := [
	["MinX", "0"],
	["MinZ", "0"],
	["Height", "0.000000"],
]


# -- module-level wrappers ---------------------------------------------------

static func read_trn(path: String) -> Variant:
	## Returns TerrainConfig, or null if the file is missing.
	## Variant (not TerrainConfig) so the static binds on the class_name —
	## Godot 4.7 drops outer statics whose signature names an inner class.
	return TerrainConfig.read(path)


static func write_trn(path: String, config: Variant) -> void:
	if config == null:
		push_error("write_trn: config is null")
		return
	(config as TerrainConfig).write(path)


static func write_complete_trn(
	path: String,
	width_m: float,
	depth_m: float,
	template_path: String = ""
) -> String:
	## Write a complete ``.trn`` for a width_m × depth_m map by cloning a
	## template and rewriting only ``[Size]``.
	var template := template_path
	if template.is_empty():
		template = _default_template()
	if not FileAccess.file_exists(template):
		push_error(
			"trn template not found: %s (vendored reference/elysium.trn ships with the repo)"
			% template
		)
		return ""
	var cfg: TerrainConfig = read_trn(template)
	if cfg == null:
		return ""
	if cfg.section("Size") == null:
		push_error("trn template has no [Size] section: %s" % template)
		return ""
	for pair in _STANDALONE_SIZE:
		cfg.set("Size", pair[0], pair[1])
	cfg.set("Size", "Width", str(int(width_m)))
	cfg.set("Size", "Depth", str(int(depth_m)))
	cfg.write(path)
	return path


static func _default_template() -> String:
	return ProjectSettings.globalize_path("res://project/backend/reference").path_join(_TRN_TEMPLATE)


# -- TerrainConfig -----------------------------------------------------------

class TerrainConfig:
	extends RefCounted
	## Ordered, comment-preserving representation of a ``.trn`` INI.

	var sections: Array = []
	var _lines: PackedStringArray = PackedStringArray()
	var _dirty: bool = false

	func _init(p_sections: Array = [], p_lines: Variant = PackedStringArray()) -> void:
		sections = p_sections
		_lines = BzTrn._as_lines(p_lines)
		_dirty = false

	static func read(path: String) -> TerrainConfig:
		## Read a ``.trn`` into a TerrainConfig. Missing file → null.
		if not FileAccess.file_exists(path):
			push_error("trn file not found: %s" % path)
			return null
		var text := BzTrn._read_text_utf8_sig(path)
		var lines := BzTrn._splitlines(text)
		var parsed: Array = []
		var current: Section = null
		for lineno in lines.size():
			var line: String = lines[lineno]
			var stripped := line.strip_edges()
			if stripped.is_empty() or stripped.begins_with(";") or stripped.begins_with("#"):
				# Comment, blank, or opaque line — not part of any section.
				continue
			if stripped.begins_with("["):
				# Section headers may carry trailing text after the bracket —
				# corpus maps write ``[TextureType0] // Lava`` (and one as
				# ``[TextureType1] Lava Pool`` with no comment marker).
				var close := stripped.find("]")
				if close > 0:
					current = Section.new(stripped.substr(1, close - 1), lineno)
					parsed.append(current)
					continue
			if current != null and line.contains("="):
				var eq := line.find("=")
				var key := line.substr(0, eq).strip_edges()
				var value := line.substr(eq + 1).strip_edges()
				current._add(key, value, lineno)
		return TerrainConfig.new(parsed, lines)

	func write(path: String) -> void:
		## Write this config. Untouched → source lines joined with CRLF.
		## Dirty → only changed / pending key lines are rewritten.
		var text := ""
		if _dirty:
			var out_lines: Array[String] = []
			for line in _lines:
				out_lines.append(line)
			for section in sections:
				var sec: Section = section
				for raw_item in sec._items:
					var item: Dictionary = raw_item
					if item["value"] == item["orig"]:
						continue
					var lineno: int = item["lineno"]
					if lineno >= 0 and lineno < out_lines.size():
						out_lines[lineno] = "%s = %s" % [item["key"], item["value"]]
				if not sec._pending.is_empty():
					# Append queued keys after the section's last existing line
					# (falling back to the file end). Header lineno is discarded
					# in Python, so an empty section's pending keys land at EOF.
					var insert := -1
					for raw_item in sec._items:
						var item: Dictionary = raw_item
						var lineno: int = item["lineno"]
						if lineno >= 0:
							insert = maxi(insert, lineno)
					if insert < 0:
						insert = out_lines.size()
					else:
						insert += 1
					var pending_lines: Array[String] = []
					for raw_p in sec._pending:
						var pair: Array = raw_p
						pending_lines.append("%s = %s" % [pair[0], pair[1]])
					for j in pending_lines.size():
						out_lines.insert(insert + j, pending_lines[j])
			text = _EOL.join(PackedStringArray(out_lines))
			if not _lines.is_empty():
				text += _EOL
		else:
			text = _EOL.join(_lines)
			if not _lines.is_empty():
				text += _EOL
		BzTrn._write_text(path, text)

	func ensure_section(p_name: String) -> Section:
		## The section, appended to the file if it is not there yet.
		##
		## `set` refuses to create sections, and a `.trn` written by hand or by
		## an older tool can be missing `[NormalView]` entirely — writing the
		## sun clock into such a file has to add the header, not push_error.
		var got: Variant = section(p_name)
		if got != null:
			return got as Section
		if not _lines.is_empty() and not _lines[_lines.size() - 1].strip_edges().is_empty():
			_lines.append("")
		_lines.append("[%s]" % p_name)
		var sec := Section.new(p_name, -1)
		sections.append(sec)
		_dirty = true
		return sec

	func sections_named(p_name: String) -> Array:
		var found: Array = []
		for section in sections:
			var sec: Section = section
			if sec.name == p_name:
				found.append(sec)
		return found

	func section(p_name: String, first_only: bool = true) -> Variant:
		## First section named ``p_name``, or all of them when first_only is false.
		var found := sections_named(p_name)
		if first_only:
			return found[0] if not found.is_empty() else null
		return found

	@warning_ignore("native_method_override")
	func get(section: Variant, key: Variant = null, default: Variant = null) -> Variant:
		## Value of ``key`` in ``section``, or ``default``.
		##
		## Python-vs-spec: F3 says keys are matched case-insensitively.
		## TerrainConfig.get/set use ``==`` (case-sensitive), matching trn.py.
		## First occurrence wins — that part matches F3's duplicate-key rule.
		if key == null:
			return super.get(StringName(str(section)))
		var sec: Section = null
		if section is Section:
			sec = section
		else:
			var got: Variant = self.section(str(section))
			if got != null:
				sec = got
		if sec == null:
			return default
		var found: Variant = sec.get(StringName(str(key)))
		return default if found == null else found

	@warning_ignore("native_method_override")
	func set(section: Variant, key: Variant = null, value: Variant = null) -> void:
		## Set ``key`` in ``section``. Marks the config dirty.
		if value == null:
			super.set(StringName(str(section)), key)
			return
		var sec: Section = null
		if section is Section:
			sec = section
		else:
			var got: Variant = self.section(str(section))
			if got != null:
				sec = got
		if sec == null:
			push_error("no section named %s" % str(section))
			return
		sec._set_item(str(key), BzTrn._py_str(value))
		_dirty = true


class Section:
	extends RefCounted
	## One ``[name]`` block of a ``.trn`` file.

	var name: String = ""
	# [{key, value, lineno, orig}, ...] — lineno is -1 when not from source.
	var _items: Array = []
	# [[key, value], ...] queued to append on write.
	var _pending: Array = []

	func _init(p_name: String = "", _lineno: int = -1) -> void:
		# Python accepts the header lineno but does not store it.
		name = p_name

	func _add(key: String, value: String, lineno: int) -> void:
		_items.append({
			"key": key,
			"value": value,
			"lineno": lineno,
			"orig": value,
		})

	func _set_item(key: String, value: String) -> void:
		# Named _set_item: Object._set(StringName, Variant) -> bool is reserved.
		for i in _items.size():
			var item: Dictionary = _items[i]
			if item["key"] == key:
				item["value"] = value
				_items[i] = item
				return
		for i in _pending.size():
			var pair: Array = _pending[i]
			if pair[0] == key:
				_pending[i] = [key, value]
				return
		_pending.append([key, value])

	@warning_ignore("native_method_override")
	func get(key: StringName) -> Variant:
		## INI-key lookup. Signature matches Object.get so Godot 4.7 will
		## compile this inner class; missing keys return null (Python default).
		var needle := String(key)
		for raw_item in _items:
			var item: Dictionary = raw_item
			if item["key"] == needle:
				return item["value"]
		for raw_p in _pending:
			var pair: Array = raw_p
			if pair[0] == needle:
				return pair[1]
		return null

	func keys() -> Array:
		var out: Array = []
		for raw_item in _items:
			var item: Dictionary = raw_item
			out.append(item["key"])
		for raw_p in _pending:
			var pair: Array = raw_p
			out.append(pair[0])
		return out

	func items() -> Array:
		var out: Array = []
		for raw_item in _items:
			var item: Dictionary = raw_item
			out.append([item["key"], item["value"]])
		for raw_p in _pending:
			var pair: Array = raw_p
			out.append([pair[0], pair[1]])
		return out

	func _to_string() -> String:
		return "Section('%s')" % name


# -- text helpers (utf-8-sig + Python splitlines) ----------------------------

static func _as_lines(p_lines: Variant) -> PackedStringArray:
	if p_lines is PackedStringArray:
		return p_lines
	var out := PackedStringArray()
	if p_lines == null:
		return out
	for line in p_lines:
		out.append(str(line))
	return out


static func _read_text_utf8_sig(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var text := bytes.get_string_from_utf8()
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	return text


static func _write_text(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(text.to_utf8_buffer())
	return OK


static func _splitlines(text: String) -> PackedStringArray:
	## Python 3 ``str.splitlines()`` (keepends=False).
	var lines := PackedStringArray()
	var start := 0
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text.unicode_at(i)
		var br := 0
		if ch == 0x0D:
			br = 2 if (i + 1 < n and text.unicode_at(i + 1) == 0x0A) else 1
		elif (
			ch == 0x0A or ch == 0x0B or ch == 0x0C
			or ch == 0x1C or ch == 0x1D or ch == 0x1E
			or ch == 0x85 or ch == 0x2028 or ch == 0x2029
		):
			br = 1
		if br > 0:
			lines.append(text.substr(start, i - start))
			i += br
			start = i
		else:
			i += 1
	if start < n:
		lines.append(text.substr(start, n - start))
	return lines


static func _py_str(value: Variant) -> String:
	## ``str(value)`` as Python would format it (used by Section._set).
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
