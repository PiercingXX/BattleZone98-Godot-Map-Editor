extends RefCounted
## BzTrn: parse, write→parse, CRLF byte-identical round-trip, surgical mutation.


func run(t) -> void:
	var work := _work_dir()
	var src_text := _sample_trn()
	var src_path := work.path_join("sample.trn")
	_write(src_path, src_text)

	# --- parse (F8: Width/Depth are metres = 1280 × zones; 2560×3840 = 2×3) ---
	var cfg: BzTrn.TerrainConfig = BzTrn.read_trn(src_path)
	t.ok(cfg != null, "read_trn")
	var names: Array = []
	for sec in cfg.sections:
		names.append(sec.name)
	t.eq(names, [
		"Size", "NormalView", "Atlases", "World", "Sky",
		"TextureType0", "TextureType1", "Color",
	], "section order + TextureType trailing text")
	t.eq(cfg.get("Size", "MinX"), "100", "first duplicate MinX wins")
	t.eq(cfg.get("Size", "Width"), "2560")
	t.eq(cfg.get("Size", "Depth"), "3840")
	t.eq(cfg.get("Size", "Height"), "20")
	t.eq(cfg.get("Sky", "SkyHeight"), "210", "SkyHeight is not [Size] Height")
	t.eq(cfg.get("Atlases", "MaterialName"), "syn_detail_atlas")
	t.eq(cfg.get("TextureType0", "FlatColor"), "201")
	t.eq(cfg.get("TextureType1", "FlatColor"), "10")
	t.eq(cfg.get("Size", "width", "MISSING"), "MISSING", "keys are case-sensitive (trn.py)")
	t.eq(cfg.section("Nope"), null)
	t.eq((cfg.section("Nope", false) as Array).size(), 0)
	t.eq(cfg.section("Size").keys(), ["MinX", "MinX", "MinZ", "Width", "Depth", "Height"])

	# --- byte-identical round-trip (CRLF, no edits) ---
	var untouched := work.path_join("untouched.trn")
	BzTrn.write_trn(untouched, cfg)
	_eq_bytes(t, untouched, src_text, "untouched CRLF round-trip")

	# fixture file, if present (same bytes as _sample_trn)
	var fixture := ProjectSettings.globalize_path("res://tests/gd/fixtures/trn/sample.txt")
	if FileAccess.file_exists(fixture):
		var from_fix: BzTrn.TerrainConfig = BzTrn.read_trn(fixture)
		var out_fix := work.path_join("from_fixture.trn")
		BzTrn.write_trn(out_fix, from_fix)
		_eq_bytes(t, out_fix, FileAccess.get_file_as_bytes(fixture).get_string_from_utf8(), "fixture round-trip")

	# --- surgical mutation: only the Width line is rewritten ---
	cfg.set("Size", "Width", "5120")
	t.eq(cfg.get("Size", "Width"), "5120")
	var mutated := work.path_join("mutated.trn")
	BzTrn.write_trn(mutated, cfg)
	var got_lines := _split_crlf(FileAccess.get_file_as_bytes(mutated).get_string_from_utf8())
	var src_lines := _split_crlf(src_text)
	t.eq(got_lines.size(), src_lines.size(), "mutation keeps line count")
	var changed := 0
	for i in src_lines.size():
		if got_lines[i] == src_lines[i]:
			continue
		changed += 1
		t.eq(got_lines[i], "Width = 5120", "rewritten line is normalized key = value")
		t.ok(src_lines[i].begins_with("Width"), "only Width changed")
	t.eq(changed, 1, "exactly one line rewritten")

	# write → parse after mutation
	var reparsed: BzTrn.TerrainConfig = BzTrn.read_trn(mutated)
	t.eq(reparsed.get("Size", "Width"), "5120")
	t.eq(reparsed.get("Size", "MinX"), "100")
	t.eq(reparsed.get("Atlases", "MaterialName"), "syn_detail_atlas")

	# --- BOM is stripped on read ---
	var bom_path := work.path_join("bom.trn")
	var bom := PackedByteArray()
	bom.append(0xEF)
	bom.append(0xBB)
	bom.append(0xBF)
	bom.append_array(src_text.to_utf8_buffer())
	var bf := FileAccess.open(bom_path, FileAccess.WRITE)
	bf.store_buffer(bom)
	var cfg_bom: BzTrn.TerrainConfig = BzTrn.read_trn(bom_path)
	t.eq(cfg_bom.get("Size", "Width"), "2560", "utf-8-sig BOM")
	t.eq(cfg_bom.sections[0].name, "Size")

	# --- pending key on a populated section ---
	var extra: BzTrn.TerrainConfig = BzTrn.read_trn(src_path)
	extra.set("Size", "NewKey", "yes")
	t.eq(extra.get("Size", "NewKey"), "yes")
	var extra_path := work.path_join("extra.trn")
	BzTrn.write_trn(extra_path, extra)
	var extra_cfg: BzTrn.TerrainConfig = BzTrn.read_trn(extra_path)
	t.eq(extra_cfg.get("Size", "NewKey"), "yes")

	# --- empty section: pending keys append at EOF (trn.py) ---
	var empty_src := "[Empty]\r\n[Size]\r\nWidth=1\r\n"
	var empty_path := work.path_join("empty_sec.trn")
	_write(empty_path, empty_src)
	var empty_cfg: BzTrn.TerrainConfig = BzTrn.read_trn(empty_path)
	empty_cfg.set("Empty", "Foo", "bar")
	var empty_out := work.path_join("empty_sec_out.trn")
	BzTrn.write_trn(empty_out, empty_cfg)
	_eq_bytes(t, empty_out, "[Empty]\r\n[Size]\r\nWidth=1\r\nFoo = bar\r\n", "empty-section pending at EOF")

	# --- write_complete_trn template-and-mutate ---
	var tmpl := work.path_join("template.trn")
	_write(tmpl, _template_trn())
	var complete := work.path_join("complete.trn")
	var ret := BzTrn.write_complete_trn(complete, 2560, 3840, tmpl)
	t.eq(ret, complete)
	_eq_bytes(
		t,
		complete,
		"[Size]\r\nMinX = 0\r\nMinZ = 0\r\nWidth = 2560\r\nDepth = 3840\r\nHeight = 0.000000\r\n\r\n[Atlases]\r\nMaterialName = syn_detail_atlas\r\n\r\n[TextureType0] // Rock\r\nFlatColor= 1\r\n",
		"write_complete_trn Size rewrite"
	)
	var done: BzTrn.TerrainConfig = BzTrn.read_trn(complete)
	t.eq(done.get("Size", "Width"), "2560")
	t.eq(done.get("Size", "Depth"), "3840")
	t.eq(done.get("Size", "MinX"), "0")
	t.eq(done.get("Size", "Height"), "0.000000")
	t.eq(done.get("Atlases", "MaterialName"), "syn_detail_atlas")

	# --- duplicate sections: first_only ---
	var dup_path := work.path_join("dupsec.trn")
	_write(dup_path, "[A]\r\nK=1\r\n[A]\r\nK=2\r\n")
	var dup: BzTrn.TerrainConfig = BzTrn.read_trn(dup_path)
	t.eq(dup.get("A", "K"), "1", "first section wins")
	var all_a: Array = dup.section("A", false)
	t.eq(all_a.size(), 2)
	t.eq(all_a[0].get("K"), "1")
	t.eq(all_a[1].get("K"), "2")

	# --- LF source is re-emitted as CRLF (not byte-identical; matches trn.py) ---
	var lf_path := work.path_join("lf.trn")
	_write(lf_path, "[Size]\nWidth=1\n")
	var lf_cfg: BzTrn.TerrainConfig = BzTrn.read_trn(lf_path)
	var lf_out := work.path_join("lf_out.trn")
	BzTrn.write_trn(lf_out, lf_cfg)
	_eq_bytes(t, lf_out, "[Size]\r\nWidth=1\r\n", "LF source rewritten as CRLF")

	# first-of-duplicate set
	var dmin := work.path_join("dupmin.trn")
	_write(dmin, "[Size]\r\nMinX=100\r\nMinX=999\r\nWidth=1\r\n")
	var dcfg: BzTrn.TerrainConfig = BzTrn.read_trn(dmin)
	dcfg.set("Size", "MinX", "0")
	var dout := work.path_join("dupmin_out.trn")
	BzTrn.write_trn(dout, dcfg)
	_eq_bytes(t, dout, "[Size]\r\nMinX = 0\r\nMinX=999\r\nWidth=1\r\n", "set first MinX only")


