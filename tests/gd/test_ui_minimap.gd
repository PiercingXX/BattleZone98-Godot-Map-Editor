extends RefCounted
## Minimap: north-up orientation (C8), overlay degrade (C15), dirty-rect
## repaint (C17), camera heading, click-to-fly.

const PanelScene := "res://project/ui/minimap/MinimapPanel.tscn"
const ViewScript := "res://project/ui/minimap/MinimapView.gd"

const GRID := 64
const BASE_RAW := 500
const SPIKE_RAW := 3000
const BLOCK := 16


func run(t) -> void:
	_orientation(t)
	_norm_space(t)
	_texel_mapping(t)
	_degrade(t)
	_scatter(t)
	_dirty_rect(t)
	await _view_interaction(t)
	await _panel(t)


## The one defect this panel has a documented history of (docs/02 §north-up:
## a mirrored render shipped once). A single raised block is put at each of
## the four corners in turn and the brightest quadrant of the rendered image
## must be the matching one. Four corners, not one: a 180° rotation or a
## single-axis mirror satisfies some of them and fails the rest.
func _orientation(t) -> void:
	var corners := [
		["south-west", 0, 0, "bottom-left", 2],
		["south-east", GRID - BLOCK, 0, "bottom-right", 3],
		["north-west", 0, GRID - BLOCK, "top-left", 0],
		["north-east", GRID - BLOCK, GRID - BLOCK, "top-right", 1],
	]
	for c in corners:
		var raster := _raster_with_block(int(c[1]), int(c[2]))
		t.eq(raster.tex_w, GRID, "no downsample at grid 64")
		t.eq(raster.tex_h, GRID)
		var means := _quadrant_means(raster.image)
		var want := int(c[4])
		var best := 0
		for i in 4:
			if means[i] > means[best]:
				best = i
		t.eq(best, want, "%s block renders in the %s quadrant" % [c[0], c[3]])
		# Not just "brightest": clearly brighter, so a near-tie cannot pass.
		for i in 4:
			if i == want:
				continue
			t.ok(
				means[want] > means[i] * 1.3,
				"%s quadrant %.3f clearly beats quadrant %d %.3f"
					% [c[3], means[want], i, means[i]]
			)

	# And directly, without averaging: the northernmost cell row is row 0.
	var north := _raster_with_block(GRID - BLOCK, GRID - BLOCK)
	t.eq(north.texel_y(GRID - 1), 0, "+z (north) is image row 0 — C8")
	t.eq(north.texel_y(0), GRID - 1, "z = 0 (south) is the bottom row")
	t.eq(north.texel_x(0), 0, "x = 0 (west) is column 0")
	t.eq(north.texel_x(GRID - 1), GRID - 1, "+x (east) is the right column")
	var lit := north.image.get_pixel(north.texel_x(GRID - 4), north.texel_y(GRID - 4))
	var dim := north.image.get_pixel(north.texel_x(4), north.texel_y(4))
	t.ok(_lum(lit) > _lum(dim) * 1.5, "the raised NE cell is the bright texel")


func _norm_space(t) -> void:
	var d := _flat_data()
	t.near(d.width_m(), float(GRID) * 5.0, 0.001, "width is grid * 5 m (C3)")
	var north := d.world_to_norm(0.0, d.depth_m())
	t.near(north.y, 0.0, 0.0001, "max z maps to the TOP of the panel")
	var south := d.world_to_norm(0.0, 0.0)
	t.near(south.y, 1.0, 0.0001, "z = 0 maps to the bottom")
	var east := d.world_to_norm(d.width_m(), 0.0)
	t.near(east.x, 1.0, 0.0001, "max x maps to the right")
	var back := d.norm_to_world(Vector2(0.25, 0.25))
	t.near(back.x, d.width_m() * 0.25, 0.001)
	t.near(back.y, d.depth_m() * 0.75, 0.001, "norm y inverts back to world z")


