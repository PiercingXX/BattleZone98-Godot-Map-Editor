extends RefCounted
## BzBzn: parse, byte-identical CRLF round-trip, set_position, clone, validate.


const FIX: String = "res://tests/gd/fixtures/bzn"
const OUT_RT: String = "user://test_bz_bzn_roundtrip.bzn"
const OUT_MUT: String = "user://test_bz_bzn_mutated.bzn"
const OUT_WP: String = "user://test_bz_bzn_writeparse.bzn"

## Synthetic .bzn fixtures are caught by .gitignore's blanket *.bzn ban
## (AGENTS.md rule 3), so a fresh checkout — and every CI runner — has none.
## The cases that need one report SKIP instead of asserting against nothing.
const NEEDS_BZN_FIXTURE := "no local .bzn fixture (gitignored; see fixtures/bzn/README.txt)"


func run(t) -> void:
	_test_fmt_float(t)
	_test_parse(t)
	_test_byte_identical_roundtrip(t)
	_test_write_parse_roundtrip(t)
	_test_mutation_set_position(t)
	_test_clone(t)
	_test_validate(t)
	_test_header_and_identity(t)
	_test_from_template_strips_comments(t)
	_test_set_yaw_signed_zero(t)


func _read_bytes(path: String) -> PackedByteArray:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return PackedByteArray()
	return fa.get_buffer(fa.get_length())


func _open(t, path: String):
	var result: Dictionary = BzBzn.BznFile.read(path)
	t.ok(bool(result.get("ok", false)), "read %s" % path)
	return result.get("bznfile")


func _eq_bytes(t, got: PackedByteArray, want: PackedByteArray, msg: String) -> void:
	if got == want:
		return
	var n: int = mini(got.size(), want.size())
	var i: int = 0
	while i < n and got[i] == want[i]:
		i += 1
	t.fail(
		"%s: differ at byte %d (got %d want %d)"
		% [msg, i, got.size(), want.size()]
	)


func _test_fmt_float(t) -> void:
	## Vectors from Python ``bzmap.formats.bzn._fmt_float``.
	var cases: Array = [
		[0.0, "0"],
		[1.0, "1"],
		[-1.0, "-1"],
		[1.5, "1.5"],
		[10.0, "10"],
		[55.6, "55.6"],
		[100.5, "100.5"],
		[625.345, "625.345"],
		[782.817, "782.817"],
		[640.0, "640"],
		[0.5, "0.5"],
		[0.0001, "0.0001"],
		[0.00001, "1e-005"],
		[0.0000123456, "1.23456e-005"],
		[1e-7, "1e-007"],
		[1e30, "1e+030"],
		[1e-30, "1e-030"],
		[1234567.0, "1.23457e+006"],
		[123456.0, "123456"],
		[999999.0, "999999"],
		[0.123456, "0.123456"],
		[0.1234567, "0.123457"],
		[1.234567, "1.23457"],
		[12.34567, "12.3457"],
		[cos(0.5), "0.877583"],
		[sin(0.5), "0.479426"],
		[-sin(0.5), "-0.479426"],
	]
	for c in cases:
		t.eq(BzBzn._fmt_float(float(c[0])), str(c[1]), "fmt_float %s" % str(c[0]))
	t.eq(BzBzn._fmt_float(BzBzn._neg_zero()), "-0", "fmt_float signed zero")


func _test_parse(t) -> void:
	if not t.require_files(["%s/untouched.bzn" % FIX], NEEDS_BZN_FIXTURE):
		return
	var bzn = _open(t, "%s/untouched.bzn" % FIX)
	if bzn == null:
		return
	t.eq(bzn.objects.size(), 2, "two GameObjects")
	t.eq(str(bzn.header_value("version [1]")), "2016")
	t.eq(str(bzn.header_value("binarySave [1]")), "false")
	t.eq(str(bzn.header_value("msn_filename")), "synthmap.bzn")
	t.eq(str(bzn.header_value("TerrainName")), "synthmap")
	t.eq(str(bzn.header_value("size [1]")), "2")
	t.eq(str(bzn.header_value("seq_count [1]")), "2")
	var player = bzn.objects[0]
	var geyser = bzn.objects[1]
	t.eq(player.prjid, "player")
	t.eq(player.seqno, 0)
	t.eq(player.team, 1)
	t.eq(player.obj_addr, 1)
	t.eq(player.label, "synthmap0_player")
	t.ok(player.is_user(), "player isUser")
	t.eq(geyser.prjid, "eggeizr1")
	t.eq(geyser.seqno, 1)
	t.eq(geyser.obj_addr, 2)
	t.ok(not geyser.is_user(), "geyser not user")
	var ppos: Variant = player.position()
	t.ok(ppos != null, "player position")
	if ppos != null:
		t.near(float(ppos[0]), 640.0, 0.0001, "player x")
		t.near(float(ppos[1]), 10.0, 0.0001, "player y")
		t.near(float(ppos[2]), 640.0, 0.0001, "player z")
	var gpos: Variant = geyser.position()
	t.ok(gpos != null, "geyser position")
	if gpos != null:
		t.near(float(gpos[0]), 100.25, 0.0001, "geyser x")
		t.near(float(gpos[1]), 12.5, 0.0001, "geyser y")
		t.near(float(gpos[2]), 200.75, 0.0001, "geyser z")
	t.near(player.yaw_deg(), 0.0, 0.001, "identity yaw")
	t.ok(bzn.validate().is_empty(), "untouched validates")
	# Vestigial names must survive verbatim (docs/02 §2).
	t.eq(str(bzn.header_value("msn_filename")), "synthmap.bzn")
	var tail_text: String = BzBzn.EOL.join(bzn.tail)
	t.ok(tail_text.contains("[AiMission]"), "tail AiMission")
	t.ok(tail_text.contains("[AOIs]"), "tail AOIs")
	t.ok(tail_text.contains("[AiPaths]"), "tail AiPaths")


