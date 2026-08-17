extends RefCounted
class_name BzBzn
## Port of backend/bzmap/formats/bzn.py — GameObject + BznFile.
##
## The ``.bzn`` is plain ASCII (CRLF) ``binarySave = false``. Two key/value
## forms are load-bearing: ``key [1] =`` / value-on-next-line, and
## ``key = value``. Source lines are kept verbatim; only a requested mutation
## rewrites its value line. An untouched file round-trips byte-for-byte.
##
## Python-vs-spec discrepancies — Python wins:
## - F3 §2.2 says ``obj_addr`` is 8 uppercase hex and 0-based; ``set_identity``
##   writes lowercase ``{addr:08x}``, and ``validate`` requires addresses
##   contiguous from ``00000001`` (1-based, file order).
## - F3 §2.1 says ``seq_count`` equals the object count; ``validate`` checks
##   ``seq_count == max(seqno)+1`` and only when both seqnos and the header
##   key are present. A missing ``seq_count`` is not a violation.
## - F3 §3 / the Python docstring say trailing ``[AOIs]``/``[AiPaths]`` sizes
##   must be 0; ``validate`` only checks that the three section names exist.
## - docs/02 §3 save / §6 R4 say "exactly one isUser=1 player"; ``validate``
##   keys off ``PrjID == "player"`` and ``team == 1``, not ``isUser``.
## - F3 §2.4 TRN offsets are not applied here (raw stored coordinates).
## - F3 §5.6 binary detection is not in this module (editor open layer).
## - ``write`` always emits CRLF even if the source used LF-only endings.
## - ``msn_filename`` / ``TerrainName`` are never rewritten on load.

const EOL: String = "\r\n"
const _SIG_DIGITS: int = 6


static func _fail(message: String, hint: String = "") -> Dictionary:
	return {
		"ok": false,
		"error": {"code": "value_error", "message": message, "hint": hint},
	}


static func read_bzn(path: String) -> Dictionary:
	return BznFile.read(path)


static func write_bzn(path: String, bzn: BznFile) -> Dictionary:
	return bzn.write(path)


# -- line / value helpers ----------------------------------------------------


static func _split_lines(text: String) -> PackedStringArray:
	## Python ``str.splitlines()`` for ``\\r`` / ``\\n`` / ``\\r\\n``.
	var lines := PackedStringArray()
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var start: int = i
		while i < n:
			var ch: int = text.unicode_at(i)
			if ch == 0x0A or ch == 0x0D:
				break
			i += 1
		lines.append(text.substr(start, i - start))
		if i >= n:
			break
		if text.unicode_at(i) == 0x0D and (i + 1) < n and text.unicode_at(i + 1) == 0x0A:
			i += 2
		else:
			i += 1
	return lines


static func _has_trailing_newline(text: String) -> bool:
	return text.ends_with("\n") or text.ends_with("\r")


static func _strip_comments(text: String) -> PackedStringArray:
	## Drop template annotation lines (``#`` / ``###``).
	var out := PackedStringArray()
	for line in _split_lines(text):
		if line.strip_edges(true, false).begins_with("#"):
			continue
		out.append(line)
	return out


static func _value_line_index(lines: PackedStringArray, key: String) -> int:
	## Index of the value line for ``key``, or -1 if absent.
	var base: String = key
	if base.ends_with(" [1]"):
		base = base.trim_suffix(" [1]")
	var next_form: String = "%s [1] =" % base
	var inline: String = "%s =" % base
	for i in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped == next_form:
			return i + 1
		if stripped == inline or stripped.begins_with(inline):
			return i
	return -1


static func _get_value(lines: PackedStringArray, key: String, default_value: Variant = null) -> Variant:
	var idx: int = _value_line_index(lines, key)
	if idx < 0 or idx >= lines.size():
		return default_value
	var line: String = lines[idx]
	if line.contains("="):
		var eq: int = line.find("=")
		return line.substr(eq + 1).strip_edges()
	return line.strip_edges()


