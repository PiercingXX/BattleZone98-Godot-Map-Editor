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

	MapState.mat_grid_x = saved_x
	MapState.mat_grid_z = saved_z
	MapState.materials = saved_mats
	if saved_x > 0 and saved_z > 0:
		MapState.upload_materials()