func _test_byte_identical_roundtrip(t) -> void:
	if not t.require_files(["%s/untouched.bzn" % FIX], NEEDS_BZN_FIXTURE):
		return
	var src := "%s/untouched.bzn" % FIX
	var want: PackedByteArray = _read_bytes(src)
	t.ok(want.size() > 0, "fixture readable")
	var saw_cr: bool = false
	for b in want:
		if int(b) == 0x0D:
			saw_cr = true
			break
	t.ok(saw_cr, "fixture is CRLF")
	var bzn = _open(t, src)
	if bzn == null:
		return
	var wr: Dictionary = bzn.write(OUT_RT)
	t.ok(bool(wr.get("ok", false)), "write roundtrip")
	var got: PackedByteArray = _read_bytes(OUT_RT)
	_eq_bytes(t, got, want, "untouched open→save")
	# Module wrappers share the same path.
	var wr2: Dictionary = BzBzn.write_bzn(OUT_RT, bzn)
	t.ok(bool(wr2.get("ok", false)), "write_bzn wrapper")
	_eq_bytes(t, _read_bytes(OUT_RT), want, "write_bzn open→save")


func _test_write_parse_roundtrip(t) -> void:
	if not t.require_files(["%s/untouched.bzn" % FIX], NEEDS_BZN_FIXTURE):
		return
	var bzn = _open(t, "%s/untouched.bzn" % FIX)
	if bzn == null:
		return
	var wr: Dictionary = bzn.write(OUT_WP)
	t.ok(bool(wr.get("ok", false)), "write for reparse")
	var again = _open(t, OUT_WP)
	if again == null:
		return
	t.eq(again.objects.size(), bzn.objects.size())
	t.eq(again.objects[0].prjid, "player")
	t.eq(again.objects[1].prjid, "eggeizr1")
	var a: Variant = again.objects[1].position()
	var b: Variant = bzn.objects[1].position()
	t.ok(a != null and b != null)
	if a != null and b != null:
		t.near(float(a[0]), float(b[0]), 0.0001)
		t.near(float(a[1]), float(b[1]), 0.0001)
		t.near(float(a[2]), float(b[2]), 0.0001)
	t.eq(str(again.header_value("msn_filename")), str(bzn.header_value("msn_filename")))


func _test_mutation_set_position(t) -> void:
	if not t.require_files(["%s/untouched.bzn" % FIX, "%s/mutated_pos.bzn" % FIX], NEEDS_BZN_FIXTURE):
		return
	var src := "%s/untouched.bzn" % FIX
	var gold := "%s/mutated_pos.bzn" % FIX
	var bzn = _open(t, src)
	if bzn == null:
		return
	var geyser = bzn.objects[1]
	geyser.set_position(333.125, 44.5, 555.875)
	var wr: Dictionary = bzn.write(OUT_MUT)
	t.ok(bool(wr.get("ok", false)), "write mutated")
	_eq_bytes(t, _read_bytes(OUT_MUT), _read_bytes(gold), "set_position gold")

	var orig_lines: PackedStringArray = BzBzn._split_lines(
		_read_bytes(src).get_string_from_utf8()
	)
	var mut_lines: PackedStringArray = BzBzn._split_lines(
		_read_bytes(OUT_MUT).get_string_from_utf8()
	)
	t.eq(orig_lines.size(), mut_lines.size(), "line count unchanged")
	var changed: int = 0
	for i in orig_lines.size():
		if orig_lines[i] != mut_lines[i]:
			changed += 1
			t.ok(
				orig_lines[i] in ["100.25", "12.5", "200.75"],
				"only pos values change (line %d was %s)" % [i, orig_lines[i]]
			)
	t.eq(changed, 9, "three sites × xyz")

	# All three stored copies agree (F3 §5.3 / F8 §1 posit_*).
	var idxs: Array = BzBzn._pos_value_indices(geyser.lines)
	t.eq(idxs.size(), 2, "two pos blocks")
	for triple in idxs:
		t.eq(geyser.lines[int(triple[0])], "333.125")
		t.eq(geyser.lines[int(triple[1])], "44.5")
		t.eq(geyser.lines[int(triple[2])], "555.875")
	t.eq(str(BzBzn._get_value(geyser.lines, "posit_x")), "333.125")
	t.eq(str(BzBzn._get_value(geyser.lines, "posit_y")), "44.5")
	t.eq(str(BzBzn._get_value(geyser.lines, "posit_z")), "555.875")
	# Untouched physics residue (1e+030) must still be there.
	t.eq(str(BzBzn._get_value(bzn.objects[0].lines, "mass_inv [1]")), "1e+030")


