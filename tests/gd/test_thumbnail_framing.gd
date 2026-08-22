extends RefCounted
## Framing and batch-slicing maths for 3D asset thumbnails.
##
## Synthetic boxes only — no game content, and nothing that needs a GPU. This
## is the half of thumbnail generation that is silently wrong when it is
## wrong: a mis-framed asset is a blank icon, and a slicing off-by-one
## shuffles every icon in the palette without ever erroring.

const _EPS := 0.0001


func run(t) -> void:
	_test_aabb_single(t)
	_test_aabb_nested(t)
	_test_aabb_ignores_root_transform(t)
	_test_aabb_skips_hidden(t)
	_test_aabb_empty(t)
	_test_fit_centres_and_fills(t)
	_test_fit_frames_offset_mesh(t)
	_test_fit_rotated_view_stays_in_cell(t)
	_test_fit_degenerate(t)
	_test_grid_dims(t)
	_test_cell_rect_row_major(t)
	_test_cell_center_matches_cell_rect(t)
	_test_slice_order_and_orientation(t)
	_test_slice_short_image(t)


# --- recursive visual AABB ---------------------------------------------------

func _test_aabb_single(t) -> void:
	var mi := _box_instance(Vector3(2, 4, 6), Vector3.ZERO)
	var box := ThumbnailFraming.visual_aabb(mi)
	_near_v(t, box.position, Vector3(-1, -2, -3), "single box position")
	_near_v(t, box.size, Vector3(2, 4, 6), "single box size")
	t.ok(ThumbnailFraming.has_visual(mi), "box has visual")
	mi.free()


func _test_aabb_nested(t) -> void:
	var root := Node3D.new()
	var mid := Node3D.new()
	mid.position = Vector3(10, 0, 0)
	root.add_child(mid)
	mid.add_child(_box_instance(Vector3(2, 2, 2), Vector3(0, 5, 0)))
	# A second box elsewhere: the union has to cover both, not just the last.
	root.add_child(_box_instance(Vector3(2, 2, 2), Vector3(-4, 0, 0)))
	var box := ThumbnailFraming.visual_aabb(root)
	_near_v(t, box.position, Vector3(-5, -1, -1), "nested union position")
	_near_v(t, box.size, Vector3(16, 7, 2), "nested union size")
	root.free()


func _test_aabb_ignores_root_transform(t) -> void:
	## Framing sets the root transform, so measuring it would feed the result
	## back into itself and every icon would drift.
	var root := Node3D.new()
	root.add_child(_box_instance(Vector3(2, 2, 2), Vector3(3, 0, 0)))
	var before := ThumbnailFraming.visual_aabb(root)
	root.position = Vector3(1000, -50, 7)
	root.scale = Vector3(3, 3, 3)
	var after := ThumbnailFraming.visual_aabb(root)
	_near_v(t, after.position, before.position, "root move does not move aabb")
	_near_v(t, after.size, before.size, "root scale does not scale aabb")
	root.free()


func _test_aabb_skips_hidden(t) -> void:
	var root := Node3D.new()
	root.add_child(_box_instance(Vector3(2, 2, 2), Vector3.ZERO))
	var hidden := _box_instance(Vector3(2, 2, 2), Vector3(100, 0, 0))
	hidden.visible = false
	root.add_child(hidden)
	var box := ThumbnailFraming.visual_aabb(root)
	_near_v(t, box.size, Vector3(2, 2, 2), "hidden LOD shell excluded")
	root.free()


func _test_aabb_empty(t) -> void:
	var root := Node3D.new()
	root.add_child(Node3D.new())
	var box := ThumbnailFraming.visual_aabb(root)
	t.eq(box.size, Vector3.ZERO, "no meshes → zero size")
	t.ok(not ThumbnailFraming.has_visual(root), "no visual")
	root.free()


# --- camera framing ----------------------------------------------------------

