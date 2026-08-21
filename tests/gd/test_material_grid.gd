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

	MapState.mat_grid_x = saved_x
	MapState.mat_grid_z = saved_z
	MapState.materials = saved_mats
	if saved_x > 0 and saved_z > 0:
		MapState.upload_materials()
