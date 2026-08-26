extends RefCounted
## set_material word encoding, material_at decode, write_materials_rect clip.


func run(t) -> void:
	_stroke_settles(t)
	_corrected_stroke(t)
	var saved_x: int = MapState.mat_grid_x
	var saved_z: int = MapState.mat_grid_z
	var saved_mats: PackedInt32Array = MapState.materials.duplicate()

	MapState.mat_grid_x = 8
	MapState.mat_grid_z = 8
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(64)
	MapState.materials.fill(0)

	MapState.set_material(2, 3, 5)
	var word: int = MapState.materials[3 * 8 + 2]
	t.eq(word, ((5 & 0xF) << 12) | ((5 & 0xF) << 8), "solid tile encoding")
	t.eq(MapState.material_at(40.0, 60.0), 5, "decode mat A nibble")
	t.eq(MapState.material_word_at(40.0, 60.0), MapState.materials[3 * 8 + 2], "word at world pos")
	var cap_word: int = BzMat.encode_entry(5, 1, 0, 1, 2, 0)
	MapState.set_material_word(4, 4, cap_word)
	t.eq(MapState.materials[4 * 8 + 4], cap_word, "manual cap word")
	t.eq(BzMat.kind_of_entry(MapState.material_word_at(80.0, 80.0)), "cap")

	var saved_kind := ToolState.paint_kind
	var saved_paint := ToolState.paint_material
	var saved_trans := ToolState.paint_transition
	var saved_flip := ToolState.paint_flip
	var saved_rot := ToolState.paint_rot
	ToolState.set_paint_kind("solid")
	ToolState.set_paint_material(4)
	t.eq(ToolState.paint_word(), BzMat.encode_entry(4, 4), "solid word")
	ToolState.set_paint_kind("cap")
	ToolState.set_paint_transition(1)
	ToolState.set_paint_flip(true)
	ToolState.set_paint_rot(2)
	t.eq(ToolState.paint_word(), BzMat.encode_entry(4, 1, 0, 1, 2, 0), "assigned cap word")
	ToolState.set_paint_from_word(BzMat.encode_entry(7, 2, 1, 0, 1, 0))
	t.eq(ToolState.paint_kind, "diag")
	t.eq(ToolState.paint_material, 7)
	t.eq(ToolState.paint_transition, 2)
	t.eq(ToolState.paint_rot, 1)
	ToolState.set_paint_kind(saved_kind)
	ToolState.set_paint_material(saved_paint)
	ToolState.set_paint_transition(saved_trans)
	ToolState.set_paint_flip(saved_flip != 0)
	ToolState.set_paint_rot(saved_rot)

	MapState.set_material(-1, 0, 3)
	MapState.set_material(0, 99, 3)
	t.eq(MapState.materials[0], 0, "out of bounds is a no-op")

	var vals := PackedInt32Array([11, 12, 13, 14])
	MapState.write_materials_rect(-1, -1, 2, 2, vals)
	t.eq(MapState.materials[0], 14, "clipped rect writes the overlapping cell")

	var big := PackedInt32Array()
	big.resize(4)
	big.fill(7)
	MapState.write_materials_rect(7, 7, 2, 2, big)
	t.eq(MapState.materials[7 * 8 + 7], 7, "high corner clip")

	MapState.materials.fill(0)
	for z in range(2, 5):
		for x in range(2, 5):
			MapState.set_material(x, z, 5)
	MapState.rematch_materials_rect(1, 1, 5, 5)
	var gx := 8
	t.eq(MapState.materials[3 * gx + 3], BzMat.encode_entry(5, 5), "3×3 interior stays solid")
	# A 3x3 of 5 on a field of 0. The higher cell of a boundary draws it, so
	# the patch carries its own edge and the 0 around it stays solid. mat_b is
	# the cell's own fill; a cap's rot is the half it keeps (0=-Z 1=+X 2=+Z
	# 3=-X) and a diagonal's rot puts mat_a in the corner cut off (0=(-X,-Z)
	# 1=(+X,-Z) 2=(+X,+Z) 3=(-X,+Z)).
	for pair in [[2 * gx + 3, 2], [3 * gx + 2, 1], [4 * gx + 3, 0], [3 * gx + 4, 3]]:
		var side: int = MapState.materials[int(pair[0])]
		t.eq((side >> 12) & 0xF, 0, "the neighbour bleeding in is mat_a")
		t.eq((side >> 8) & 0xF, 5, "the painted fill is mat_b")
		t.eq((side >> 7) & 1, 0, "a straight edge is a cap")
		t.eq((side >> 4) & 0x3, int(pair[1]), "rot keeps the half away from the 0")
		t.eq(BzMat.fill_of_entry(side), 5, "a transition's fill is mat_b")
	var nw: int = MapState.materials[2 * gx + 2]
	t.eq((nw >> 12) & 0xF, 0, "the corner cut off is mat_a")
	t.eq((nw >> 8) & 0xF, 5)
	t.eq((nw >> 7) & 1, 1, "NW outer corner is a diagonal")
	t.eq((nw >> 4) & 0x3, 1, "0 cuts the (-X,-Z) corner")
	t.eq(BzMat.fill_of_entry(nw), 5, "a diagonal's fill is the mat_b field")
	var ne: int = MapState.materials[2 * gx + 4]
	t.eq((ne >> 7) & 1, 1, "NE outer corner is a diagonal")
	t.eq((ne >> 4) & 0x3, 2, "0 cuts the (+X,-Z) corner")
	var sw: int = MapState.materials[4 * gx + 2]
	t.eq((sw >> 7) & 1, 1, "SW outer corner is a diagonal")
	t.eq((sw >> 4) & 0x3, 0, "0 cuts the (-X,+Z) corner")
	var se: int = MapState.materials[4 * gx + 4]
	t.eq((se >> 7) & 1, 1, "SE outer corner is a diagonal")
	t.eq((se >> 4) & 0x3, 3, "0 cuts the (+X,+Z) corner")
	# Nothing lands on ground nobody painted.
	for ring in [1 * gx + 3, 2 * gx + 1, 5 * gx + 3, 3 * gx + 5, 1 * gx + 1, 5 * gx + 5]:
		t.eq(MapState.materials[ring], 0, "the field around the patch stays clean")
	t.eq(MapState.materials[1 * gx + 1], 0, "kitty-corner background stays solid")

	# Anything a tile cannot blend gets rounded off instead of seaming. A cap
	# blends one edge and a diagonal two adjacent ones, so a painted cell
	# exposed on OPPOSITE sides, or on three, is dropped back to the ground
	# around it: one-cell spurs and one-cell-wide arms round off.
	MapState.materials.fill(0)
	for z in range(2, 6):
		for x in range(2, 6):
			MapState.set_material(x, z, 5)
	MapState.set_material(6, 3, 5)              # a spur: 0 on three sides
	MapState.set_material(3, 6, 5)              # and another
	MapState.rematch_materials_rect(0, 0, 8, 8)
	t.eq(BzMat.fill_of_entry(MapState.materials[3 * gx + 6]), 0, "a one-cell spur rounds off")
	t.eq(BzMat.fill_of_entry(MapState.materials[6 * gx + 3]), 0, "so does the other")
	t.eq(BzMat.fill_of_entry(MapState.materials[3 * gx + 3]), 5, "the body survives")
	# The invariant that buys it: no painted cell is left exposed on a side its
	# own tile cannot reach.
	for z in range(1, 7):
		for x in range(1, 7):
			var m: int = BzMat.fill_of_entry(MapState.materials[z * gx + x])
			var sides := 0
			for side in 4:
				var nx: int = x + (1 if side == 1 else (-1 if side == 3 else 0))
				var nz: int = z + (1 if side == 2 else (-1 if side == 0 else 0))
				if BzMat.fill_of_entry(MapState.materials[nz * gx + nx]) < m:
					sides |= 1 << side
			var n: int = (sides & 1) + ((sides >> 1) & 1) + ((sides >> 2) & 1) + ((sides >> 3) & 1)
			t.ok(n < 3 and sides != 0b0101 and sides != 0b1010,
				"cell %d,%d has no unblendable side (mask %d)" % [x, z, sides])

	var saved_world := MapState.world
	var saved_worlds: Array = MapState.worlds.duplicate(true)
	MapState.world = "mars"
	MapState.worlds = [{
		"id": "mars",
		"atlas_tiles": {
			"MA00SA0.MAP": [0.0, 0.0, 0.125, 0.125],
			"MA01CA0.MAP": [0.5, 0.0, 0.125, 0.125],
			"MA01DA0.MAP": [0.0, 0.125, 0.125, 0.125],
		},
	}]
	MapState.materials.fill(0)
	for z in range(2, 5):
		for x in range(2, 5):
			MapState.set_material(x, z, 5)
	MapState.rematch_materials_rect(1, 1, 5, 5)
	t.eq(MapState.materials[2 * gx + 3], BzMat.encode_entry(5, 5), "no 5↔0 cap in atlas → edge stays solid")
	t.eq(MapState.materials[2 * gx + 2], BzMat.encode_entry(5, 5), "no 5↔0 diagonal → corner stays solid")
	MapState.world = saved_world
	MapState.worlds = saved_worlds

	MapState.mat_grid_x = saved_x
	MapState.mat_grid_z = saved_z
	MapState.materials = saved_mats
	if saved_x > 0 and saved_z > 0:
		MapState.upload_materials()


