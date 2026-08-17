extends RefCounted
class_name BzTemplates
## Verbatim template blocks for template-and-mutate.
##
## Port of ``backend/bzmap/formats/templates.py``. Loads known-good BZN
## header / tail / object blocks. A stock ``.bzn`` (``bzn_path``) takes
## precedence; ``reference/`` is the fallback.
##
## GameObject.from_template / BznFile.read used by the Python module are
## inlined here (same algorithms as bzn.py) so this file does not depend
## on BzBzn's inner-class layout.

const _EOL := "\r\n"
const _OBJECT_TEMPLATE := "bzn-object-template.txt"
const _HEADER_TAIL_TEMPLATE := "bzn-header-tail-template.txt"
const DEFAULT_REFERENCE_DIR := "res://project/backend/reference"


static func template(prjid: String, bzn_path: String = "") -> String:
	## Return the verbatim ``[GameObject]`` block for ``prjid``.
	return TemplateLoader.new("", bzn_path).object(prjid)


class TemplateLoader:
	extends RefCounted
	## Loads verbatim header/tail/object blocks for template-and-mutate.

	var reference_dir: String = ""
	var bzn_path: String = ""
	var _bzn: _BznLite = null
	var _bzn_loaded: bool = false

	func _init(p_reference_dir: String = "", p_bzn_path: String = "") -> void:
		if p_reference_dir.is_empty():
			reference_dir = DEFAULT_REFERENCE_DIR
		else:
			reference_dir = p_reference_dir
		bzn_path = p_bzn_path

	func _load_bzn() -> _BznLite:
		if bzn_path.is_empty():
			return null
		if not _bzn_loaded:
			_bzn_loaded = true
			_bzn = _BznLite.read(bzn_path)
		return _bzn

	func _read_reference(filename: String) -> String:
		var path := reference_dir.path_join(filename)
		if not FileAccess.file_exists(path):
			push_error("reference template not found: %s" % path)
			return ""
		return BzTemplates._read_text_utf8_sig(path)

	func header() -> String:
		## Verbatim BZN header block (``#`` comments stripped).
		var bzn := _load_bzn()
		if bzn != null and not bzn.header.is_empty():
			return _EOL.join(bzn.header)
		return _header_from_reference()

	func tail() -> String:
		## Verbatim BZN trailing block (``#`` comments stripped).
		var bzn := _load_bzn()
		if bzn != null and not bzn.tail.is_empty():
			return _EOL.join(bzn.tail)
		return _tail_from_reference()

	func _header_from_reference() -> String:
		# Python-vs-spec: both header and tail from the reference file return
		# the *entire* header-tail template with comments stripped (templates.py).
		return _EOL.join(BzTemplates._strip_comments(_read_reference(_HEADER_TAIL_TEMPLATE)))

	func _tail_from_reference() -> String:
		return _EOL.join(BzTemplates._strip_comments(_read_reference(_HEADER_TAIL_TEMPLATE)))

	func object(prjid: String) -> String:
		## Verbatim ``[GameObject]`` block for ``prjid`` (CRLF, no trailing NL).
		## Empty string when no matching template exists (Python raises KeyError).
		var bzn := _load_bzn()
		if bzn != null:
			for obj in bzn.objects:
				var go: _GameObjectLite = obj
				if go.prjid != null and str(go.prjid) == prjid:
					return go.render()
		return _object_from_reference(prjid)

	func _object_from_reference(prjid: String) -> String:
		var text := _read_reference(_OBJECT_TEMPLATE)
		if text.is_empty() and not FileAccess.file_exists(reference_dir.path_join(_OBJECT_TEMPLATE)):
			return ""
		var lines := BzTemplates._strip_comments(text)
		var obj := _GameObjectLite.from_template(_EOL.join(lines))
		if obj.prjid == null or str(obj.prjid) != prjid:
			var have := "None" if obj.prjid == null else str(obj.prjid)
			push_error(
				"no object template for '%s' in reference/ (only '%s' is available); pass a stock bzn_path"
				% [prjid, have]
			)
			return ""
		return obj.render()

	func available_prjids() -> Array:
		## Set of ``PrjID`` values this loader can clone (as an Array).
		var prjids: Dictionary = {}
		var obj_path := reference_dir.path_join(_OBJECT_TEMPLATE)
		if FileAccess.file_exists(obj_path):
			var text := _read_reference(_OBJECT_TEMPLATE)
			var obj := _GameObjectLite.from_template(
				_EOL.join(BzTemplates._strip_comments(text))
			)
			if obj.prjid != null:
				prjids[str(obj.prjid)] = true
		var bzn := _load_bzn()
		if bzn != null:
			for obj in bzn.objects:
				var go: _GameObjectLite = obj
				if go.prjid != null:
					prjids[str(go.prjid)] = true
		return prjids.keys()