func _sample_trn() -> String:
	# Synthetic — not from any game map. Generated to match tests/gd/fixtures/trn/sample.txt.
	return (
		"; synthetic terrain config — not from any game map\r\n"
		+ "# comment hash\r\n"
		+ "\r\n"
		+ "[Size]\r\n"
		+ "MinX=100\r\n"
		+ "MinX=999\r\n"
		+ "MinZ = 200\r\n"
		+ "Width=2560\r\n"
		+ "Depth = 3840\r\n"
		+ "Height=20\r\n"
		+ "\r\n"
		+ "[NormalView]\r\n"
		+ "FogStart= 80\r\n"
		+ "\r\n"
		+ "[Atlases]\r\n"
		+ "MaterialName\t= syn_detail_atlas\r\n"
		+ "\r\n"
		+ "[World]\r\n"
		+ "MusicTrack=20\r\n"
		+ "\r\n"
		+ "[Sky]\r\n"
		+ "SkyHeight = 210\r\n"
		+ "SkyTexture=synthetic.map \r\n"
		+ "\r\n"
		+ "[TextureType0] // Packed Dirt\r\n"
		+ "FlatColor= 201\r\n"
		+ "SolidA0        = syn00sa0.map\r\n"
		+ "\r\n"
		+ "[TextureType1] Lava Pool\r\n"
		+ "FlatColor= 10\r\n"
		+ "\r\n"
		+ "this is opaque leftover\r\n"
		+ "\r\n"
		+ "[Color]\r\n"
		+ "Palette=synthetic.act\r\n"
	)


func _template_trn() -> String:
	return (
		"[Size]\r\n"
		+ "MinX=5\r\n"
		+ "MinZ=5\r\n"
		+ "Width=1280\r\n"
		+ "Depth=1280\r\n"
		+ "Height=20\r\n"
		+ "\r\n"
		+ "[Atlases]\r\n"
		+ "MaterialName = syn_detail_atlas\r\n"
		+ "\r\n"
		+ "[TextureType0] // Rock\r\n"
		+ "FlatColor= 1\r\n"
	)


func _work_dir() -> String:
	var d := OS.get_cache_dir().path_join("bz_trn_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(text.to_utf8_buffer())


func _eq_bytes(t, path: String, want: String, msg: String) -> void:
	var got := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	t.eq(got, want, msg)


func _split_crlf(text: String) -> PackedStringArray:
	var s := text
	if s.ends_with("\r\n"):
		s = s.substr(0, s.length() - 2)
	return s.split("\r\n")
