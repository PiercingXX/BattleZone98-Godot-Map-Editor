extends RefCounted
## MapState water writes the docs/02 features.json shape.


func run(t) -> void:
	var saved_feat: Dictionary = MapState.features.duplicate(true)
	var saved_stem: String = MapState.stem
	var saved_unsaved: bool = MapState.unsaved
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	MapState.stem = "testmap"
	MapState.features = {"water": [], "plants": []}
	MapState.set_water_level(92.0)
	t.near(MapState.water_level(), 92.0, 0.001)
	var waters: Array = MapState.features.get("water", [])
	t.eq(waters.size(), 1, "one water feature")
	t.eq(waters[0].get("level_m"), 92.0)
	t.eq(waters[0].get("variant_scope"), "all")
	t.ok(str(waters[0].get("stem", "")).length() <= 8, "stem fits engine 8-char cap")
	t.ok(MapState.unsaved)
	t.eq(MapState.dirty.get("features"), true)
	MapState.set_water_level(-1.0)
	t.eq(MapState.features.get("water"), [])
	t.near(MapState.water_level(), -1.0, 0.001)
	MapState.features = saved_feat
	MapState.stem = saved_stem
	MapState.unsaved = saved_unsaved
	MapState.dirty = saved_dirty