static func _pos_value_indices(lines: PackedStringArray) -> Array:
	## ``(x, y, z)`` value-line indices for each ``pos [1] =`` block.
	var result: Array = []
	for i in lines.size():
		if lines[i].strip_edges() != "pos [1] =":
			continue
		var idx: Dictionary = {}
		var end: int = mini(i + 7, lines.size())
		var j: int = 0
		var k: int = i + 1
		while k < end:
			var stripped: String = lines[k].strip_edges()
			if stripped == "x [1] =":
				idx["x"] = i + j + 2
			elif stripped == "y [1] =":
				idx["y"] = i + j + 2
			elif stripped == "z [1] =":
				idx["z"] = i + j + 2
			j += 1
			k += 1
		if idx.size() == 3:
			result.append([int(idx["x"]), int(idx["y"]), int(idx["z"])])
	return result


static func _split_blocks(lines: PackedStringArray) -> Dictionary:
	## Partition into ``{header, objects, tail}``.
	var header: Array = []
	var objects: Array = []
	var tail: Array = []
	var current: Array = []
	var mode: int = 0
	for raw in lines:
		var line: String = String(raw)
		var stripped: String = line.strip_edges()
		if stripped == "[GameObject]":
			current = [line]
			objects.append(current)
			mode = 1
			continue
		if stripped == "[AiMission]":
			tail = [line]
			mode = 2
			continue
		if mode == 0:
			header.append(line)
		elif mode == 2:
			tail.append(line)
		else:
			current.append(line)
	return {
		"header": PackedStringArray(header),
		"objects": objects,
		"tail": PackedStringArray(tail),
	}


# -- C %g with three-digit exponents (docs/02 §1 / Python ``_fmt_float``) ----


static func _is_neg_zero(value: float) -> bool:
	if value != 0.0:
		return false
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_double(value)
	buf.seek(0)
	buf.get_32()
	var hi: int = buf.get_32()
	return (hi & 0x80000000) != 0


static func _neg_zero() -> float:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_32(0)
	buf.put_32(0x80000000)
	buf.seek(0)
	return buf.get_double()


static func _neg_float(value: float) -> float:
	## IEEE-style negation so ``-0.0`` survives (Python ``set_yaw``).
	if value == 0.0:
		if _is_neg_zero(value):
			return 0.0
		return _neg_zero()
	return -value


static func _pow10(exp: int) -> float:
	var r: float = 1.0
	if exp >= 0:
		for _i in exp:
			r *= 10.0
		return r
	for _i in -exp:
		r /= 10.0
	return r


static func _ilog10(ax: float) -> int:
	var exp: int = int(floor(log(ax) / log(10.0)))
	var p: float = _pow10(exp)
	if p > 0.0 and ax < p:
		exp -= 1
	else:
		var p1: float = _pow10(exp + 1)
		if p1 > 0.0 and ax >= p1:
			exp += 1
	return exp


static func _round_half_even(x: float) -> float:
	## Python 3 ``round`` (banker's rounding) on a non-negative value.
	var f: float = floor(x)
	var frac: float = x - f
	if frac > 0.5:
		return f + 1.0
	if frac < 0.5:
		return f
	var n: int = int(f)
	if n % 2 == 0:
		return f
	return f + 1.0


static func _strip_trailing_zeros(s: String) -> String:
	if not s.contains("."):
		return s
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


