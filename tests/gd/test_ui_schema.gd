extends RefCounted
## Schema-driven property editors: normalization, typed editors, round-trip,
## change signals, clamping, rerolls.

const BRUSH := {
	"radius_m": {
		"type": TYPE_FLOAT,
		"range": {"min": 5.0, "max": 200.0, "step": 1.0},
		"default": 40.0,
		"suffix": "m",
		"label": "Radius",
		"doc": "Footprint of the stamp on the heightfield.",
		"warning": "Above 120 m a stroke rebuilds several clipmap rings.",
		"cost": PropertySchema.COST_MODERATE,
	},
	"strength": {
		"type": TYPE_FLOAT,
		"range": {"min": 0.0, "max": 1.0, "step": 0.05},
		"default": 0.45,
	},
	"grow_cells": {
		"type": TYPE_INT,
		"range": {"min": 1, "max": 64, "step": 1},
		"default": 1,
		"suffix": "cells",
	},
	"clone_materials": {"type": TYPE_BOOL, "default": false},
	"symmetry": {
		"type": TYPE_STRING,
		"usage": PropertySchema.USAGE_ENUM,
		"object_type": ["off", "mirror_x", "mirror_z", "rot180", "quad"],
		"default": "off",
	},
	"shape_id": {
		"type": TYPE_INT,
		"usage": PropertySchema.USAGE_ENUM,
		"object_type": ["Circle", "Square"],
		"default": 0,
	},
	"label": {"type": TYPE_STRING, "default": ""},
	"notes": {
		"type": TYPE_STRING,
		"usage": PropertySchema.USAGE_MULTILINE,
		"default": "",
	},
	"source_bzn": {
		"type": TYPE_STRING,
		"usage": PropertySchema.USAGE_FILE,
		"object_type": ["*.bzn ; BZN maps"],
		"default": "",
	},
	"slope_band": {
		"type": TYPE_VECTOR2,
		"usage": PropertySchema.USAGE_BAND,
		"range": {"min": 0.0, "max": 90.0, "step": 1.0},
		"default": Vector2(12.0, 34.0),
		"suffix": "deg",
	},
	"grid_size": {
		"type": TYPE_VECTOR2I,
		"range": {"min": 16, "max": 512, "step": 16},
		"default": Vector2i(256, 256),
	},
	"origin": {"type": TYPE_VECTOR3, "default": Vector3.ZERO},
	"tint": {"type": TYPE_COLOR, "default": Color(0.2, 0.4, 0.6, 1)},
	"seed": {
		"type": TYPE_INT,
		"usage": PropertySchema.USAGE_SEED,
		"default": 0,
		"randomizable": true,
	},
}


func run(t) -> void:
	_normalization(t)
	_editor_types(t)
	_round_trip(t)
	await _change_signal(t)
	_clamping(t)
	_randomize(t)
	_validation(t)


func _normalization(t) -> void:
	var norm := PropertySchema.normalize(BRUSH)
	t.eq(norm.size(), BRUSH.size(), "every entry normalizes")
	t.eq(norm.keys()[0], "radius_m", "declaration order is preserved")
	var radius: Dictionary = norm["radius_m"]
	t.eq(radius["label"], "Radius", "explicit label wins")
	t.ok(radius["bounded"], "min+max marks the entry bounded")
	t.eq(radius["cost"], PropertySchema.COST_MODERATE)
	t.eq(norm["grow_cells"]["label"], "Grow cells", "label inferred from key")
	t.eq(norm["strength"]["cost"], PropertySchema.COST_LIGHT, "cost defaults")
	t.ok(not norm["origin"]["bounded"], "no range means unbounded")
	t.eq(norm["radius_m"]["usage"], PropertySchema.USAGE_PLAIN)
	t.ok(PropertySchema.tooltip_for(radius).contains("Warning:"),
		"tooltip carries the warning")
	t.ok(PropertySchema.range_text(radius).contains("200"),
		"range text names the ceiling")
	t.eq(PropertySchema.range_text(norm["origin"]), "",
		"unbounded has no range text")
	var defaults := PropertySchema.defaults(norm)
	t.near(float(defaults["radius_m"]), 40.0, 0.001)
	t.eq(defaults["symmetry"], "off")
	t.eq(defaults["grid_size"], Vector2i(256, 256))
	# Normalizing twice must not shift anything.
	var twice := PropertySchema.normalize(norm)
	t.eq(twice["radius_m"]["default"], norm["radius_m"]["default"])

	var items := PropertySchema.enum_items(norm["shape_id"])
	t.eq(items.size(), 2)
	t.eq(items[1]["label"], "Square")
	t.eq(items[1]["value"], 1, "int enum values are indices")
	t.eq(PropertySchema.enum_items(norm["symmetry"])[2]["value"], "mirror_z",
		"string enum values are the names")


