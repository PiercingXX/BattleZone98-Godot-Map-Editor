extends RefCounted
## BzTemplates: strip/load reference blocks, bzn_path override, available_prjids.


func run(t) -> void:
	var work := _work_dir()
	var ref := work.path_join("ref")
	DirAccess.make_dir_recursive_absolute(ref)
	_write(ref.path_join("bzn-object-template.txt"), _object_template())
	_write(ref.path_join("bzn-header-tail-template.txt"), _header_tail_template())

	var loader := BzTemplates.TemplateLoader.new(ref, "")

	# --- header / tail from reference (comments stripped; both return the whole file) ---
	var stripped_ht := "version [1] =\r\n2016\r\n[AiMission]\r\n[AOIs]\r\nsize [1] =\r\n0"
	t.eq(loader.header(), stripped_ht, "header() strips # lines")
	t.eq(loader.tail(), stripped_ht, "tail() is the same full template (templates.py)")
	t.ok(not loader.header().contains("#"), "no annotation lines")

	# --- object from reference ---
	var obj := loader.object("synobj01")
	var obj_want := "[GameObject]\r\nPrjID [1] =\r\nsynobj01\r\nseqno [1] =\r\n1\r\nlabel = hello"
	t.eq(obj, obj_want, "object() from reference")
	t.ok(not obj.contains("#"), "annotation stripped")
	t.eq(loader.object("missing"), "", "unknown PrjID → empty (Python KeyError)")

	var prjids: Array = loader.available_prjids()
	t.eq(prjids.size(), 1)
	t.eq(prjids[0], "synobj01")

	# --- stock bzn_path takes precedence ---
	var bzn_path := work.path_join("stock.bzn")
	_write(
		bzn_path,
		"version [1] =\r\n2016\r\n[GameObject]\r\nPrjID [1] =\r\nsynobj02\r\nseqno [1] =\r\n2\r\n[AiMission]\r\n[AOIs]\r\nsize [1] =\r\n0\r\n"
	)
	var from_bzn := BzTemplates.TemplateLoader.new(ref, bzn_path)
	t.eq(from_bzn.header(), "version [1] =\r\n2016", "header from bzn")
	t.eq(from_bzn.tail(), "[AiMission]\r\n[AOIs]\r\nsize [1] =\r\n0", "tail from bzn")
	t.eq(
		from_bzn.object("synobj02"),
		"[GameObject]\r\nPrjID [1] =\r\nsynobj02\r\nseqno [1] =\r\n2",
		"object from bzn"
	)
	t.eq(from_bzn.object("synobj01"), obj_want, "fallback to reference")
	var both: Array = from_bzn.available_prjids()
	both.sort()
	t.eq(both, ["synobj01", "synobj02"])

	# --- module-level template() against this reference via loader ---
	t.eq(BzTemplates.template("synobj01", bzn_path), obj_want)

	# --- empty bzn header/tail falls back to reference ---
	var bare_bzn := work.path_join("bare.bzn")
	_write(bare_bzn, "[GameObject]\r\nPrjID [1] =\r\nfoo\r\n")
	var bare := BzTemplates.TemplateLoader.new(ref, bare_bzn)
	t.eq(bare.header(), stripped_ht, "empty header falls back")
	t.eq(bare.tail(), stripped_ht, "empty tail falls back")
	t.eq(bare.object("foo"), "[GameObject]\r\nPrjID [1] =\r\nfoo")

	# --- DEFAULT_REFERENCE_DIR + repo template (eggeizr1) if present ---
	t.ok(BzTemplates.DEFAULT_REFERENCE_DIR.contains("backend/reference"))
	var repo_obj := ProjectSettings.globalize_path(
		"res://project/backend/reference/bzn-object-template.txt"
	)
	if FileAccess.file_exists(repo_obj) or FileAccess.file_exists(BzTemplates.DEFAULT_REFERENCE_DIR.path_join("bzn-object-template.txt")):
		var repo := BzTemplates.TemplateLoader.new()
		var ids: Array = repo.available_prjids()
		t.ok(ids.has("eggeizr1"), "repo reference object PrjID")
		var block := repo.object("eggeizr1")
		t.ok(block.begins_with("[GameObject]"), "repo object block")
		t.ok(block.contains("eggeizr1"))
		t.ok(not block.contains("#"))
		var via_fn := BzTemplates.template("eggeizr1")
		t.eq(via_fn, block, "template() matches TemplateLoader.object")

	# fixture files, if present
	var fix_ref := ProjectSettings.globalize_path("res://tests/gd/fixtures/templates")
	if FileAccess.file_exists(fix_ref.path_join("bzn-object-template.txt")):
		var fix := BzTemplates.TemplateLoader.new(fix_ref, "")
		t.eq(fix.object("synobj01"), obj_want, "fixture reference object")


func _object_template() -> String:
	return "# annotation\n[GameObject]\nPrjID [1] =\nsynobj01\nseqno [1] =\n1\nlabel = hello\n"


func _header_tail_template() -> String:
	return "# hdr\nversion [1] =\n2016\n### TAIL\n[AiMission]\n[AOIs]\nsize [1] =\n0\n"


func _work_dir() -> String:
	var d := OS.get_cache_dir().path_join("bz_tpl_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(text.to_utf8_buffer())
