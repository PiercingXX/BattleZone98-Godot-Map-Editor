extends RefCounted
## Microbenchmark harness. Not a test: it asserts nothing and it is not wired
## into the blocking suite (run_tests.gd only discovers test_*.gd).
##
## Timing shape is deliberately boring so numbers from two machines are
## comparable: warm up, time every iteration individually with
## Time.get_ticks_usec(), sort, and report the distribution rather than an
## average. p95 is the number that matters for AGENTS.md rule 6 — a brush that
## is fast on average and stalls one frame in twenty still stutters.

## Iterations discarded before timing starts: enough for the first-call
## allocations and the CPU's caches to stop dominating.
const MIN_WARMUP := 5

var results: Array = []


## Time `body` `iterations` times and record the distribution. Returns the
## record it appended, so a caller can print or assert on it immediately.
func run(name: String, iterations: int, body: Callable) -> Dictionary:
	var iters := maxi(1, iterations)
	var warmup := maxi(MIN_WARMUP, int(iters / 10))
	for _i in warmup:
		body.call()
	var samples := PackedFloat64Array()
	samples.resize(iters)
	for i in iters:
		var t0 := Time.get_ticks_usec()
		body.call()
		samples[i] = float(Time.get_ticks_usec() - t0)
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for v in samples:
		total += v
	var rec := {
		"name": name,
		"iterations": iters,
		"warmup": warmup,
		"unit": "us",
		"min": sorted[0],
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"mean": total / float(iters),
		"max": sorted[iters - 1],
	}
	results.append(rec)
	return rec


## Everything a second machine needs to judge whether two runs are comparable.
func report() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	return {
		"godot": str(version.get("string", "")),
		"godot_version": version,
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"debug_build": OS.is_debug_build(),
		"rendering_driver": _rendering_driver(),
		"utc": Time.get_datetime_string_from_system(true),
		"results": results,
	}


## `path` may be res://, user://, or a native absolute path.
func write_json(path: String) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report(), "  ") + "\n")
	return OK


func format_table() -> String:
	var lines: Array[String] = []
	lines.append(
		"%-38s %7s %10s %10s %10s %10s %10s"
		% ["case", "iters", "min us", "p50 us", "p95 us", "mean us", "max us"]
	)
	lines.append("-".repeat(100))
	for rec in results:
		lines.append(
			"%-38s %7d %10.1f %10.1f %10.1f %10.1f %10.1f"
			% [
				rec["name"],
				rec["iterations"],
				rec["min"],
				rec["p50"],
				rec["p95"],
				rec["mean"],
				rec["max"],
			]
		)
	return "\n".join(lines)


## Nearest-rank, so p50 of an even sample count is a real observation rather
## than an interpolated value no run actually produced.
func _percentile(sorted: PackedFloat64Array, q: float) -> float:
	var n := sorted.size()
	if n < 1:
		return 0.0
	var idx := clampi(int(ceil(q * float(n))) - 1, 0, n - 1)
	return sorted[idx]


func _rendering_driver() -> String:
	if DisplayServer.get_name() == "headless":
		return "headless"
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
