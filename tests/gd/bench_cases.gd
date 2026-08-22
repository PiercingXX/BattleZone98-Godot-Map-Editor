extends RefCounted
## Benchmark cases. Kept out of bench_main.gd because the -s script is compiled
## before the autoloads are registered, so a direct MapState reference there is
## an "Identifier not found" at load time; run_tests.gd loads its test files the
## same way and for the same reason.

## 1024 cells × 5 m = 5115 m across — the map size AGENTS.md rule 6 names.
const BIG := 1024
## The O(n·radius) selection filters are quadratic enough that a 5 km grid
## would dominate the whole run. Half-size keeps the shape visible in seconds.
const SEL := 512
## One sculpt brush stamp: the rect that actually moves while the mouse is down.
const BRUSH := 64

var _field: HeightField
var _sel_field: HeightField
var _brush_values: PackedInt32Array


func run(bench) -> void:
	_setup()
	_bench_heightfield(bench)
	_bench_raycast(bench)
	_bench_selection(bench)
	_teardown()


func _setup() -> void:
	_field = _make_field(BIG, BIG)
	_sel_field = _make_field(SEL, SEL)
	_brush_values = PackedInt32Array()
	_brush_values.resize(BRUSH * BRUSH)
	_brush_values.fill(1500)


func _teardown() -> void:
	MapState.field = HeightField.new()
	MapState.clear_selection()


## Deterministic lumpy terrain — same bytes on every machine, so two runs
## differ because the hardware differs, not because the data did.
func _make_field(gx: int, gz: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	for z in gz:
		var row := z * gx
		for x in gx:
			field.heights[row + x] = 800 + ((x * 7 + z * 13) % 61) * 30
	field.upload_rect(0, 0, gx, gz)
	field.flush_upload()
	return field


# ------------------------------------------------------- height texture ----

func _bench_heightfield(bench) -> void:
	bench.run("heightfield.full_upload_%d" % BIG, 10, _case_full_upload)
	bench.run("heightfield.dirty_rect_%d" % BRUSH, 300, _case_dirty_rect)
	bench.run("heightfield.write_rect_%d" % BRUSH, 200, _case_write_rect)
	bench.run("heightfield.cold_build_%d" % BIG, 5, _case_cold_build)


## Whole height texture re-encoded and pushed. This is what opening a map
## costs — and what a per-frame mesh/texture rebuild would cost every frame.
func _case_full_upload() -> void:
	_field.upload_rect(0, 0, BIG, BIG)
	_field.flush_upload()


## The dirty-rect path rule 6 mandates. Compare against full_upload: the ratio
## is the whole argument for keeping dirty rects.
func _case_dirty_rect() -> void:
	_field.upload_rect(300, 300, BRUSH, BRUSH)
	_field.flush_upload()


## CPU write plus upload — one undoable sculpt step's worth of work.
func _case_write_rect() -> void:
	_field.write_rect(300, 300, BRUSH, BRUSH, _brush_values)


## Cold path: allocate the CPU array, encode every cell to FORMAT_RF and
## create the texture from scratch. This is the terrain half of opening a map.
##
## TerrainRenderer's own chunk build is deliberately NOT benchmarked here. It
## needs a live scene tree, a camera and the terrain shader, none of which
## exist headlessly, and its internals are mid-rewrite; a benchmark bolted to
## a private method of a moving file would measure the harness's luck, not the
## renderer. The height texture below is the upload the renderer consumes.
func _case_cold_build() -> void:
	var field := HeightField.new()
	field.grid_x = BIG
	field.grid_z = BIG
	field.heights = _field.heights
	field.upload_rect(0, 0, BIG, BIG)
	field.flush_upload()


# ------------------------------------------------------------- raycast -----

func _bench_raycast(bench) -> void:
	bench.run("raycast.intersect_vertical", 400, _case_ray_vertical)
	bench.run("raycast.intersect_grazing", 100, _case_ray_grazing)
	bench.run("raycast.height_at_x1000", 100, _case_height_at)
	bench.run("raycast.normal_at_x1000", 100, _case_normal_at)


## The common case: a mouse pick straight down at the cursor. One DDA cell.
func _case_ray_vertical() -> void:
	TerrainRaycast.intersect(
		Vector3(2557.5, 4000.0, 2551.3), Vector3(0.0, -1.0, 0.0), _field
	)


## The worst case: a near-horizontal pick from a low fly camera, which walks
## the DDA across a large share of the grid before it finds a facet.
func _case_ray_grazing() -> void:
	TerrainRaycast.intersect(
		Vector3(3.0, 260.0, 7.0), Vector3(1.0, -0.02, 0.35).normalized(), _field
	)


## Sampling cost on its own, amortised over 1000 calls so the per-iteration
## Callable dispatch does not dominate the measurement.
func _case_height_at() -> void:
	for i in 1000:
		TerrainRaycast.height_at(_field, float(i) * 4.9, float(i) * 3.1)


func _case_normal_at() -> void:
	for i in 1000:
		TerrainRaycast.normal_at(_field, float(i) * 4.9, float(i) * 3.1)


# ----------------------------------------------------------- selection -----

func _bench_selection(bench) -> void:
	MapState.field = _field
	bench.run("mapstate.select_all_%d" % BIG, 20, _case_select_all)
	# Half the grid, so inverting always lands on a non-empty mask. Inverting a
	# fully-selected mask empties it, and the empty case short-circuits to
	# select_all — which would benchmark the fast path half the time.
	MapState.rect_terrain_selection(0, 0, BIG - 1, BIG / 2, MapState.SEL_REPLACE)
	bench.run("mapstate.invert_selection_%d" % BIG, 10, _case_invert_selection)
	MapState.clear_selection()

	MapState.field = _sel_field
	MapState.select_all_terrain()
	bench.run("mapstate.feather_selection_%d_r10m" % SEL, 5, _case_feather_selection)
	MapState.clear_selection()


## Full-grid fill plus a fresh R8 selection texture.
func _case_select_all() -> void:
	MapState.select_all_terrain()


## An O(n) GDScript loop over every cell of the heightfield.
func _case_invert_selection() -> void:
	MapState.invert_terrain_selection()


## Separable box blur: O(n · radius). The heaviest selection op there is.
func _case_feather_selection() -> void:
	MapState.feather_terrain_selection(10.0)
