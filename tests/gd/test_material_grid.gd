extends RefCounted
## set_material word encoding, material_at decode, write_materials_rect clip.


func run(t) -> void:
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
	var north: int = MapState.materials[2 * gx + 3]
	t.eq((north >> 12) & 0xF, 5, "north edge keeps 5")
	t.eq((north >> 8) & 0xF, 0, "north edge meets 0")
	t.eq((north >> 7) & 1, 0, "straight edge is a cap")
	var nw: int = MapState.materials[2 * gx + 2]
	t.eq((nw >> 12) & 0xF, 5, "NW corner keeps 5")
	t.eq((nw >> 8) & 0xF, 0)
	t.eq((nw >> 7) & 1, 1, "NW outer corner is a diagonal")
	t.eq(MapState.materials[1 * gx + 1], 0, "kitty-corner background stays solid")
	MapState.materials.fill(0)
	for x in range(2, 5):
		MapState.set_material(x, 2, 5)
	for z in range(3, 5):
		MapState.set_material(2, z, 5)
	MapState.rematch_materials_rect(1, 1, 5, 5)
	var bite: int = MapState.materials[3 * gx + 3]
	t.eq((bite >> 12) & 0xF, 0, "L-shape inner corner stays the background")
	t.eq((bite >> 8) & 0xF, 5)
	t.eq((bite >> 7) & 1, 1, "L-shape inner corner is a diagonal")

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
