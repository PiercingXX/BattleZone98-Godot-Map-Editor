extends RefCounted
## Tier 1 MapValidator against synthetic map directories.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz-fmt-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_write_clean_map(tmp, "synth")

	var clean: PackedStringArray = BzCheckFormats.validate_map(tmp)
	t.eq(clean.size(), 0, "clean map has zero findings: %s" % " | ".join(clean))

	# Ground-snap: lift the player 10 m off the terrain.
	var snap_dir: String = tmp + "-snap"
	DirAccess.make_dir_recursive_absolute(snap_dir)
	_write_clean_map(snap_dir, "synth", 110.0)
	var snap: PackedStringArray = BzCheckFormats.validate_map(snap_dir)
	t.ok("\n".join(snap).contains("from terrain height"), "ground snap: %s" % " | ".join(snap))

	# BZN invariant: two players.
	var two_dir: String = tmp + "-two"
	DirAccess.make_dir_recursive_absolute(two_dir)
	_write_clean_map(two_dir, "synth")
	_write_text(
		two_dir.path_join("synth.bzn"),
		_bzn_text("synth", 100.0, true)
	)
	var two: PackedStringArray = BzCheckFormats.validate_map(two_dir)
	t.ok("\n".join(two).contains("expected exactly one player"), " | ".join(two))

	# Missing terrain file implied by the BZN.
	var miss: String = tmp + "-miss"
	DirAccess.make_dir_recursive_absolute(miss)
	_write_text(miss.path_join("synth.bzn"), _bzn_text("synth", 100.0, false))
	var mp: PackedStringArray = BzCheckFormats.validate_map(miss)
	t.ok("\n".join(mp).contains("terrain file <synth.trn>"), " | ".join(mp))
	t.ok("\n".join(mp).contains("terrain file <synth.hg2>"), " | ".join(mp))
	t.ok("\n".join(mp).contains("terrain file <synth.mat>"), " | ".join(mp))

	# DES / _S count mismatch + ini maxPlayers.
	var xdir: String = tmp + "-cross"
	DirAccess.make_dir_recursive_absolute(xdir)
	_write_clean_map(xdir, "synth")
	_write_text(xdir.path_join("synth_S.bzn"), _bzn_text("synth_S", 100.0, false))
	_write_text(xdir.path_join("synth.des"), "WORLD: mars\tSIZE: Small\r\nGEYSERS: 9\tSCRAP: 0\r\n")
	_write_text(
		xdir.path_join("synth.ini"),
		"[MULTIPLAYER]\nmaxPlayers = 0\n"
	)
	# Add a deathmatch spawn to the base BZN so maxPlayers 0 fails.
	_write_text(xdir.path_join("synth.bzn"), _bzn_text("synth", 100.0, false, true))
	var xp: PackedStringArray = BzCheckFormats.validate_map(xdir)
	var xj := "\n".join(xp)
	t.ok(xj.contains("states 9 GEYSERS"), xj)
	t.ok(xj.contains("maxPlayers 0 is less than"), xj)

	# Terrain-name collision against a fake reference tree.
	var ref: String = tmp + "-ref"
	DirAccess.make_dir_recursive_absolute(ref.path_join("edit"))
	_write_text(ref.path_join("edit").path_join("synth.trn"), "[Size]\n")
	var col: PackedStringArray = BzCheckFormats.validate_map(tmp, ref)
	t.ok("\n".join(col).contains("collides with an installed terrain"), " | ".join(col))

	# Module wrapper + class constructor agree.
	var via_new: PackedStringArray = BzCheckFormats.new(tmp).validate()
	t.eq(via_new.size(), 0)
	t.eq(BzCheckFormats.SPAWN_CLASS, "pspwn_1")
	t.eq(BzCheckFormats.GROUND_SNAP_TOLERANCE_M, 1.5)


func _write_clean_map(dir: String, stem: String, player_y: float = 100.0) -> void:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(1000)
	var hm := BzHg2.HeightMap.new(1, 1, data)
	var wr: Dictionary = hm.write(dir.path_join("%s.hg2" % stem))
	if not wr.get("ok", false):
		push_error("hg2 write failed")
	var mat := PackedByteArray()
	mat.resize(64 * 64 * 2)
	var mf := FileAccess.open(dir.path_join("%s.mat" % stem), FileAccess.WRITE)
	mf.store_buffer(mat)
	mf.close()
	_write_text(dir.path_join("%s.trn" % stem), "[Size]\r\nWidth = 1280\r\nDepth = 1280\r\n")
	_write_text(dir.path_join("%s.bzn" % stem), _bzn_text(stem, player_y, false))


func _bzn_text(stem: String, player_y: float, two_players: bool, with_spawn: bool = false) -> String:
	var n: int = 1
	if two_players:
		n += 1
	if with_spawn:
		n += 1
	var parts: PackedStringArray = PackedStringArray([
		"version [1] =",
		"2016",
		"binarySave [1] =",
		"false",
		"msn_filename = %s.bzn" % stem,
		"seq_count [1] =",
		str(n),
		"missionSave [1] =",
		"true",
		"TerrainName = %s" % stem,
		"size [1] =",
		str(n),
	])
	parts.append_array(_object_block("player", 0, 1, 640.0, player_y, 640.0, 1, true))
	var seq := 1
	var addr := 2
	if two_players:
		parts.append_array(_object_block("player", seq, addr, 650.0, player_y, 650.0, 1, false))
		seq += 1
		addr += 1
	if with_spawn:
		parts.append_array(_object_block("pspwn_1", seq, addr, 600.0, 100.0, 600.0, 0, false))
	parts.append_array(PackedStringArray([
		"[AiMission]",
		"[AOIs]",
		"size [1] =",
		"0",
		"[AiPaths]",
		"count [1] =",
		"0",
	]))
	return "\r\n".join(parts) + "\r\n"


func _object_block(
	prjid: String, seq: int, addr: int, x: float, y: float, z: float, team: int, is_user: bool
) -> PackedStringArray:
	return PackedStringArray([
		"[GameObject]",
		"PrjID [1] =",
		prjid,
		"seqno [1] =",
		str(seq),
		"pos [1] =",
		"  x [1] =",
		str(x),
		"  y [1] =",
		str(y),
		"  z [1] =",
		str(z),
		"team [1] =",
		str(team),
		"label = %s%d_%s" % ["synth", seq, prjid],
		"isUser [1] =",
		"1" if is_user else "0",
		"obj_addr = %08x" % addr,
		"transform [1] =",
		"  right_x [1] =",
		"1",
		"  right_y [1] =",
		"0",
		"  right_z [1] =",
		"0",
		"  up_x [1] =",
		"0",
		"  up_y [1] =",
		"1",
		"  up_z [1] =",
		"0",
		"  front_x [1] =",
		"0",
		"  front_y [1] =",
		"0",
		"  front_z [1] =",
		"1",
		"  posit_x [1] =",
		str(x),
		"  posit_y [1] =",
		str(y),
		"  posit_z [1] =",
		str(z),
		"illumination [1] =",
		"0",
		"pos [1] =",
		"  x [1] =",
		str(x),
		"  y [1] =",
		str(y),
		"  z [1] =",
		str(z),
		"seqNo [1] =",
		str(seq),
		"name = ",
	])


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(text.to_utf8_buffer())
	f.close()