func _test_clone(t) -> void:
	var tmpl: String = FileAccess.get_file_as_string("%s/clone_template.txt" % FIX)
	t.ok(not tmpl.is_empty(), "clone template")
	var clone = BzBzn.GameObject.from_template(tmpl)
	t.eq(clone.prjid, "sobject1")
	clone.set_position(11.5, 22.25, 33.75)
	clone.set_yaw(0.5)
	clone.set_identity(3, 4, "cloned_obj")
	var tr: Dictionary = clone.set_team(2)
	t.ok(bool(tr.get("ok", false)), "set_team")
	var gold: PackedByteArray = _read_bytes("%s/cloned_object.txt" % FIX)
	_eq_bytes(t, clone.render().to_utf8_buffer(), gold, "clone render")
	t.eq(clone.seqno, 3)
	t.eq(clone.obj_addr, 4)
	t.eq(clone.label, "cloned_obj")
	t.eq(clone.team, 2)
	var pos: Variant = clone.position()
	t.ok(pos != null)
	if pos != null:
		t.near(float(pos[0]), 11.5, 0.0001)
		t.near(float(pos[1]), 22.25, 0.0001)
		t.near(float(pos[2]), 33.75, 0.0001)
	t.near(clone.yaw_deg(), rad_to_deg(0.5), 0.001, "yaw recovered from front")
	# Lowercase hex (Python), not F3 uppercase.
	t.eq(str(BzBzn._get_value(clone.lines, "obj_addr")), "00000004")


func _test_validate(t) -> void:
	if not t.require_files(["%s/untouched.bzn" % FIX], NEEDS_BZN_FIXTURE):
		return
	var ok = _open(t, "%s/untouched.bzn" % FIX)
	if ok == null:
		return
	t.eq(ok.validate(), PackedStringArray(), "valid file")

	# size mismatch
	var b1 = _open(t, "%s/untouched.bzn" % FIX)
	b1.set_header("size [1]", "99")
	var p1: PackedStringArray = b1.validate()
	t.ok(_has(p1, "size 99 != object count 2"), "size mismatch: %s" % str(p1))

	# missing size
	var b2 := BzBzn.BznFile.build(
		"version [1] =\n2016\n",
		ok.objects,
		"[AiMission]\n[AOIs]\n[AiPaths]\n"
	)
	var p2: PackedStringArray = b2.validate()
	t.ok(_has(p2, "header missing 'size [1]'"), "missing size: %s" % str(p2))

	# seq_count != max(seqno)+1  (Python; not F3 "equals object count")
	var b3 = _open(t, "%s/untouched.bzn" % FIX)
	b3.set_header("seq_count [1]", "99")
	var p3: PackedStringArray = b3.validate()
	t.ok(_has(p3, "seq_count 99 != max(seqno)+1 = 2"), "seq_count: %s" % str(p3))

	# obj_addr not contiguous from 00000001
	var b4 = _open(t, "%s/untouched.bzn" % FIX)
	b4.objects[1].set_identity(1, 9, "synthmap1_geyser")
	var p4: PackedStringArray = b4.validate()
	t.ok(_has_prefix(p4, "obj_addr not contiguous from 00000001:"), "addr: %s" % str(p4))

	# no player
	var b5 = _open(t, "%s/untouched.bzn" % FIX)
	var pidx: int = BzBzn._value_line_index(b5.objects[0].lines, "PrjID [1]")
	b5.objects[0].lines[pidx] = "notplayer"
	var p5: PackedStringArray = b5.validate()
	t.ok(_has(p5, "expected exactly one player object, found 0"), "no player: %s" % str(p5))

	# two players
	var b6 = _open(t, "%s/untouched.bzn" % FIX)
	var gidx: int = BzBzn._value_line_index(b6.objects[1].lines, "PrjID [1]")
	b6.objects[1].lines[gidx] = "player"
	var p6: PackedStringArray = b6.validate()
	t.ok(_has(p6, "expected exactly one player object, found 2"), "two players: %s" % str(p6))

	# player team != 1
	var b7 = _open(t, "%s/untouched.bzn" % FIX)
	b7.objects[0].set_team(0)
	var p7: PackedStringArray = b7.validate()
	t.ok(_has(p7, "player team is 0, expected 1"), "team: %s" % str(p7))

	# missing trailing sections
	var b8 = _open(t, "%s/untouched.bzn" % FIX)
	b8.tail = PackedStringArray()
	var p8: PackedStringArray = b8.validate()
	t.ok(_has(p8, "missing [AiMission] trailing block"), "no mission: %s" % str(p8))
	t.ok(_has(p8, "missing [AOIs] trailing block"), "no AOIs")
	t.ok(_has(p8, "missing [AiPaths] trailing block"), "no AiPaths")

	# Python does not check AOIs size == 0 (disagrees with the module docstring).
	var b9 = _open(t, "%s/untouched.bzn" % FIX)
	var sidx: int = BzBzn._value_line_index(b9.tail, "size [1]")
	t.ok(sidx >= 0, "AOIs size present")
	if sidx >= 0:
		b9.tail[sidx] = "7"
	t.ok(b9.validate().is_empty(), "non-zero AOIs size is not an R4 violation")


