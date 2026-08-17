extends RefCounted
## BzVxt — verbatim observer-list writer.
## Expected bytes match bzmap.formats.vxt (PYTHONPATH=backend). `*.vxt` is
## gitignored, so goldens live in this file rather than on disk.


func run(t) -> void:
	_constants(t)
	_write_standard_byte_identical(t)
	_write_verbatim(t)
	_write_parse_roundtrip(t)


func _constants(t) -> void:
	t.eq(BzVxt.STANDARD_OBSERVERS.size(), 5)
	t.eq(BzVxt.STANDARD_OBSERVERS[0], "avobserv avobserv.des\tx\tNSDF")
	t.eq(BzVxt.STANDARD_OBSERVERS[1], "svobserv svobserv.des\tx\tCCA")
	t.eq(BzVxt.STANDARD_OBSERVERS[2], "bvobserv bvobserv.des\tx\tBDOG")
	t.eq(BzVxt.STANDARD_OBSERVERS[3], "cvobserv cvobserv.des\tx\tCRA")
	t.eq(BzVxt.STANDARD_OBSERVERS[4], "observer observer.des\tx\tObserver")
	var joined := "\n\n".join(BzVxt.STANDARD_OBSERVERS)
	t.eq(BzVxt.STANDARD_VXT_TEXT, joined, "STANDARD_VXT_TEXT is join of observers")
	t.eq(BzVxt.STANDARD_VXT_TEXT.length(), 150)
	t.ok(not BzVxt.STANDARD_VXT_TEXT.ends_with("\n\n"), "no trailing blank line")


func _write_standard_byte_identical(t) -> void:
	var path := OS.get_temp_dir().path_join("bzvxt_standard.vxt")
	var ret: String = BzVxt.write_standard_vxt(path)
	t.eq(ret, path)
	var got := FileAccess.get_file_as_bytes(path)
	var want := BzVxt.STANDARD_VXT_TEXT.to_utf8_buffer()
	t.eq(got, want, "write_standard_vxt matches Python STANDARD_VXT_TEXT")
	t.eq(got.get_string_from_utf8(), BzVxt.STANDARD_VXT_TEXT)


func _write_verbatim(t) -> void:
	var path := OS.get_temp_dir().path_join("bzvxt_custom.vxt")
	# Includes CR/LF and a trailing newline — must not be translated or stripped.
	BzVxt.write_vxt(path, "hello\r\nworld\n")
	var got := FileAccess.get_file_as_bytes(path)
	t.eq(got, "hello\r\nworld\n".to_utf8_buffer(), "write_vxt is verbatim (Python newline='')")


func _write_parse_roundtrip(t) -> void:
	var path := OS.get_temp_dir().path_join("bzvxt_roundtrip.vxt")
	var text := BzVxt.STANDARD_VXT_TEXT
	BzVxt.write_vxt(path, text)
	var back := FileAccess.get_file_as_string(path)
	t.eq(back, text, "write→read text round-trip")
	var path2 := OS.get_temp_dir().path_join("bzvxt_roundtrip2.vxt")
	BzVxt.write_vxt(path2, back)
	t.eq(
		FileAccess.get_file_as_bytes(path2),
		text.to_utf8_buffer(),
		"second write stays byte-identical"
	)
