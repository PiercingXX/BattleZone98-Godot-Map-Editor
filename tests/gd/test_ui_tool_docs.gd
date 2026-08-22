extends RefCounted
## Self-documenting tools: one declaration feeds both the editors and the
## prose, the registry is searchable, and everything renders with no game
## installed (C15).

const RAISE_SCHEMA := {
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
		"doc": "Metres of lift at the centre of one stamp.",
		"cost": PropertySchema.COST_TRIVIAL,
	},
	"seed": {
		"type": TYPE_INT,
		"usage": PropertySchema.USAGE_SEED,
		"default": 0,
		"randomizable": true,
		"doc": "Reroll to get a different noise pattern.",
	},
}


func run(t) -> void:
	ToolDocs.clear()
	_model(t)
	_rendering(t)
	_registry(t)
	_shared_declaration(t)
	_view(t)
	await _section(t)
	ToolDocs.clear()


func _doc() -> ToolDoc:
	return ToolDoc.make(
		"raise", "Raise", "Sculpt",
		"Pushes terrain up under the brush, weighted by the falloff.",
		RAISE_SCHEMA, "R", PropertySchema.COST_MODERATE
	)


func _model(t) -> void:
	var doc := _doc()
	t.eq(doc.id, "raise")
	t.eq(doc.title(), "Raise")
	t.eq(doc.category, "Sculpt")
	t.ok(doc.description.contains("falloff"))
	t.ok(doc.header_line().contains("Sculpt"), "header names the category")
	t.ok(doc.header_line().contains("R"), "header names the shortcut")
	t.ok(doc.header_line().contains("moderate"), "header names the cost")

	var params := doc.params()
	t.eq(params.size(), 3, "one row per schema entry")
	t.eq(params[0]["key"], "radius_m", "declaration order survives")
	t.eq(params[0]["label"], "Radius")
	t.eq(params[0]["type_name"], "float")
	t.ok(str(params[0]["range_text"]).contains("200"))
	t.eq(params[0]["cost"], PropertySchema.COST_MODERATE)
	t.eq(params[0]["cost_order"], 2)
	t.ok(str(params[0]["warning"]).contains("clipmap"))
	t.ok(params[2]["randomizable"], "the seed advertises its reroll")
	t.eq(doc.param("strength")["type_name"], "float")
	t.eq(doc.param("nope").size(), 0, "unknown parameter is empty, not an error")
	t.eq(doc.undocumented_params().size(), 0, "every parameter has prose")

	var thin := ToolDoc.make("thin", "Thin", "Sculpt", "",
		{"x": {"type": TYPE_INT}})
	t.eq(thin.undocumented_params().size(), 1, "a bare entry is reported")
	t.eq(thin.undocumented_params()[0], "x")


func _rendering(t) -> void:
	var doc := _doc()
	var bb := doc.to_bbcode()
	t.ok(bb.contains("[b]Raise[/b]"), "bbcode titles the tool")
	t.ok(bb.contains("Radius"), "bbcode lists the parameters")
	t.ok(bb.contains("Warning:"), "bbcode carries the caveat")
	t.ok(bb.contains("cost: moderate"))
	var md := doc.to_markdown()
	t.ok(md.contains("### Raise"))
	t.ok(md.contains("| Parameter | Type | Range | Default | Cost | Notes |"))
	t.ok(md.contains("`radius_m`"))
	t.ok(md.contains("**Warning:**"))
	var bare := ToolDoc.make("bare", "Bare", "Misc", "No knobs.")
	t.ok(not bare.to_markdown().contains("| Parameter |"),
		"a tool with no parameters gets no table")

	t.ok(doc.matches("clipmap"), "search reaches parameter warnings")
	t.ok(doc.matches("SCULPT"), "search is case-insensitive")
	t.ok(doc.matches(""), "an empty query matches everything")
	t.ok(not doc.matches("tunnel"))


