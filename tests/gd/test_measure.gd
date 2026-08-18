extends RefCounted
## Select-tool measure: 3D distance and log line.

const MainScript = preload("res://scenes/main.gd")


func run(t) -> void:
	t.near(MainScript.measure_meters(Vector3.ZERO, Vector3(3, 4, 0)), 5.0)
	t.near(MainScript.measure_meters(Vector3(1, 2, 3), Vector3(1, 2, 3)), 0.0)
	t.near(MainScript.measure_meters(Vector3(0, 0, 0), Vector3(0, 0, 512.4)), 512.4, 0.01)
	var a := Vector3(10.0, 5.0, 20.0)
	var b := Vector3(10.0 + 300.0, 5.0, 20.0 + 400.0)
	t.near(MainScript.measure_meters(a, b), 500.0, 0.001, "3-4-5 scaled")
	t.eq(MainScript.measure_log_line(512.4), "measured 512.4 m")
	t.eq(MainScript.measure_log_line(0.0), "measured 0.0 m")
	t.eq(MainScript.measure_log_line(12.04), "measured 12.0 m")
	var tmp := OS.get_temp_dir().path_join("bz_shot_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	t.eq(SessionIO.next_screenshot_path(tmp, "map"), tmp.path_join("map-1.png"))
	var f := FileAccess.open(tmp.path_join("map-1.png"), FileAccess.WRITE)
	f.store_string("x")
	f.close()
	t.eq(SessionIO.next_screenshot_path(tmp, "map"), tmp.path_join("map-2.png"))
	DirAccess.remove_absolute(tmp.path_join("map-1.png"))
	DirAccess.remove_absolute(tmp)