static func _fmt_float(value: float) -> String:
	## Python ``f"{value:g}"`` then expand ``e+30`` → ``e+030``.
	if is_nan(value):
		return "nan"
	if is_inf(value):
		return "-inf" if value < 0.0 else "inf"
	if value == 0.0:
		return "-0" if _is_neg_zero(value) else "0"
	var sign: String = "-" if value < 0.0 else ""
	var ax: float = absf(value)
	var exp: int = _ilog10(ax)
	var scale_exp: int = (_SIG_DIGITS - 1) - exp
	var rnd: float = _round_half_even(ax * _pow10(scale_exp))
	var cap: float = _pow10(_SIG_DIGITS)
	var floor_cap: float = _pow10(_SIG_DIGITS - 1)
	if rnd >= cap:
		rnd = floor_cap
		exp += 1
	if rnd < floor_cap and rnd > 0.0:
		rnd *= 10.0
		exp -= 1
	var digits: String = "%d" % int(rnd)
	if exp >= -4 and exp < _SIG_DIGITS:
		var dec_pos: int = exp + 1
		var s: String
		if dec_pos <= 0:
			s = "0."
			for _i in -dec_pos:
				s += "0"
			s += digits
		elif dec_pos >= digits.length():
			s = digits
			for _i in (dec_pos - digits.length()):
				s += "0"
		else:
			s = digits.substr(0, dec_pos) + "." + digits.substr(dec_pos)
		return sign + _strip_trailing_zeros(s)
	var mant: String = _strip_trailing_zeros(digits.substr(0, 1) + "." + digits.substr(1))
	var esign: String = "+" if exp >= 0 else "-"
	return "%se%s%s" % [sign + mant, esign, str(absi(exp)).pad_zeros(3)]


# -- public classes ----------------------------------------------------------