func _test_fit_centres_and_fills(t) -> void:
	var box := AABB(Vector3(-1, -2, -3), Vector3(2, 4, 6))
	var xf := ThumbnailFraming.fit_transform(
		box, Basis(), Vector3.ZERO, Vector2.ONE, 0.8
	)
	var framed: AABB = xf * box
	_near_v(t, framed.get_center(), Vector3.ZERO, "framed centre is the cell")
	# y is the tall axis: 4 → 0.8, so the uniform scale is 0.2.
	t.near(framed.size.y, 0.8, _EPS, "tall axis fills the cell")
	t.near(framed.size.x, 0.4, _EPS, "short axis scales with it")
	t.near(framed.size.z, 1.2, _EPS, "depth is not constrained")


func _test_fit_frames_offset_mesh(t) -> void:
	## A hull modelled far from its own origin is the classic blank icon.
	var at_origin := AABB(Vector3(-1, -2, -3), Vector3(2, 4, 6))
	var far_away := AABB(Vector3(499, 98, -103), Vector3(2, 4, 6))
	var view := ThumbnailFraming.view_basis()
	var cell := Vector3(1.5, -0.5, 0.0)
	var a: AABB = ThumbnailFraming.fit_transform(at_origin, view, cell) * at_origin
	var b: AABB = ThumbnailFraming.fit_transform(far_away, view, cell) * far_away
	_near_v(t, a.get_center(), cell, "origin-centred hull lands on the cell")
	_near_v(t, b.get_center(), cell, "offset hull lands on the same cell")
	_near_v(t, a.size, b.size, "offset does not change the framed size")


func _test_fit_rotated_view_stays_in_cell(t) -> void:
	var view := ThumbnailFraming.view_basis(45.0, 30.0)
	var shapes: Array[AABB] = [
		AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)),
		AABB(Vector3(0, 0, 0), Vector3(30, 1, 30)),
		AABB(Vector3(-0.05, -8, -0.05), Vector3(0.1, 16, 0.1)),
	]
	for i in shapes.size():
		var box: AABB = shapes[i]
		var centre := ThumbnailGrid.cell_center(i, 2, 2)
		var framed: AABB = ThumbnailFraming.fit_transform(box, view, centre) * box
		_near_v(t, framed.get_center(), centre, "shape %d centred" % i)
		var widest := maxf(framed.size.x, framed.size.y)
		t.near(widest, 0.8, 0.001, "shape %d fills 80%% of its cell" % i)
		var lo := framed.position
		var hi := framed.position + framed.size
		t.ok(lo.x >= centre.x - 0.5 - _EPS and hi.x <= centre.x + 0.5 + _EPS,
			"shape %d inside the cell horizontally" % i)
		t.ok(lo.y >= centre.y - 0.5 - _EPS and hi.y <= centre.y + 0.5 + _EPS,
			"shape %d inside the cell vertically" % i)


func _test_fit_degenerate(t) -> void:
	var flat := AABB(Vector3(5, 5, 5), Vector3.ZERO)
	var xf := ThumbnailFraming.fit_transform(flat, Basis(), Vector3(1, 1, 0))
	t.eq(ThumbnailFraming.fit_scale(flat, Basis()), 0.0, "nothing to fit")
	_near_v(t, xf.origin, Vector3(1, 1, 0), "degenerate falls back to the cell")


# --- batch grid --------------------------------------------------------------

func _test_grid_dims(t) -> void:
	t.eq(ThumbnailGrid.columns_for(0, 4), 0, "empty batch has no columns")
	t.eq(ThumbnailGrid.columns_for(1, 4), 1, "one asset, one column")
	t.eq(ThumbnailGrid.columns_for(3, 4), 3)
	t.eq(ThumbnailGrid.columns_for(9, 4), 4)
	t.eq(ThumbnailGrid.rows_for(1, 1), 1)
	t.eq(ThumbnailGrid.rows_for(4, 4), 1, "a full row is one row")
	t.eq(ThumbnailGrid.rows_for(5, 4), 2, "the fifth asset wraps")
	t.eq(ThumbnailGrid.rows_for(16, 4), 4)
	t.eq(ThumbnailGrid.viewport_size(4, 3, 96), Vector2i(384, 288))
	t.eq(ThumbnailGrid.camera_size(3), 3.0, "one world unit per cell row")