func _registry(t) -> void:
	ToolDocs.clear()
	t.eq(ToolDocs.size(), 0)
	var raise := ToolDocs.register(_doc())
	ToolDocs.register(ToolDoc.make("place", "Place", "Objects",
		"Drops the armed prefab on the terrain.", {}, "P"))
	ToolDocs.register(ToolDoc.make("water", "Water", "Features",
		"Edits the water plane."))
	t.eq(ToolDocs.size(), 3)
	t.eq(ToolDocs.get_doc("raise"), raise)
	t.ok(ToolDocs.has("place"))
	t.eq(ToolDocs.get_doc("missing"), null, "an absent id is null, not a crash")
	t.eq(ToolDocs.categories().size(), 3)
	t.eq(ToolDocs.categories()[0], "Sculpt", "categories keep first-seen order")
	t.eq(ToolDocs.in_category("Objects").size(), 1)

	ToolDocs.register(ToolDoc.make("raise", "Raise II", "Sculpt", "Reloaded."))
	t.eq(ToolDocs.size(), 3, "re-registering replaces rather than duplicates")
	t.eq(ToolDocs.get_doc("raise").title(), "Raise II")

	t.eq(ToolDocs.search("prefab").size(), 1, "search spans the registry")
	t.eq(ToolDocs.search("prefab")[0].id, "place")
	t.eq(ToolDocs.search("").size(), 3)
	var manual := ToolDocs.manual_markdown()
	t.ok(manual.contains("# Tool reference"))
	t.ok(manual.contains("## Sculpt"))
	t.ok(manual.contains("### Place"))
	t.ok(manual.contains("### Water"))
	var help := ToolDocs.to_bbcode("prefab")
	t.ok(help.contains("Place"), "filtered help keeps the hit")
	t.ok(not help.contains("Water"), "filtered help drops the rest")
	ToolDocs.clear()
	t.eq(ToolDocs.size(), 0)


func _shared_declaration(t) -> void:
	# The point of the exercise: docs and editors come from one dictionary, so
	# a parameter cannot exist in one and not the other.
	var doc := _doc()
	var grid := PropertyGrid.make(doc.schema)
	t.eq(grid.keys().size(), doc.params().size(),
		"every documented parameter has an editor")
	for p in doc.params():
		t.ok(grid.has_key(str(p["key"])), "%s is editable" % p["key"])
		t.ok(grid.label_for(str(p["key"])).tooltip_text.contains(
			str(p["description"])), "%s documents itself on hover" % p["key"])
	t.near(float(grid.get_value("radius_m")), 40.0, 0.001,
		"the declared default is what the editor starts at")
	grid.free()


func _view(t) -> void:
	var doc := _doc()
	var compact := ToolDocView.make(doc)
	t.ok(compact.body_text().contains("falloff"), "prose renders")
	t.ok(compact.get_node("Meta").text.contains("Sculpt"))
	t.eq(compact.get_node("Params").get_child_count(), 0,
		"compact leaves per-parameter detail to the tooltips")
	compact.set_compact(false)
	t.eq(compact.get_node("Params").get_child_count(), 3,
		"expanded documents every parameter")
	var block := compact.get_node("Params").get_child(0)
	t.ok(block.get_node("Head").text.contains("Radius"))
	t.ok(block.get_node("Head").text.contains("cost moderate"))
	t.ok(block.get_node("Body").text.contains("Footprint"))
	t.ok(block.get_node("Warning").text.contains("clipmap"))
	compact.set_doc(null)
	t.eq(compact.get_node("Params").get_child_count(), 0,
		"clearing the doc empties the view")
	compact.free()


func _section(t) -> void:
	var doc := _doc()
	var sec := SchemaSection.make(doc)
	t.tree.root.add_child(sec)
	await t.tree.process_frame
	t.eq(sec.tool_doc(), doc)
	t.ok(sec.header() is SectionHeader)
	t.ok(sec.grid() is PropertyGrid)
	t.ok(sec.docs_view() is ToolDocView)
	t.eq(sec.header().caption, "Raise", "the section titles itself")
	var seen: Array = []
	sec.property_changed.connect(
		func(key: String, value: Variant) -> void: seen.append([key, value])
	)
	sec.grid().editor_for("strength").spin_box().value = 0.8
	t.eq(seen.size(), 1, "the section forwards edits")
	t.eq(seen[0][0], "strength")
	t.near(float(sec.get_values()["strength"]), 0.8, 0.001)
	sec.set_values({"strength": 0.25})
	t.near(float(sec.get_values()["strength"]), 0.25, 0.001)
	t.ok(not sec.is_collapsed())
	sec.set_collapsed(true)
	t.ok(sec.is_collapsed(), "the header collapses the block")
	t.ok(not sec.grid().visible)
	sec.set_collapsed(false)
	t.ok(sec.grid().visible)

	var plain := SchemaSection.from_schema("View", {
		"labels": {"type": TYPE_BOOL, "default": true},
	})
	t.ok(plain.docs_view() == null, "a schema-only section has no prose block")
	t.eq(plain.get_values()["labels"], true)
	plain.free()
	sec.queue_free()
