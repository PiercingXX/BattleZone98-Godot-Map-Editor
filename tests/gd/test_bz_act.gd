extends RefCounted
## BzAct: shipped template, with_all_fog paints every entry.


func run(t) -> void:
	_test_template_path(t)
	_test_with_all_fog(t)
	_test_read_write(t)


func _test_template_path(t) -> void:
	var path: String = BzAct.template_path()
	t.ok(not path.is_empty(), "template_path resolves")
	t.ok(FileAccess.file_exists(path), "shipped template.act exists at %s" % path)
	var read: Dictionary = BzAct.read(path)
	t.ok(bool(read.get("ok")), "template is a valid palette")
	t.eq((read.get("palette", PackedByteArray()) as PackedByteArray).size(), BzAct.SIZE)


func _test_with_all_fog(t) -> void:
	var read: Dictionary = BzAct.read(BzAct.template_path())
	t.ok(bool(read.get("ok")), "read template for with_all_fog")
	if not bool(read.get("ok")):
		return
	var base: PackedByteArray = read["palette"]
	var color := Color8(10, 20, 30)
	t.ok(not BzAct.fog_color(base).is_equal_approx(color), "template is not already that colour")
	var painted: PackedByteArray = BzAct.with_all_fog(base, color)
	t.eq(painted.size(), BzAct.SIZE, "size unchanged")
	var bad := 0
	for i in BzAct.ENTRIES:
		var at: int = i * 3
		if int(painted[at]) != 10 or int(painted[at + 1]) != 20 or int(painted[at + 2]) != 30:
			bad += 1
	t.eq(bad, 0, "all 256 entries are the requested colour")
	t.ok(BzAct.fog_color(painted).is_equal_approx(color), "fog_color still reads index 0")
	var short := PackedByteArray([1, 2, 3])
	t.eq(BzAct.with_all_fog(short, color), short, "wrong-size base is returned untouched")


func _test_read_write(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_act_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var base := PackedByteArray()
	base.resize(BzAct.SIZE)
	for i in BzAct.SIZE:
		base[i] = i % 256
	var path: String = tmp.path_join("round.act")
	t.ok(bool(BzAct.write(path, base).get("ok")), "write a 768-byte palette")
	var read: Dictionary = BzAct.read(path)
	t.ok(bool(read.get("ok")), "read it back")
	t.ok((read["palette"] as PackedByteArray) == base, "byte-identical")
	var short_p: String = tmp.path_join("short.act")
	var sf := FileAccess.open(short_p, FileAccess.WRITE)
	if sf:
		sf.store_buffer(PackedByteArray([1, 2, 3]))
		sf.close()
	t.eq(BzAct.read(short_p).get("ok"), false, "a non-768-byte .act is refused")
	_rm_rf(tmp)


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