func _texel_mapping(t) -> void:
	var d := MinimapData.new()
	d.grid_x = 512
	d.grid_z = 512
	d.heights = PackedInt32Array()
	d.heights.resize(512 * 512)
	var raster := MinimapRaster.new()
	t.ok(raster.configure(d), "large grid configures")
	t.ok(raster.step > 1, "a 512 grid downsamples")
	t.ok(not raster.painting(), "configure alone paints nothing")
	raster.begin_full()
	t.ok(raster.painting(), "begin_full queues the whole image")
	t.ok(not raster.pump(1), "a one-microsecond budget does not finish it")
	t.ok(raster.pump(2000000), "a generous budget does")
	t.ok(not raster.painting(), "and then nothing is pending (C17)")
	t.ok(raster.tex_w <= MinimapRaster.MAX_TEXELS, "texels are capped")
	for z in [0, 137, 511]:
		var v: int = raster.texel_y(int(z))
		t.ok(v >= 0 and v < raster.tex_h, "row in range for z=%d" % z)
		t.ok(
			absi(raster.cell_z(v) - int(z)) <= raster.step,
			"cell_z inverts texel_y within a step for z=%d" % z
		)
	t.eq(raster.texel_y(511), 0, "north stays row 0 when downsampled")


func _degrade(t) -> void:
	# C15: no game, no material grid, no scatter — still an image, no crash.
	var raster := MinimapRaster.new()
	t.ok(raster.configure(_flat_data()))
	raster.set_mode(MinimapRaster.Mode.MATERIAL)
	raster.render_all()
	t.ok(raster.image != null, "material mode still renders without a grid")
	t.ok(not raster.degraded().is_empty(), "and says why")
	t.ok("relief" in raster.degraded(), "degrade message names the fallback")
	raster.set_mode(MinimapRaster.Mode.SCATTER)
	t.ok(not raster.degraded().is_empty(), "scatter with no source degrades")
	raster.set_mode(MinimapRaster.Mode.RELIEF)
	t.eq(raster.degraded(), "", "relief never degrades")
	t.eq(raster.mode_name(), "Relief")

	var d := _flat_data()
	d.mat_grid_x = GRID / MinimapData.MAT_CELLS
	d.mat_grid_z = GRID / MinimapData.MAT_CELLS
	d.materials = PackedInt32Array()
	d.materials.resize(d.mat_grid_x * d.mat_grid_z)
	for i in d.materials.size():
		d.materials[i] = (3 & 0xF) << 12
	t.ok(d.has_materials())
	t.eq(d.material_base(0, 0), 3, "base nibble decodes to the painted slot")
	var mat := MinimapRaster.new()
	mat.configure(d)
	mat.set_mode(MinimapRaster.Mode.MATERIAL)
	mat.render_all()
	t.eq(mat.degraded(), "", "material mode with a grid does not degrade")
	var want := MaterialPalette.colors()[3]
	var got := mat.image.get_pixel(GRID / 2, GRID / 2)
	t.ok(
		absf(_hue_ratio(got) - _hue_ratio(want)) < 0.25,
		"material overlay uses the palette colour for slot 3"
	)


func _scatter(t) -> void:
	var d := _flat_data()
	t.ok(not d.has_scatter(), "no source, no scatter")
	t.ok(not d.attach_scatter(null), "null source is not an error")

	# The mask shape: grid_x / grid_z / values, which is what ScatterMask has,
	# so neither side needs to know about the other.
	var mask := _StubMask.new()
	mask.grid_x = GRID
	mask.grid_z = GRID
	mask.values.resize(GRID * GRID)
	for z in range(GRID - BLOCK, GRID):
		for x in range(GRID - BLOCK, GRID):
			mask.values[z * GRID + x] = 1
	t.ok(d.attach_scatter(mask), "a mask-shaped object is adopted")
	t.ok(d.has_scatter())
	t.eq(d.scatter_at(GRID - 2, GRID - 2), 1, "painted cell reads back")
	t.eq(d.scatter_at(2, 2), 0, "unpainted cell is empty")
	t.near(d.scatter_coverage(GRID - 2, GRID - 2, 1), 1.0, 0.0001)
	t.near(d.scatter_coverage(2, 2, 1), 0.0, 0.0001)

	var raster := MinimapRaster.new()
	raster.configure(d)
	raster.set_mode(MinimapRaster.Mode.SCATTER)
	t.eq(raster.degraded(), "", "scatter mode with a source does not degrade")
	raster.render_all()
	var hot := raster.image.get_pixel(raster.texel_x(GRID - 4), raster.texel_y(GRID - 4))
	var cold := raster.image.get_pixel(raster.texel_x(4), raster.texel_y(4))
	t.ok(hot.r > cold.r + 0.15, "occupied cells read warmer than empty ones")

	# The explicit contract still wins when a source offers it.
	var src := _StubOccupancy.new()
	src.grid_x = 4
	src.grid_z = 4
	src.cells.resize(16)
	src.cells[15] = 255
	var d2 := _flat_data()
	t.ok(d2.attach_scatter(src), "minimap_occupancy() source is adopted")
	t.eq(d2.scatter_grid_x, 4)
	src.cells = PackedByteArray()
	t.ok(not d2.attach_scatter(src), "a short buffer is refused, not adopted")
	t.ok(not d2.has_scatter())