# -- inlined BznFile.read / GameObject.from_template (templates.py usage) ----

class _GameObjectLite:
	extends RefCounted
	var lines: PackedStringArray = PackedStringArray()
	var prjid: Variant:
		get:
			return get_field("PrjID [1]")

	func _init(p_lines: Variant = PackedStringArray()) -> void:
		lines = BzTemplates._as_lines(p_lines)

	static func from_template(text: String) -> _GameObjectLite:
		return _GameObjectLite.new(BzTemplates._strip_comments(text))

	func render() -> String:
		return _EOL.join(lines)

	func get_field(key: String, default: Variant = null) -> Variant:
		return BzTemplates._get_value(lines, key, default)


class _BznLite:
	extends RefCounted
	var header: PackedStringArray = PackedStringArray()
	var objects: Array = []
	var tail: PackedStringArray = PackedStringArray()

	static func read(path: String) -> _BznLite:
		if not FileAccess.file_exists(path):
			push_error("bzn file not found: %s" % path)
			return null
		var text := BzTemplates._read_text_utf8_sig(path)
		var src_lines := BzTemplates._splitlines(text)
		# Arrays (not PackedStringArray) so block appends mutate in place.
		var header_lines: Array = []
		var object_blocks: Array = []
		var tail_lines: Array = []
		var current: Array = []
		var has_current := false
		for line in src_lines:
			var stripped: String = line.strip_edges()
			if stripped == "[GameObject]":
				var block: Array = [line]
				object_blocks.append(block)
				current = block
				has_current = true
				continue
			if stripped == "[AiMission]":
				current = tail_lines
				has_current = true
				tail_lines.append(line)
				continue
			if not has_current:
				header_lines.append(line)
			else:
				current.append(line)
		var out := _BznLite.new()
		out.header = PackedStringArray(header_lines)
		out.tail = PackedStringArray(tail_lines)
		for block in object_blocks:
			out.objects.append(_GameObjectLite.new(block))
		return out


static func _strip_comments(text: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for line in _splitlines(text):
		if line.strip_edges(true, false).begins_with("#"):
			continue
		lines.append(line)
	return lines


static func _value_line_index(lines: PackedStringArray, key: String) -> int:
	var base := key
	if base.ends_with(" [1]"):
		base = base.substr(0, base.length() - 4)
	var next_form := "%s [1] =" % base
	var inline := "%s =" % base
	for i in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped == next_form:
			return i + 1
		if stripped == inline or stripped.begins_with(inline):
			return i
	return -1


static func _get_value(lines: PackedStringArray, key: String, default: Variant = null) -> Variant:
	var idx := _value_line_index(lines, key)
	if idx < 0 or idx >= lines.size():
		return default
	var line: String = lines[idx]
	if line.contains("="):
		return line.substr(line.find("=") + 1).strip_edges()
	return line.strip_edges()


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


static func _splitlines(text: String) -> PackedStringArray:
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