func _editor_types(t) -> void:
	var grid := PropertyGrid.make(BRUSH)
	t.eq(grid.columns, 2, "label plus editor per row")
	t.eq(grid.keys().size(), BRUSH.size())
	t.ok(grid.editor_for("radius_m") is SpinSlider, "float -> SpinSlider")
	t.ok(grid.editor_for("grow_cells") is SpinSlider, "int -> SpinSlider")
	t.ok(grid.editor_for("grow_cells").spin_box().rounded, "int spin is rounded")
	t.ok(grid.editor_for("clone_materials") is CheckBox, "bool -> CheckBox")
	t.ok(grid.editor_for("symmetry") is OptionButton, "enum -> OptionButton")
	t.ok(grid.editor_for("shape_id") is OptionButton, "int enum -> OptionButton")
	t.eq(grid.editor_for("shape_id").item_count, 2)
	t.ok(grid.editor_for("label") is LineEdit, "String -> LineEdit")
	t.ok(grid.editor_for("notes") is TextEdit, "multiline -> TextEdit")
	t.ok(grid.editor_for("source_bzn").get_node_or_null("Path") is LineEdit,
		"file -> path field")
	t.ok(grid.editor_for("source_bzn").get_node_or_null("Browse") is Button,
		"file -> browse button")
	t.ok(grid.editor_for("slope_band") is RangeSlider, "band -> RangeSlider")
	t.ok(grid.editor_for("grid_size") is HBoxContainer, "Vector2i -> axis row")
	t.eq(grid.editor_for("grid_size").get_child_count(), 2)
	t.eq(grid.editor_for("origin").get_child_count(), 3, "Vector3 -> 3 axes")
	t.ok(grid.editor_for("tint") is ColorPickerButton, "Color -> picker")
	t.eq(grid.label_for("radius_m").text, "Radius")
	t.ok(grid.label_for("radius_m").tooltip_text.contains("Footprint"),
		"the label documents itself from the schema")
	t.ok(grid.find_child("Random_seed", true, false) is Button,
		"randomizable entries get a reroll button")
	t.ok(grid.find_child("Random_radius_m", true, false) == null,
		"non-randomizable entries do not")
	# Defaults are installed at build time.
	t.near(float(grid.get_value("radius_m")), 40.0, 0.001)
	t.eq(grid.get_value("symmetry"), "off")
	t.eq(grid.get_value("slope_band"), Vector2(12.0, 34.0))
	grid.free()


func _round_trip(t) -> void:
	var grid := PropertyGrid.make(BRUSH)
	var want := {
		"radius_m": 85.0,
		"strength": 0.75,
		"grow_cells": 12,
		"clone_materials": true,
		"symmetry": "quad",
		"shape_id": 1,
		"label": "outpost",
		"notes": "two\nlines",
		"source_bzn": "user://x.bzn",
		"slope_band": Vector2(20.0, 55.0),
		"grid_size": Vector2i(128, 64),
		"origin": Vector3(1.5, 2.5, 3.5),
		"tint": Color(0.1, 0.2, 0.3, 1.0),
		"seed": 991,
	}
	grid.set_values(want)
	var got := grid.get_values()
	t.eq(got.size(), want.size(), "get_values covers every key")
	for key in want.keys():
		_same(t, got[key], want[key], "round-trip %s" % key)
	# A second round-trip through the same dict is stable.
	grid.set_values(got)
	var again := grid.get_values()
	for key in want.keys():
		_same(t, again[key], got[key], "stable %s" % key)
	grid.reset_to_defaults()
	t.near(float(grid.get_value("radius_m")), 40.0, 0.001, "reset restores default")
	t.eq(grid.get_value("symmetry"), "off")
	grid.free()


func _change_signal(t) -> void:
	# Godot 4.7 only emits Range.value_changed for a node inside the tree, so
	# the signal path has to be exercised attached, exactly as a panel runs.
	var grid := PropertyGrid.make(BRUSH)
	t.tree.root.add_child(grid)
	await t.tree.process_frame
	var seen: Array = []
	grid.property_changed.connect(
		func(key: String, value: Variant) -> void: seen.append([key, value])
	)
	grid.set_values({"radius_m": 60.0})
	t.eq(seen.size(), 0, "scripted sync is not a user edit")

	grid.editor_for("radius_m").spin_box().value = 90.0
	t.eq(seen.size(), 1, "editing the spinbox reports once")
	t.eq(seen[0][0], "radius_m", "signal names the key")
	t.near(float(seen[0][1]), 90.0, 0.001, "signal carries the new value")
	t.near(float(grid.editor_for("radius_m").slider().value), 90.0, 0.001,
		"slider follows the spinbox")

	seen.clear()
	grid.editor_for("clone_materials").button_pressed = true
	t.eq(seen.size(), 1)
	t.eq(seen[0][0], "clone_materials")
	t.eq(seen[0][1], true)

	seen.clear()
	grid.editor_for("shape_id").selected = 1
	grid.editor_for("shape_id").item_selected.emit(1)
	t.eq(seen.size(), 1)
	t.eq(seen[0][1], 1, "enum reports its value, not its row")

	seen.clear()
	grid.editor_for("slope_band").set_band_notify(30.0, 10.0)
	t.eq(seen.size(), 1)
	t.eq(seen[0][1], Vector2(10.0, 30.0), "band reports sorted")

	seen.clear()
	grid.set_value("label", "hq", true)
	t.eq(seen.size(), 1, "set_value can opt into notifying")
	t.eq(seen[0][1], "hq")
	grid.queue_free()