## C17: an edit repaints the texels it touched, not the whole image.
func _dirty_rect(t) -> void:
	var d := _flat_data()
	var raster := MinimapRaster.new()
	raster.configure(d)
	raster.render_all()
	var before := raster.image.get_data()

	var x0 := 20
	var z0 := 20
	var x1 := 23
	var z1 := 23
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			d.heights[z * GRID + x] = SPIKE_RAW
	raster.render_cell_rect(x0, z0, x1, z1)
	var after := raster.image.get_data()
	t.eq(before.size(), after.size(), "image size is stable across a rect repaint")

	var u0 := raster.texel_x(x0) - 1
	var u1 := raster.texel_x(x1) + 1
	var va := raster.texel_y(z0)
	var vb := raster.texel_y(z1)
	var v0 := mini(va, vb) - 1
	var v1 := maxi(va, vb) + 1
	var changed := 0
	var strays := 0
	for v in raster.tex_h:
		for u in raster.tex_w:
			var i := (v * raster.tex_w + u) * 4
			if before[i] == after[i] and before[i + 1] == after[i + 1] \
					and before[i + 2] == after[i + 2]:
				continue
			changed += 1
			if u < u0 or u > u1 or v < v0 or v > v1:
				strays += 1
	t.ok(changed > 0, "the edited rect actually repainted")
	t.eq(strays, 0, "no texel outside the dirty rect (plus halo) was touched")
	t.ok(changed < raster.tex_w * raster.tex_h / 4, "a small edit is a small repaint")


func _view_interaction(t) -> void:
	# Heading is drawn, not just position, so the pilot can tell which way
	# the camera faces. North must point UP on the panel.
	var ViewCls: GDScript = load(ViewScript)
	t.eq(ViewCls.heading_map_dir(Vector3(0, 0, 1)), Vector2(0, -1), "north heads up")
	t.eq(ViewCls.heading_map_dir(Vector3(0, 0, -1)), Vector2(0, 1), "south heads down")
	t.eq(ViewCls.heading_map_dir(Vector3(1, 0, 0)), Vector2(1, 0), "east heads right")
	t.eq(ViewCls.heading_map_dir(Vector3(-1, 0, 0)), Vector2(-1, 0), "west heads left")
	t.eq(
		ViewCls.heading_map_dir(Vector3(0, -1, 0)), Vector2.UP,
		"looking straight down falls back to north-up"
	)

	var view: MinimapView = ViewCls.new()
	view.name = "MinimapViewTest"
	t.tree.root.add_child(view)
	view.size = Vector2(200, 200)
	await t.tree.process_frame

	var d := _flat_data()
	t.ok(view.raster.configure(d))
	view.raster.render_all()
	var m: Rect2 = view.map_rect()
	t.ok(m.size.x > 100.0 and m.size.y > 100.0, "square map fills the square view")
	t.near(m.size.x, m.size.y, 0.5, "aspect preserved")

	var flown: Array = []
	view.fly_requested.connect(func(w: Vector3) -> void: flown.append(w))
	var top_right := m.position + Vector2(m.size.x - 1.0, 1.0)
	_click(view, top_right)
	t.eq(flown.size(), 1, "a left click flies")
	var w: Vector3 = flown[0]
	t.ok(w.x > d.width_m() * 0.9, "clicking the right edge flies east")
	t.ok(w.z > d.depth_m() * 0.9, "clicking the TOP edge flies north — C8")
	t.near(w.y, float(BASE_RAW) * HeightField.HEIGHT_SCALE, 0.5, "y is ground height")

	flown.clear()
	_click(view, m.position + Vector2(1.0, m.size.y - 1.0))
	t.eq(flown.size(), 1)
	t.ok(flown[0].z < d.depth_m() * 0.1, "clicking the bottom edge flies south")

	var menus: Array = []
	view.context_menu_requested.connect(func(at: Vector2) -> void: menus.append(at))
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	rmb.position = m.get_center()
	view._gui_input(rmb)
	t.eq(menus.size(), 1, "right click asks for the overlay menu")

	# Camera marker: pose at the north-east corner sits at the top right.
	t.ok(view.camera_marker().is_empty(), "no pose, no marker")
	t.ok(view.update_camera_pose(
		Vector3(d.width_m(), 40.0, d.depth_m()), Vector3(0, 0, 1)
	), "first pose always redraws")
	var marker: Dictionary = view.camera_marker()
	t.near(marker["pos"].x, 1.0, 0.0001, "camera at max x is at the right edge")
	t.near(marker["pos"].y, 0.0, 0.0001, "camera at max z is at the TOP edge")
	t.eq(marker["dir"], Vector2(0, -1), "facing north draws pointing up")
	t.ok(
		not view.update_camera_pose(
			Vector3(d.width_m() + 0.5, 40.0, d.depth_m()), Vector3(0, 0, 1)
		),
		"a sub-threshold nudge does not schedule a repaint (C17)"
	)
	t.ok(
		view.update_camera_pose(Vector3(20.0, 40.0, 20.0), Vector3(1, 0, 0)),
		"a real move does"
	)

	# Smoke the draw path itself: markers plus a camera arrow, drawn for real.
	# A failure here surfaces as a SCRIPT ERROR, which the harness reports.
	view.set_findings([
		{"severity": "error", "world_pos": [10.0, 0.0, 10.0]},
		{"severity": "warning", "world_pos": [200.0, 0.0, 300.0]},
		{"severity": "info", "title": "no position at all"},
	])
	view.queue_redraw()
	await t.tree.process_frame
	t.ok(true, "drawing markers and the camera arrow completes")

	# Zoom and pan.
	t.near(view.zoom(), 1.0, 0.0001)
	var r0: Rect2 = view.region_uv()
	t.near(r0.size.x, 1.0, 0.0001, "unzoomed shows the whole map")
	_wheel(view, m.get_center(), MOUSE_BUTTON_WHEEL_UP)
	t.ok(view.zoom() > 1.0, "wheel zooms in")
	var r1: Rect2 = view.region_uv()
	t.ok(r1.size.x < 1.0, "the visible slice shrinks")
	t.ok(r1.position.x >= -0.0001 and r1.position.x + r1.size.x <= 1.0001,
			"the slice stays inside the map")
	flown.clear()
	_drag(view, m.get_center(), Vector2(30, 0))
	t.eq(flown.size(), 0, "a drag pans, it does not fly")
	t.ok(view.region_uv().position.x < r1.position.x, "dragging right pans west")
	view.reset_view()
	t.near(view.zoom(), 1.0, 0.0001, "reset returns to the whole map")

	view.queue_free()
	await t.tree.process_frame