class GameObject:
	extends RefCounted
	## One verbatim ``[GameObject]`` block with in-place value mutation.

	var lines: PackedStringArray = PackedStringArray()

	func _init(p_lines: PackedStringArray = PackedStringArray()) -> void:
		lines = p_lines.duplicate()

	static func from_template(text: String) -> GameObject:
		return GameObject.new(BzBzn._strip_comments(text))

	func set_position(x: float, y: float, z: float) -> void:
		## Update both ``pos`` blocks and ``transform.posit_*``.
		for triple in BzBzn._pos_value_indices(lines):
			var t: Array = triple
			lines[int(t[0])] = BzBzn._fmt_float(x)
			lines[int(t[1])] = BzBzn._fmt_float(y)
			lines[int(t[2])] = BzBzn._fmt_float(z)
		for pair in [["posit_x", x], ["posit_y", y], ["posit_z", z]]:
			var idx: int = BzBzn._value_line_index(lines, str(pair[0]))
			if idx >= 0:
				lines[idx] = BzBzn._fmt_float(float(pair[1]))

	func set_yaw(theta: float) -> void:
		## Pure yaw about Y: ``right=(c,0,-s)``, ``up=(0,1,0)``, ``front=(s,0,c)``.
		var c: float = cos(theta)
		var s: float = sin(theta)
		var basis := {
			"right_x": c,
			"right_y": 0.0,
			"right_z": BzBzn._neg_float(s),
			"up_x": 0.0,
			"up_y": 1.0,
			"up_z": 0.0,
			"front_x": s,
			"front_y": 0.0,
			"front_z": c,
		}
		for key in basis:
			var idx: int = BzBzn._value_line_index(lines, str(key))
			if idx >= 0:
				lines[idx] = BzBzn._fmt_float(float(basis[key]))

	func set_identity(seqno: int, addr: int, label: String) -> void:
		## ``addr`` is 8-digit *lowercase* hex (Python ``{addr:08x}``, not F3 upper).
		for key in ["seqno [1]", "seqNo [1]"]:
			var idx: int = BzBzn._value_line_index(lines, key)
			if idx >= 0:
				lines[idx] = str(seqno)
		var aidx: int = BzBzn._value_line_index(lines, "obj_addr")
		if aidx >= 0:
			lines[aidx] = "obj_addr = %08x" % addr
		var lidx: int = BzBzn._value_line_index(lines, "label")
		if lidx >= 0:
			lines[lidx] = "label = %s" % label

	func _field(key: String, default_value: Variant = null) -> Variant:
		return BzBzn._get_value(lines, key, default_value)

	var prjid: Variant:
		get:
			return _field("PrjID [1]")

	var seqno: Variant:
		get:
			var val: Variant = _field("seqno [1]")
			if val == null:
				return null
			var s: String = str(val)
			if not s.is_valid_int():
				return null
			return s.to_int()

	var label: Variant:
		get:
			return _field("label")

	var team: Variant:
		get:
			var val: Variant = _field("team [1]")
			if val == null:
				return null
			var s: String = str(val)
			if not s.is_valid_int():
				return null
			return s.to_int()

	var obj_addr: Variant:
		get:
			var val: Variant = _field("obj_addr")
			if val == null:
				return null
			var s: String = str(val).strip_edges()
			if s.is_empty():
				return null
			return s.hex_to_int()

	func position() -> Variant:
		## ``[x, y, z]`` from the first ``pos`` block, or ``null``.
		var idxs: Array = BzBzn._pos_value_indices(lines)
		if idxs.is_empty():
			return null
		var t: Array = idxs[0]
		var xs: String = lines[int(t[0])].strip_edges()
		var ys: String = lines[int(t[1])].strip_edges()
		var zs: String = lines[int(t[2])].strip_edges()
		if not xs.is_valid_float() or not ys.is_valid_float() or not zs.is_valid_float():
			return null
		return [xs.to_float(), ys.to_float(), zs.to_float()]

	func yaw_deg() -> float:
		var fx: Variant = _field("front_x [1]")
		var fz: Variant = _field("front_z [1]")
		if fx == null or fz == null:
			return 0.0
		var fxs: String = str(fx).strip_edges()
		var fzs: String = str(fz).strip_edges()
		if not fxs.is_valid_float() or not fzs.is_valid_float():
			return 0.0
		return rad_to_deg(atan2(fxs.to_float(), fzs.to_float()))

	func is_user() -> bool:
		var val: Variant = _field("isUser [1]")
		if val == null:
			return false
		var s: String = str(val).strip_edges()
		if not s.is_valid_int():
			return false
		return s.to_int() == 1

	func set_team(team: Variant) -> Dictionary:
		var idx: int = BzBzn._value_line_index(lines, "team [1]")
		if idx < 0:
			return BzBzn._fail("no team [1] field")
		var line: String = lines[idx]
		if line.contains("="):
			lines[idx] = "team [1] = %d" % int(team)
		else:
			lines[idx] = str(int(team))
		return {"ok": true}

	func set_is_user(flag: bool) -> Dictionary:
		var idx: int = BzBzn._value_line_index(lines, "isUser [1]")
		if idx < 0:
			return BzBzn._fail("no isUser [1] field")
		var value: String = "1" if flag else "0"
		var line: String = lines[idx]
		if line.contains("="):
			lines[idx] = "isUser [1] = %s" % value
		else:
			lines[idx] = value
		return {"ok": true}

	func render() -> String:
		## Block as CRLF text (no trailing newline).
		return BzBzn.EOL.join(lines)

	func _to_string() -> String:
		return "GameObject(%s)" % var_to_str(prjid)