func _clamping(t) -> void:
	var grid := PropertyGrid.make(BRUSH)
	grid.set_value("radius_m", 9999.0)
	t.near(float(grid.get_value("radius_m")), 200.0, 0.001, "clamped to max")
	grid.set_value("radius_m", -50.0)
	t.near(float(grid.get_value("radius_m")), 5.0, 0.001, "clamped to min")
	grid.set_value("grow_cells", 999)
	t.eq(grid.get_value("grow_cells"), 64, "int clamped to max")
	grid.set_value("grow_cells", 7.6)
	t.eq(grid.get_value("grow_cells"), 8, "float input rounds into an int field")
	grid.set_value("strength", 0.123)
	t.near(float(grid.get_value("strength")), 0.1, 0.001, "snapped to step")
	grid.set_value("slope_band", Vector2(-10.0, 200.0))
	t.eq(grid.get_value("slope_band"), Vector2(0.0, 90.0), "band clamped")
	grid.set_value("symmetry", "nonsense")
	t.eq(grid.get_value("symmetry"), "off", "unknown enum falls back")
	grid.set_value("grid_size", Vector2i(9999, 1))
	t.eq(grid.get_value("grid_size"), Vector2i(512, 16), "vector clamped per axis")
	grid.free()

	var entry := PropertySchema.normalize_entry("radius_m", BRUSH["radius_m"])
	t.near(float(PropertySchema.coerce(entry, 1e9)), 200.0, 0.001)
	t.near(float(PropertySchema.coerce(entry, "73")), 73.0, 0.001,
		"a string coerces into a float field")
	var coerced := PropertySchema.coerce_values(BRUSH, {"radius_m": 500.0})
	t.near(float(coerced["radius_m"]), 200.0, 0.001)
	t.eq(coerced["symmetry"], "off", "missing keys take their default")
	t.ok(not coerced.has("bogus"), "unknown keys are dropped")


func _randomize(t) -> void:
	var grid := PropertyGrid.make(BRUSH)
	var seen: Array = []
	grid.property_changed.connect(
		func(key: String, value: Variant) -> void: seen.append([key, value])
	)
	grid.set_random_seed(12345)
	grid.randomize_key("seed")
	t.eq(seen.size(), 1, "a reroll reports like an edit")
	t.eq(seen[0][0], "seed")
	var first: Variant = grid.get_value("seed")
	grid.set_random_seed(12345)
	grid.randomize_key("seed")
	t.eq(grid.get_value("seed"), first, "same seed, same reroll (C6)")
	seen.clear()
	grid.randomize_key("radius_m")
	t.eq(seen.size(), 0, "non-randomizable entries ignore the request")
	grid.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var entry := PropertySchema.normalize_entry("radius_m", BRUSH["radius_m"])
	for i in 20:
		var v := float(PropertySchema.random_value(entry, rng))
		t.ok(v >= 5.0 and v <= 200.0, "reroll stays inside the range")


func _validation(t) -> void:
	t.eq(PropertySchema.validate(BRUSH).size(), 0, "the sample schema is clean")
	var bad := {
		"a": {"range": {"min": 1, "max": 0}},
		"b": "not a dictionary",
		"c": {"type": TYPE_INT, "usage": PropertySchema.USAGE_ENUM},
	}
	var problems := PropertySchema.validate(bad)
	t.eq(problems.size(), 4, "every fault is named")
	t.ok(str(problems).contains("no type"))
	t.ok(str(problems).contains("not a Dictionary"))
	t.ok(str(problems).contains("enum usage"))
	t.ok(str(problems).contains("min above max"))


func _same(t, got: Variant, want: Variant, msg: String) -> void:
	if typeof(want) == TYPE_FLOAT:
		t.near(float(got), float(want), 0.001, msg)
	elif typeof(want) == TYPE_VECTOR2:
		t.near((got as Vector2).distance_to(want), 0.0, 0.001, msg)
	elif typeof(want) == TYPE_VECTOR3:
		t.near((got as Vector3).distance_to(want), 0.0, 0.001, msg)
	elif typeof(want) == TYPE_COLOR:
		var a: Color = got
		var b: Color = want
		t.near(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b), 0.0,
			0.004, msg)
	else:
		t.eq(got, want, msg)