func _test_header_and_identity(t) -> void:
	if not t.require_files(["%s/untouched.bzn" % FIX], NEEDS_BZN_FIXTURE):
		return
	var bzn = _open(t, "%s/untouched.bzn" % FIX)
	if bzn == null:
		return
	var hs: Dictionary = bzn.set_header("msn_filename", "other.bzn")
	t.ok(bool(hs.get("ok", false)), "set_header")
	t.eq(str(bzn.header_value("msn_filename")), "other.bzn")
	var miss: Dictionary = bzn.set_header("no_such_key", "x")
	t.ok(not bool(miss.get("ok", true)), "missing header key")
	var player = bzn.objects[0]
	player.set_identity(7, 8, "new_label")
	t.eq(player.seqno, 7)
	t.eq(player.obj_addr, 8)
	t.eq(player.label, "new_label")
	t.eq(str(BzBzn._get_value(player.lines, "seqNo [1]")), "7")
	var ur: Dictionary = player.set_is_user(false)
	t.ok(bool(ur.get("ok", false)))
	t.ok(not player.is_user())
	# add_object marks dirty and grows the list
	var n: int = bzn.objects.size()
	var extra = BzBzn.GameObject.from_template(
		FileAccess.get_file_as_string("%s/clone_template.txt" % FIX)
	)
	bzn.add_object(extra)
	t.eq(bzn.objects.size(), n + 1)
	t.ok(bzn._dirty, "add_object dirty")
	# KeyError-equivalent on a block with no team field.
	var bare = BzBzn.GameObject.new(PackedStringArray(["[GameObject]"]))
	t.ok(not bool(bare.set_team(1).get("ok", true)), "no team field")
	t.ok(not bool(bare.set_is_user(true).get("ok", true)), "no isUser field")


func _test_from_template_strips_comments(t) -> void:
	var tmpl: String = FileAccess.get_file_as_string("%s/clone_template.txt" % FIX)
	var obj = BzBzn.GameObject.from_template(tmpl)
	for line in obj.lines:
		t.ok(
			not line.strip_edges(true, false).begins_with("#"),
			"comment stripped: %s" % line
		)
	t.eq(obj.lines[0], "[GameObject]")


func _test_set_yaw_signed_zero(t) -> void:
	var tmpl: String = FileAccess.get_file_as_string("%s/clone_template.txt" % FIX)
	var obj = BzBzn.GameObject.from_template(tmpl)
	obj.set_yaw(0.0)
	t.eq(str(BzBzn._get_value(obj.lines, "right_x [1]")), "1")
	t.eq(str(BzBzn._get_value(obj.lines, "right_y [1]")), "0")
	t.eq(str(BzBzn._get_value(obj.lines, "right_z [1]")), "-0")
	t.eq(str(BzBzn._get_value(obj.lines, "up_y [1]")), "1")
	t.eq(str(BzBzn._get_value(obj.lines, "front_x [1]")), "0")
	t.eq(str(BzBzn._get_value(obj.lines, "front_z [1]")), "1")


func _has(arr: PackedStringArray, want: String) -> bool:
	for s in arr:
		if s == want:
			return true
	return false


func _has_prefix(arr: PackedStringArray, prefix: String) -> bool:
	for s in arr:
		if str(s).begins_with(prefix):
			return true
	return false