class BznFile:
	extends RefCounted
	## Parsed ``.bzn``: header, objects, trailing ``[AiMission]`` block.

	var header: PackedStringArray = PackedStringArray()
	var objects: Array = []
	var tail: PackedStringArray = PackedStringArray()
	var _trailing_newline: bool = true
	var _dirty: bool = false

	func _init(
		p_header: PackedStringArray = PackedStringArray(),
		p_objects: Array = [],
		p_tail: PackedStringArray = PackedStringArray(),
		p_trailing_newline: bool = true
	) -> void:
		header = p_header.duplicate()
		objects = p_objects.duplicate()
		tail = p_tail.duplicate()
		_trailing_newline = p_trailing_newline
		_dirty = false

	static func read(path: String) -> Dictionary:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return BzBzn._fail(
				"%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		var raw: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		var text: String = raw.get_string_from_utf8()
		if text.begins_with("\uFEFF"):
			text = text.substr(1)
		var lines: PackedStringArray = BzBzn._split_lines(text)
		var trailing: bool = BzBzn._has_trailing_newline(text)
		var parts: Dictionary = BzBzn._split_blocks(lines)
		var objs: Array = []
		for block in parts["objects"]:
			objs.append(GameObject.new(PackedStringArray(block)))
		var bzn := BznFile.new(
			parts["header"],
			objs,
			parts["tail"],
			trailing
		)
		return {"ok": true, "bznfile": bzn}

	func write(path: String) -> Dictionary:
		var parts: PackedStringArray = header.duplicate()
		for obj in objects:
			parts.append_array((obj as GameObject).lines)
		parts.append_array(tail)
		var text: String = BzBzn.EOL.join(parts)
		if _trailing_newline:
			text += BzBzn.EOL
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return BzBzn._fail(
				"%s: cannot write (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		file.store_buffer(text.to_utf8_buffer())
		file.close()
		return {"ok": true}

	static func build(header_text: String, object_blocks: Array, tail_text: String) -> BznFile:
		return BznFile.new(
			BzBzn._strip_comments(header_text),
			object_blocks,
			BzBzn._strip_comments(tail_text)
		)

	func header_value(key: String, default_value: Variant = null) -> Variant:
		return BzBzn._get_value(header, key, default_value)

	func set_header(key: String, value: Variant) -> Dictionary:
		var idx: int = BzBzn._value_line_index(header, key)
		if idx < 0:
			return BzBzn._fail("no header key '%s'" % key)
		var line: String = header[idx]
		if line.contains("="):
			var base: String = key.trim_suffix(" [1]")
			header[idx] = "%s = %s" % [base, str(value)]
		else:
			header[idx] = str(value)
		_dirty = true
		return {"ok": true}

	func add_object(obj: GameObject) -> void:
		objects.append(obj)
		_dirty = true

	func validate() -> PackedStringArray:
		## R4 invariants (docs/02 §6 R4) as implemented in Python ``BznFile.validate``.
		var problems := PackedStringArray()
		var size_val: Variant = header_value("size [1]")
		if size_val != null:
			if str(size_val).to_int() != objects.size():
				problems.append(
					"size %s != object count %d" % [str(size_val), objects.size()]
				)
		else:
			problems.append("header missing 'size [1]'")

		var seqs: Array[int] = []
		for obj in objects:
			var sn: Variant = (obj as GameObject).seqno
			if sn != null:
				seqs.append(int(sn))
		if not seqs.is_empty():
			var expected: int = int(seqs.max()) + 1
			var seq_count: Variant = header_value("seq_count [1]")
			if seq_count != null and str(seq_count).to_int() != expected:
				problems.append(
					"seq_count %s != max(seqno)+1 = %d" % [str(seq_count), expected]
				)

		# obj_addr contiguous from 00000001 in file order (Python; not F3 0-based).
		var addrs: Array = []
		for obj in objects:
			addrs.append((obj as GameObject).obj_addr)
		if not addrs.is_empty():
			var want: Array = []
			for i in range(1, addrs.size() + 1):
				want.append(i)
			if addrs != want:
				problems.append("obj_addr not contiguous from 00000001: %s" % str(addrs))

		# Exactly one PrjID=="player", team == 1 (Python; not isUser).
		var players: Array = []
		for obj in objects:
			if (obj as GameObject).prjid == "player":
				players.append(obj)
		if players.size() != 1:
			problems.append(
				"expected exactly one player object, found %d" % players.size()
			)
		elif (players[0] as GameObject).team != 1:
			problems.append(
				"player team is %s, expected 1" % str((players[0] as GameObject).team)
			)

		var tail_text: String = BzBzn.EOL.join(tail)
		if not tail_text.contains("[AiMission]"):
			problems.append("missing [AiMission] trailing block")
		if not tail_text.contains("[AOIs]"):
			problems.append("missing [AOIs] trailing block")
		if not tail_text.contains("[AiPaths]"):
			problems.append("missing [AiPaths] trailing block")
		return problems