func _test_cell_rect_row_major(t) -> void:
	t.eq(ThumbnailGrid.cell_rect(0, 3, 8), Rect2i(0, 0, 8, 8), "index 0 top-left")
	t.eq(ThumbnailGrid.cell_rect(2, 3, 8), Rect2i(16, 0, 8, 8), "end of row 0")
	t.eq(ThumbnailGrid.cell_rect(3, 3, 8), Rect2i(0, 8, 8, 8), "wraps to row 1")
	t.eq(ThumbnailGrid.cell_rect(5, 3, 8), Rect2i(16, 8, 8, 8))


func _test_cell_center_matches_cell_rect(t) -> void:
	## The one seam that batching can get wrong: world placement and pixel
	## readback disagreeing. Project each cell centre through the orthogonal
	## camera by hand and demand the same pixel the slicer will cut.
	var cols := 4
	var rows := 3
	var px := 32
	for i in cols * rows:
		var c := ThumbnailGrid.cell_center(i, cols, rows)
		# +x right, +y UP in world; +y DOWN in pixels.
		var sx := (c.x + float(cols) * 0.5) * float(px)
		var sy := (float(rows) * 0.5 - c.y) * float(px)
		var rect := ThumbnailGrid.cell_rect(i, cols, px)
		var mid := Vector2(rect.position) + Vector2(rect.size) * 0.5
		t.near(sx, mid.x, _EPS, "cell %d projects to its own column" % i)
		t.near(sy, mid.y, _EPS, "cell %d projects to its own row" % i)


func _test_slice_order_and_orientation(t) -> void:
	## Paint the grid from an independent formula, then demand the slicer
	## hands back exactly those cells — right index, right way up, not
	## transposed and not mirrored.
	var cols := 3
	var rows := 2
	var px := 8
	var img := Image.create_empty(cols * px, rows * px, false, Image.FORMAT_RGBA8)
	for y in rows * px:
		for x in cols * px:
			var idx := int(y / px) * cols + int(x / px)
			img.set_pixel(x, y, _mark(idx, x % px, y % px))
	var cells := ThumbnailGrid.slice(img, cols * rows, cols, px)
	t.eq(cells.size(), 6, "one image per cell")
	for i in 6:
		var cell: Image = cells[i]
		if cell == null:
			t.fail("cell %d missing" % i)
			continue
		t.eq(cell.get_width(), px)
		t.eq(cell.get_height(), px)
		var bad := 0
		for ly in px:
			for lx in px:
				if not cell.get_pixel(lx, ly).is_equal_approx(_mark(i, lx, ly)):
					bad += 1
		t.eq(bad, 0, "cell %d pixels match cell %d of the source" % [i, i])


func _test_slice_short_image(t) -> void:
	## A truncated readback must read as a miss, never as a blank icon that
	## then gets cached forever.
	var img := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var cells := ThumbnailGrid.slice(img, 4, 2, 8)
	t.eq(cells.size(), 4)
	t.ok(cells[0] != null and cells[1] != null, "row 0 slices")
	t.eq(cells[2], null, "row 1 is not in the image")
	t.eq(cells[3], null, "row 1 is not in the image")


# --- helpers -----------------------------------------------------------------

func _mark(idx: int, lx: int, ly: int) -> Color:
	return Color8(20 + idx * 30, 10 + lx * 20, 5 + ly * 25, 255)


func _box_instance(size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	return mi


func _near_v(t, got: Vector3, want: Vector3, msg: String) -> void:
	t.near(got.x, want.x, _EPS, "%s x" % msg)
	t.near(got.y, want.y, _EPS, "%s y" % msg)
	t.near(got.z, want.z, _EPS, "%s z" % msg)