func _panel(t) -> void:
	var saved_session: bool = MapState.has_session
	var saved_field: HeightField = MapState.field
	MapState.has_session = false
	MapState.field = HeightField.new()
	MapState.session_changed.emit()

	var panel: Node = load(PanelScene).instantiate()
	t.tree.root.add_child(panel)
	panel.size = Vector2(260, 220)
	await t.tree.process_frame

	var view: MinimapView = panel.find_child("View", true, false)
	t.ok(view != null, "the panel owns a view")
	t.ok(not view.raster.ready(), "no map open, nothing to draw")
	t.ok((panel.find_child("TitleIcon", true, false) as TextureRect).texture != null)

	var modes: Array = []
	panel.overlay_changed.connect(func(m: int) -> void: modes.append(m))
	panel.set_overlay_mode(MinimapRaster.Mode.SLOPE)
	t.eq(modes, [MinimapRaster.Mode.SLOPE], "overlay changes are announced")
	t.eq(panel.overlay_mode(), MinimapRaster.Mode.SLOPE)
	panel.set_overlay_mode(MinimapRaster.Mode.SLOPE)
	t.eq(modes.size(), 1, "setting the same mode is a no-op")
	var menu: PopupMenu = panel.find_child("OverlayMenu", true, false)
	t.ok(menu != null and menu.item_count >= 5, "the overlay menu is built")
	t.ok(menu.is_item_checked(menu.get_item_index(MinimapRaster.Mode.SLOPE)),
			"the menu shows the active mode")
	panel.set_overlay_mode(MinimapRaster.Mode.RELIEF)

	# Now open a synthetic session and confirm the panel picks it up.
	var field := HeightField.new()
	field.grid_x = GRID
	field.grid_z = GRID
	field.heights = _heights(GRID - BLOCK, GRID - BLOCK)
	MapState.field = field
	MapState.has_session = true
	MapState.session_changed.emit()
	panel.flush()
	await t.tree.process_frame
	t.ok(view.raster.ready(), "the panel rebuilds on session_changed")
	t.ok(not view.raster.painting(), "flush() finishes the image")
	t.eq(view.raster.tex_h, GRID)
	var means := _quadrant_means(view.raster.image)
	var best := 0
	for i in 4:
		if means[i] > means[best]:
			best = i
	t.eq(best, 1, "the live panel is north-up too — C8")

	var flown: Array = []
	panel.fly_requested.connect(func(w: Vector3) -> void: flown.append(w))
	var m: Rect2 = view.map_rect()
	_click(view, m.position + Vector2(m.size.x - 1.0, 1.0))
	t.eq(flown.size(), 1, "the panel forwards the fly request")
	t.ok(flown[0].z > field.grid_z * 5.0 * 0.9, "north-east click flies north-east")

	# A dirty rect from the heightfield repaints without a full rebuild.
	field.heights[10 * GRID + 10] = SPIKE_RAW
	field.rect_dirty.emit(10, 10, 10, 10)
	panel.flush()
	t.ok(view.raster.ready(), "a rect repaint keeps the image")

	panel.set_findings([
		{"severity": "error", "title": "x", "world_pos": [10.0, 0.0, 10.0]},
		{"severity": "warning", "title": "no pos"},
	])
	await t.tree.process_frame

	t.ok(panel.has_method("set_collapsed"))
	panel.set_collapsed(true)
	t.ok(not view.visible, "collapse hides the map")
	panel.set_collapsed(false)
	t.ok(view.visible)

	MapState.has_session = false
	MapState.field = HeightField.new()
	MapState.session_changed.emit()
	panel.flush()
	await t.tree.process_frame
	t.ok(not view.raster.ready(), "closing the map empties the minimap")

	panel.queue_free()
	await t.tree.process_frame
	MapState.field = saved_field
	MapState.has_session = saved_session
	MapState.session_changed.emit()