## A drag lands where a single stamp of the same shape would. The per-dab pass
## is live feedback over a shape that is still moving; `end_paint` re-tiles the
## finished stroke, and only that pass rounds cells off. Drop the settle and a
## dragged stroke keeps whatever each dab guessed on the way past.
func _stroke_settles(t) -> void:
	var saved := {
		"field": MapState.field, "session": MapState.has_session,
		"w": MapState.width_m, "d": MapState.depth_m,
		"gx": MapState.mat_grid_x, "gz": MapState.mat_grid_z,
		"mats": MapState.materials.duplicate(),
		"kind": ToolState.paint_kind, "mat": ToolState.paint_material,
		"match": ToolState.paint_match_edges,
	}
	var field := HeightField.new()
	field.grid_x = 64
	field.grid_z = 64
	field.heights.resize(64 * 64)
	field.heights.fill(200)
	MapState.field = field
	MapState.has_session = true
	MapState.width_m = 64 * int(HeightField.CELL_M)
	MapState.depth_m = 64 * int(HeightField.CELL_M)
	MapState.clear_selection()
	MapState.mat_grid_x = 16
	MapState.mat_grid_z = 16
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(16 * 16)
	MapState.materials.fill(0)
	ToolState.set_paint_kind("solid")
	ToolState.set_paint_material(5)
	ToolState.paint_match_edges = true

	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "paint"
	sculpt.radius_m = 45.0
	sculpt.strength = 1.0
	sculpt.falloff = 1.0
	sculpt.shape = "circle"
	sculpt.paint_material = 5
	sculpt.begin_stroke(field, 120.0, 120.0, true)
	for i in 5:
		sculpt.stamp(field, 120.0 + float(i) * 22.0, 120.0 + float(i) * 14.0)
	# Then a thin tail, one tile wide — exposed on opposite sides, which no
	# tile can show. A dab has no way to know the stroke stops here; the
	# settle does.
	sculpt.radius_m = 9.0
	for i in range(1, 4):
		sculpt.stamp(field, 236.0 + float(i) * 21.0, 190.0 + float(i) * 21.0)
	sculpt.end_paint()
	var dragged: PackedInt32Array = MapState.materials.duplicate()

	# Same fills, tiled in one pass.
	var fills := PackedInt32Array()
	fills.resize(dragged.size())
	for i in dragged.size():
		fills[i] = BzMat.fill_of_entry(dragged[i])
	MapState.materials.fill(0)
	for z in 16:
		for x in 16:
			MapState.set_material(x, z, fills[z * 16 + x])
	MapState.rematch_materials_rect(0, 0, 16, 16)
	t.eq(MapState.materials, dragged, "a drag lands where one stamp of the same shape would")

	var painted := 0
	for i in dragged.size():
		if BzMat.fill_of_entry(dragged[i]) != 0:
			painted += 1
	t.ok(painted > 20, "the stroke actually painted something (%d tiles)" % painted)
	# And nothing it left behind can seam.
	for z in range(1, 15):
		for x in range(1, 15):
			var m: int = BzMat.fill_of_entry(dragged[z * 16 + x])
			var sides := 0
			for side in 4:
				var nx: int = x + (1 if side == 1 else (-1 if side == 3 else 0))
				var nz: int = z + (1 if side == 2 else (-1 if side == 0 else 0))
				if BzMat.fill_of_entry(dragged[nz * 16 + nx]) < m:
					sides |= 1 << side
			var n: int = (sides & 1) + ((sides >> 1) & 1) + ((sides >> 2) & 1) + ((sides >> 3) & 1)
			t.ok(n < 3 and sides != 0b0101 and sides != 0b1010,
				"stroke cell %d,%d has no unblendable side (mask %d)" % [x, z, sides])

	MapState.field = saved["field"]
	MapState.has_session = saved["session"]
	MapState.width_m = saved["w"]
	MapState.depth_m = saved["d"]
	MapState.mat_grid_x = saved["gx"]
	MapState.mat_grid_z = saved["gz"]
	MapState.materials = saved["mats"]
	ToolState.set_paint_kind(saved["kind"])
	ToolState.set_paint_material(saved["mat"])
	ToolState.paint_match_edges = saved["match"]


