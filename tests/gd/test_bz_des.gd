extends RefCounted
## BzDes: write_des_text, write→read, size_band (F8 widths), Python golden.


func run(t) -> void:
	var work := _work_dir()

	# --- parse / emit the documented four-line blurb ---
	var text := BzDes.write_des_text("ignored", "Mars", "Medium", 3, 12, 14)
	var want := "WORLD: Mars\tSIZE: Medium\r\nGEYSERS: 3\tSCRAP: 12\r\nPLAYERS: 14\r\nMade by Skippy\r\n"
	t.eq(text, want, "write_des_text matches des.py")
	var lines := text.replace("\r\n", "\n").split("\n", false)
	t.eq(lines.size(), 4)
	t.ok(lines[0].begins_with("WORLD: Mars"), "world")
	t.ok(lines[0].contains("SIZE: Medium"), "size")
	t.ok(lines[1].contains("GEYSERS: 3"), "geyser count from caller")
	t.ok(lines[1].contains("SCRAP: 12"), "scrap count from caller")
	t.eq(lines[2], "PLAYERS: 14")
	t.eq(lines[3], "Made by Skippy")

	# custom author; mission_name still unused
	var custom := BzDes.write_des_text("The Name", "Io", "Small", 0, 0, 2, "Ada")
	t.eq(custom, "WORLD: Io\tSIZE: Small\r\nGEYSERS: 0\tSCRAP: 0\r\nPLAYERS: 2\r\nMade by Ada\r\n")
	t.ok(not custom.contains("The Name"), "mission_name is not written (des.py)")

	# --- write → parse (read file back) ---
	var path := work.path_join("map.des")
	BzDes.write_des(path, "ignored", "Mars", "Medium", 3, 12, 14)
	_eq_bytes(t, path, want, "write_des file == write_des_text")
	var round := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	t.eq(BzDes.write_des_text("ignored", "Mars", "Medium", 3, 12, 14), round)

	# --- size_band (F8 §2 zone widths) ---
	t.eq(BzDes.size_band(0.0), "Small")
	t.eq(BzDes.size_band(1280.0), "Small", "1×1 zone")
	t.eq(BzDes.size_band(2560.0), "Small", "2×N inclusive ceiling")
	t.eq(BzDes.size_band(2561.0), "Medium")
	t.eq(BzDes.size_band(3840.0), "Medium", "3×N inclusive ceiling")
	t.eq(BzDes.size_band(3841.0), "Large")
	t.eq(BzDes.size_band(5120.0), "Large", "4×4 max observed (F8) is Large, not Huge")
	t.eq(BzDes.SIZE_BANDS.size(), 3)

	var fixture := ProjectSettings.globalize_path("res://tests/gd/fixtures/des/sample.txt")
	if FileAccess.file_exists(fixture):
		_eq_bytes(t, fixture, want, "checked-in des golden")


func _work_dir() -> String:
	var d := OS.get_cache_dir().path_join("bz_des_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _eq_bytes(t, path: String, want: String, msg: String) -> void:
	var got := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	t.eq(got, want, msg)