# --- helpers ---------------------------------------------------------------


func _heights(bx: int, bz: int) -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(GRID * GRID)
	h.fill(BASE_RAW)
	for z in range(bz, bz + BLOCK):
		for x in range(bx, bx + BLOCK):
			h[z * GRID + x] = SPIKE_RAW
	return h


func _flat_data() -> MinimapData:
	var d := MinimapData.new()
	d.grid_x = GRID
	d.grid_z = GRID
	d.heights = PackedInt32Array()
	d.heights.resize(GRID * GRID)
	d.heights.fill(BASE_RAW)
	return d


func _raster_with_block(bx: int, bz: int) -> MinimapRaster:
	var d := MinimapData.new()
	d.grid_x = GRID
	d.grid_z = GRID
	d.heights = _heights(bx, bz)
	var raster := MinimapRaster.new()
	raster.configure(d)
	raster.render_all()
	return raster


## [top-left, top-right, bottom-left, bottom-right] mean luminance.
func _quadrant_means(img: Image) -> Array:
	var sums := [0.0, 0.0, 0.0, 0.0]
	var counts := [0, 0, 0, 0]
	var hw := img.get_width() / 2
	var hh := img.get_height() / 2
	for v in img.get_height():
		for u in img.get_width():
			var q := (0 if v < hh else 2) + (0 if u < hw else 1)
			sums[q] += _lum(img.get_pixel(u, v))
			counts[q] += 1
	var out := []
	for i in 4:
		out.append(sums[i] / maxf(float(counts[i]), 1.0))
	return out


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Rough colour identity that survives the hillshade multiply.
func _hue_ratio(c: Color) -> float:
	return c.r / maxf(c.r + c.g + c.b, 0.0001)


func _click(view: MinimapView, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	view._gui_input(up)


func _drag(view: MinimapView, from: Vector2, by: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	view._gui_input(down)
	var move := InputEventMouseMotion.new()
	move.position = from + by
	move.relative = by
	view._gui_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = from + by
	view._gui_input(up)


func _wheel(view: MinimapView, at: Vector2, button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = at
	view._gui_input(ev)


class _StubMask:
	extends RefCounted
	var grid_x: int = 0
	var grid_z: int = 0
	var values: PackedByteArray = PackedByteArray()


class _StubOccupancy:
	extends RefCounted
	var grid_x: int = 0
	var grid_z: int = 0
	var cells: PackedByteArray = PackedByteArray()

	func minimap_occupancy() -> Dictionary:
		return {"grid_x": grid_x, "grid_z": grid_z, "cells": cells}