## The corner rule against a real hand-corrected stroke.
##
## The operator painted one stroke, then fixed its caps and corners by hand;
## FILL is the shape they painted and WANT is what they wanted it tiled as.
## The four-neighbour rule that preceded this managed 73% of these tiles. The
## corner rule gets every one except the two marked, which are the tip of the
## two-cell spur — there they paired diagonals to round it off where the rule
## lays two flat caps.
##
## Shape and tiles only; no game asset is reproduced here.
func _corrected_stroke(t) -> void:
	const FILL := [
		"...............",
		"...........##..",
		"..........####.",
		"..##......####.",
		".####.....####.",
		".####.....####.",
		".#####...#####.",
		"..###########..",
		"..###########..",
		"...#########...",
		".....####......",
		"...............",
	]
	const WANT := [
		"..............................",
		"......................C2C2....",
		"....................C1####C3..",
		"....D1D2............C1####C3..",
		"..C1####C3..........C1####C3..",
		"..C1####D2..........D1####C3..",
		"..C1######D2......D1######C3..",
		"....D0######D2C2D1######D3....",
		"....C1##################C3....",
		"......C0D0########D3C0C0......",
		"..........C0C0C0C0............",
		"..............................",
	]
	# The two the rule knowingly misses: the 2-wide spur tip at the top left.
	const SPUR_TIP := [Vector2i(2, 3), Vector2i(3, 3)]
	var w: int = FILL[0].length()
	var h: int = FILL.size()
	var fill := PackedInt32Array()
	fill.resize(w * h)
	for z in h:
		for x in w:
			fill[z * w + x] = 1 if FILL[z][x] == "#" else 0
	var checked := 0
	var missed := 0
	for z in h:
		for x in w:
			if fill[z * w + x] == 0:
				continue
			var sm: int = fill[z * w + x]
			var got: int = BzMat.autotile_neighbors(
				sm,
				_cell(fill, w, h, x, z - 1, sm), _cell(fill, w, h, x + 1, z - 1, sm),
				_cell(fill, w, h, x + 1, z, sm), _cell(fill, w, h, x + 1, z + 1, sm),
				_cell(fill, w, h, x, z + 1, sm), _cell(fill, w, h, x - 1, z + 1, sm),
				_cell(fill, w, h, x - 1, z, sm), _cell(fill, w, h, x - 1, z - 1, sm)
			)
			var want: String = WANT[z].substr(x * 2, 2)
			var have := _tile_symbol(got)
			if SPUR_TIP.has(Vector2i(x, z)):
				if have != want:
					missed += 1
				continue
			checked += 1
			t.eq(have, want, "stroke cell %d,%d" % [x, z])
	t.ok(checked > 60, "the fixture actually exercised the rule (%d cells)" % checked)
	t.eq(missed, 2, "the spur tip is the only place the rule is known to differ")


func _cell(fill: PackedInt32Array, w: int, h: int, x: int, z: int, fallback: int) -> int:
	if x < 0 or z < 0 or x >= w or z >= h:
		return fallback
	return fill[z * w + x]


func _tile_symbol(word: int) -> String:
	var a: int = (word >> 12) & 0xF
	var b: int = (word >> 8) & 0xF
	if a == b:
		return ".." if a == 0 else "##"
	return "%s%d" % ["D" if ((word >> 7) & 1) else "C", (word >> 4) & 3]
