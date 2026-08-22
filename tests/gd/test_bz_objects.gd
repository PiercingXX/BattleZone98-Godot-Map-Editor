extends RefCounted
## BzObjects: objects.json records, clone-from-source, apply_record_to_block.


const FIXTURE := "res://tests/gd/fixtures/bzn/untouched.bzn"

## Synthetic .bzn fixtures are caught by .gitignore's blanket *.bzn ban
## (AGENTS.md rule 3), so a fresh checkout — and every CI runner — has none.
## The cases that need one report SKIP instead of asserting against nothing.
const NEEDS_BZN_FIXTURE := "no local .bzn fixture (gitignored; see fixtures/bzn/README.txt)"


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_objects_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	_test_missing(t, tmp)
	_test_from_fixture(t)
	_test_template_and_apply(t, tmp)

	_rm_rf(tmp)


func _test_missing(t, tmp: String) -> void:
	var missing: Dictionary = BzObjects.load_variant_objects(tmp.path_join("nope.bzn"))
	t.ok(BzErrors.is_err(missing), "missing BZN is an error")
	t.eq(missing["error"].get("code"), "not_found")
	t.ok(str(missing["error"].get("path")).ends_with("nope.bzn"))


func _test_from_fixture(t) -> void:
	if not t.require_files([FIXTURE], NEEDS_BZN_FIXTURE):
		return
	var loaded: Dictionary = BzObjects.load_variant_objects(FIXTURE)
	t.eq(loaded.get("ok"), true, "load_variant_objects fixture")
	t.ok(loaded.has("records"))
	t.ok(loaded.has("blocks"))
	t.ok(loaded.has("bzn"))
	var records: Array = loaded["records"]
	t.eq(records.size(), 2, "two GameObject blocks")

	var player: Dictionary = records[0]
	t.eq(player.get("id"), "obj-0001")
	t.eq(player.get("origin"), "source")
	t.eq(player.get("prjid"), "player")
	t.eq(player.get("x"), 640.0)
	t.eq(player.get("y"), 10.0)
	t.eq(player.get("z"), 640.0)
	t.eq(player.get("yaw_deg"), 0.0)
	t.eq(player.get("team"), 1)
	t.eq(player.get("label"), "synthmap0_player")
	t.eq(player.get("up_convention"), "upright")
	t.eq(player.get("pinned_y"), false)
	t.eq(player.get("managed"), false)
	t.eq(player.get("required"), true, "isUser / prjid player is required")

	var geyser: Dictionary = records[1]
	t.eq(geyser.get("id"), "obj-0002")
	t.eq(geyser.get("prjid"), "eggeizr1")
	t.eq(geyser.get("x"), 100.25)
	t.eq(geyser.get("y"), 12.5)
	t.eq(geyser.get("z"), 200.75)
	t.eq(geyser.get("team"), 0)
	t.eq(geyser.get("label"), "synthmap1_geyser")
	t.eq(geyser.get("required"), false)
	t.ok((loaded["blocks"] as Dictionary).has("obj-0001"))
	t.ok((loaded["blocks"] as Dictionary).has("obj-0002"))

	var pref: Dictionary = BzObjects.objects_from_bzn(loaded["bzn"], "obj_s")
	t.eq(pref.get("ok"), true)
	t.eq(pref["records"][0].get("id"), "obj_s-0001", "id_prefix for variant _S")


func _test_template_and_apply(t, tmp: String) -> void:
	if not t.require_files([FIXTURE], NEEDS_BZN_FIXTURE):
		return
	t.eq(BzObjects.template_text_for("eggeizr1", tmp), "", "empty residue → no template")

	var src: String = tmp.path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	var dest: String = src.path_join("untouched.bzn")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), dest)

	var text: String = BzObjects.template_text_for("eggeizr1", src)
	t.ok(not text.is_empty(), "same-class block from residue")
	t.ok(text.begins_with("[GameObject]"), "verbatim block starts at [GameObject]")
	t.ok(text.contains("eggeizr1"))
	t.ok(text.contains("\r\n"), "CRLF render")

	t.eq(BzObjects.template_text_for("EGGEIZR1", src), text, "prjid match is case-insensitive")
	t.eq(BzObjects.template_text_for("no-such-class", src), "")

	var extra_only: String = BzObjects.template_text_for(
		"player", tmp.path_join("empty_src"), [dest]
	)
	t.ok(extra_only.contains("player"), "extra_bzns searched after residue")

	var loaded: Dictionary = BzObjects.load_variant_objects(dest)
	var geyser: Variant = loaded["blocks"]["obj-0002"]
	var rec := {
		"x": 1.5,
		"y": 2.5,
		"z": 3.5,
		"yaw_deg": 90.0,
		"team": 3,
		"label": "newlab",
	}
	var out: Variant = BzObjects.apply_record_to_block(geyser, rec)
	t.ok(out == geyser, "returns the same block")
	var pos: Array = geyser.position()
	t.near(float(pos[0]), 1.5)
	t.near(float(pos[1]), 2.5)
	t.near(float(pos[2]), 3.5)
	t.near(float(geyser.yaw_deg()), 90.0, 0.01)
	t.eq(int(geyser.team), 3)
	t.eq(str(geyser.label), "newlab")

	# Empty label does not rewrite identity (Python `if record.get("label")`).
	var seq_before: Variant = geyser.seqno
	BzObjects.apply_record_to_block(geyser, {
		"x": 9.0, "y": 8.0, "z": 7.0, "yaw_deg": 0.0, "team": 3, "label": "",
	})
	t.eq(geyser.seqno, seq_before)
	t.eq(str(geyser.label), "newlab")


func _rm_rf(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var child: String = path.path_join(fn)
		if da.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		fn = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
