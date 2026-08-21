extends RefCounted
## MapState object / class lookups stay correct after assign, add, remove.


func run(t) -> void:
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_index: Dictionary = MapState.asset_index.duplicate(true)

	MapState.objects = {
		"": [
			{"id": "dm-1", "prjid": "player", "x": 1.0},
			{"id": "dm-2", "prjid": "npscr1", "x": 2.0},
		],
		"_S": [
			{"id": "s-1", "prjid": "avtank", "x": 3.0},
		],
	}
	t.eq(str(MapState.find_object("dm-2").get("prjid", "")), "npscr1", "lookup after assign")
	t.eq(MapState.find_object_variant("s-1"), "_S", "variant after assign")
	t.eq(MapState.find_object("missing"), {}, "missing id")

	MapState.add_object_record("_ST", {"id": "st-1", "prjid": "eggeizr1"})
	t.eq(MapState.find_object_variant("st-1"), "_ST", "add updates index")
	t.eq(str(MapState.find_object("st-1").get("prjid", "")), "eggeizr1")

	MapState.remove_object_record("_ST", "st-1")
	t.eq(MapState.find_object("st-1"), {}, "remove drops index")
	t.eq(MapState.find_object_variant("dm-1"), "", "other ids survive remove")

	MapState.asset_index = {
		"classes": [
			{"prjid": "AvTank", "category": "craft", "height_m": 4.0},
			{"prjid": "player", "category": "craft"},
		],
	}
	MapState.rebuild_lookups()
	t.eq(str(MapState.class_info("avtank").get("prjid", "")), "AvTank", "class lookup is case-insensitive")
	t.eq(str(MapState.class_info("player").get("category", "")), "craft")
	t.eq(MapState.class_info("nope"), {}, "unknown class")

	MapState.objects = saved_objects
	MapState.asset_index = saved_index
	MapState.rebuild_lookups()
