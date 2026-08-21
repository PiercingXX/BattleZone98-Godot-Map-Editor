extends RefCounted
## Palette: search, arming, brush sliders, shape, swatches, empty/no-session.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_tool := ToolState.tool
	var saved_r := ToolState.radius_m
	var saved_s := ToolState.strength
	var saved_f := ToolState.falloff
	var saved_shape := ToolState.shape
	var saved_mat := ToolState.paint_material
	var saved_sym := ToolState.symmetry
	var saved_armed: Dictionary = ToolState.armed.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_w: int = MapState.width_m
	var saved_d: int = MapState.depth_m
	MapState.has_session = false
	MapState.selected_ids.clear()
	ToolState.clear_armed()
	ToolState.set_tool("fly")
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)

	var pal: Node = load("res://project/ui/palette/PalettePanel.tscn").instantiate()
	t.tree.root.add_child(pal)
	await t.tree.process_frame

	var list: ItemList = pal.find_child("ClassList", true, false)
	t.ok(list.item_count >= 1, "empty placeholder present")
	t.ok(list.is_item_disabled(0), "placeholder disabled")
	t.ok(pal.has_method("set_collapsed"))
	pal.set_collapsed(true)
	t.ok(not (pal.find_child("FlyHint", true, false) as Control).is_visible_in_tree())
	t.ok((pal.find_child("Collapse", true, false) as Button).is_visible_in_tree())
	pal.set_collapsed(false)
	t.ok((pal.find_child("FlyHint", true, false) as Control).is_visible_in_tree())

	var index := {
		"classes": [
			{"prjid": "avapc", "label": "APC", "source": "game", "category": "craft", "placement_mode": "clone", "template_verified": true},
			{"prjid": "player", "label": "Player", "source": "game", "category": "craft", "placement_mode": "clone", "template_verified": false},
			{"prjid": "packonly", "label": "Other", "source": "workshop", "category": "building", "placement_mode": "runtime", "template_verified": true},
		],
	}
	pal.set_classes(index, "base")
	t.eq(list.item_count, 3, "three classes listed")
	var disabled_count := 0
	for i in list.item_count:
		if list.is_item_disabled(i):
			disabled_count += 1
	t.eq(disabled_count, 1, "other-pack class disabled for base maps")

	var armed: Array = []
	pal.class_armed.connect(func(rec): armed.append(rec.get("prjid", "")))
	var player_i := _index_of(list, "player")
	t.ok(player_i >= 0)
	list.item_selected.emit(player_i)
	t.eq(armed, [], "arming refused with no session")

	MapState.has_session = true
	list.item_selected.emit(player_i)
	t.eq(armed, ["player"], "arming works with a session")

	var search: LineEdit = pal.find_child("Search", true, false)
	search.text = "apc"
	search.text_changed.emit("apc")
	t.eq(list.item_count, 1, "search filters to APC")
	t.ok(str(list.get_item_text(0)).begins_with("avapc"))
	search.text = "zzzz"
	search.text_changed.emit("zzzz")
	t.eq(list.item_count, 1, "no-match placeholder")
	t.ok(list.is_item_disabled(0))
	t.eq(list.get_item_text(0), "No classes match “zzzz”")
	search.text = ""
	search.text_changed.emit("")
	t.eq(list.item_count, 3)

	var radius: HSlider = pal.find_child("Radius", true, false)
	radius.value = 120
	t.eq(int(ToolState.radius_m), 120)
	t.eq((pal.find_child("RadiusVal", true, false) as Label).text, "120 m")
	var strength: HSlider = pal.find_child("Strength", true, false)
	strength.value = 0.8
	t.near(ToolState.strength, 0.8, 0.001)
	var falloff: HSlider = pal.find_child("Falloff", true, false)
	falloff.value = 0.2
	t.near(ToolState.falloff, 0.2, 0.001)

	(pal.find_child("ShapeSquare", true, false) as Button).pressed.emit()
	t.eq(ToolState.shape, "square")
	t.ok((pal.find_child("ShapeSquare", true, false) as Button).button_pressed)
	(pal.find_child("ShapeCircle", true, false) as Button).pressed.emit()
	t.eq(ToolState.shape, "circle")

	await _symmetry_selector(t, pal)

	ToolState.set_radius(55)
	t.eq(int(radius.value), 55, "keyboard/state radius syncs the slider")
	t.eq((pal.find_child("RadiusVal", true, false) as Label).text, "55 m")

	var swatches: GridContainer = pal.find_child("Swatches", true, false)
	t.eq(swatches.get_child_count(), 16, "16 material swatches")
	(swatches.get_child(5) as Button).pressed.emit()
	t.eq(ToolState.paint_material, 5)
	t.eq(ToolState.tool, "paint")

	ToolState.set_armed({"prjid": "avapc"})
	t.eq(ToolState.tool, "place")
	var apc_i := _index_of(list, "avapc")
	t.ok(apc_i >= 0 and list.is_selected(apc_i), "armed class stays highlighted")
	MapState.session_changed.emit()
	t.ok(ToolState.armed.is_empty(), "session_changed clears the armed class")
	t.eq(list.get_selected_items().size(), 0, "palette deselects when the session changes")
	ToolState.set_armed({"prjid": "avapc"})
	apc_i = _index_of(list, "avapc")
	t.ok(apc_i >= 0 and list.is_selected(apc_i), "re-arm highlights again")
	ToolState.clear_armed()
	t.eq(list.get_selected_items().size(), 0, "Esc/clear_armed deselects the list")

	var cat: OptionButton = pal.find_child("CategoryFilter", true, false)
	var clone: CheckBox = pal.find_child("CloneSafe", true, false)
	t.ok(cat != null and clone != null, "filter controls exist")
	t.ok(search.right_icon != null, "search field has a search icon")
	t.ok(cat.icon != null, "category filter has an icon")
	t.ok((pal.find_child("PaletteIcon", true, false) as TextureRect).texture != null)
	t.eq(cat.get_item_text(0), "All")
	t.eq(cat.item_count, 3, "All + categories present in the index")
	t.ok(_select_option(cat, "craft") >= 0)
	t.eq(list.item_count, 2, "category craft → avapc + player")
	t.ok(_index_of(list, "avapc") >= 0 and _index_of(list, "player") >= 0)
	t.ok(_select_option(cat, "building") >= 0)
	t.eq(list.item_count, 1, "category building → packonly")
	t.ok(_index_of(list, "packonly") >= 0)

	_select_option(cat, "All")
	clone.button_pressed = true
	t.eq(list.item_count, 2, "clone-safe only → verified avapc + packonly")
	t.ok(_index_of(list, "avapc") >= 0)
	t.ok(_index_of(list, "packonly") >= 0)
	t.eq(_index_of(list, "player"), -1, "unverified player hidden")

	_select_option(cat, "craft")
	t.eq(list.item_count, 1, "craft + clone-safe → avapc")
	t.ok(_index_of(list, "avapc") >= 0)

	search.text = "player"
	search.text_changed.emit("player")
	t.eq(list.item_count, 1, "craft + clone-safe + search player → empty")
	t.ok(list.is_item_disabled(0))
	t.eq(list.get_item_text(0), "no matches — category: craft, clone-safe, “player”")

	search.text = ""
	search.text_changed.emit("")
	pal.set_classes({
		"classes": [
			{"prjid": "player", "label": "Player", "source": "game", "category": "craft", "placement_mode": "clone", "template_verified": false},
		],
	}, "base")
	_select_option(cat, "craft")
	clone.button_pressed = true
	t.eq(list.get_item_text(0), "no matches — category: craft, clone-safe")

	_select_option(cat, "All")
	clone.button_pressed = false

	var many: Array = []
	for i in 90:
		many.append({
			"prjid": "cls%02d" % i,
			"label": "Class %d" % i,
			"source": "game",
			"category": "craft" if i < 50 else "building",
			"placement_mode": "runtime",
			"template_verified": false,
		})
	pal.set_classes({"classes": many}, "bzp")
	t.ok(str(list.get_item_text(0)).begins_with("Type to search"), "unfiltered large list is a browse prompt")
	t.ok(_index_of(list, "cls00") < 0, "individual classes are not dumped")
	search.text = "cls00"
	search.text_changed.emit("cls00")
	t.ok(_index_of(list, "cls00") >= 0, "search still lists a hit")
	search.text = ""
	search.text_changed.emit("")
	_select_option(cat, "building")
	t.eq(list.item_count, 40, "category lists without a search")

	_select_option(cat, "All")
	clone.button_pressed = false

	await _visibility_matrix(t, pal)

	pal.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
	MapState.selected_ids = saved_sel
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")
	ToolState.set_radius(saved_r)
	ToolState.set_strength(saved_s)
	ToolState.set_falloff(saved_f)
	ToolState.set_shape(saved_shape)
	ToolState.set_paint_material(saved_mat)
	ToolState.set_symmetry(saved_sym)
	MapState.width_m = saved_w
	MapState.depth_m = saved_d
	if saved_armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(saved_armed)


func _visibility_matrix(t, pal: Node) -> void:
	var want := {
		"raise": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"lower": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"flatten": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"smooth": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"ramp": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"noise": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"paint": {"palette": false, "brush": true, "mats": true, "select": false, "fly": false, "terrain": false},
		"place": {"palette": true, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
		"select": {"palette": false, "brush": false, "mats": false, "select": true, "fly": false, "terrain": false},
		"fly": {"palette": false, "brush": false, "mats": false, "select": false, "fly": true, "terrain": false},
		"qsel": {"palette": false, "brush": true, "mats": true, "select": false, "fly": false, "terrain": true},
		"rsel": {"palette": false, "brush": false, "mats": true, "select": false, "fly": false, "terrain": true},
		"wand": {"palette": false, "brush": false, "mats": true, "select": false, "fly": false, "terrain": true},
		"clone": {"palette": false, "brush": true, "mats": false, "select": false, "fly": false, "terrain": false},
	}
	var rail: Control = pal as Control
	var rail_w: float = rail.custom_minimum_size.x
	t.eq(rail_w, 294.0, "left rail min width is locked")
	var first_w: float = -1.0
	for tool in want.keys():
		var name := str(tool)
		_apply_tool(pal, name)
		await t.tree.process_frame
		var got: Dictionary = _section_vis(pal)
		t.eq(got, want[name], "visibility for %s" % name)
		t.eq(rail.custom_minimum_size.x, rail_w, "min width unchanged on %s" % name)
		t.ok(rail.size.x >= rail_w, "laid-out width holds on %s" % name)
		if first_w < 0.0:
			first_w = rail.size.x
		else:
			t.eq(rail.size.x, first_w, "width does not jump on %s" % name)
		_assert_no_empty_gap(t, pal, name, want[name])

	# Widgets follow the section: hidden sections leave the tree.
	_apply_tool(pal, "raise")
	t.ok(not (pal.find_child("Search", true, false) as Control).is_visible_in_tree())
	t.ok((pal.find_child("Radius", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("Swatches", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("ClassList", true, false) as Control).is_visible_in_tree())

	_apply_tool(pal, "paint")
	t.ok(not (pal.find_child("ClassList", true, false) as Control).is_visible_in_tree())
	t.ok((pal.find_child("Radius", true, false) as Control).is_visible_in_tree())
	t.ok((pal.find_child("Swatches", true, false) as Control).is_visible_in_tree())
	var swatches: GridContainer = pal.find_child("Swatches", true, false)
	t.eq(swatches.get_child_count(), 16)
	var tip: String = (swatches.get_child(5) as Button).tooltip_text
	t.ok(MaterialPalette.type_name(5) in tip, "swatch tooltip uses world type name")
	t.ok("(5)" in tip)

	_apply_tool(pal, "place")
	t.ok((pal.find_child("Search", true, false) as Control).is_visible_in_tree())
	t.ok((pal.find_child("CategoryFilter", true, false) as Control).is_visible_in_tree())
	t.ok((pal.find_child("ClassList", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("Radius", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("Swatches", true, false) as Control).is_visible_in_tree())
	var place_sym: OptionButton = pal.find_child("Symmetry", true, false)
	t.ok(place_sym != null and place_sym.is_visible_in_tree(), "place shows the symmetry selector")

	_apply_tool(pal, "fly")
	var fly: Label = pal.find_child("FlyHint", true, false)
	t.ok(fly != null and fly.is_visible_in_tree())
	t.ok("pick a tool to edit" in fly.text.to_lower())

	# Select: palette collapsed, count + nudge/rotate hint.
	MapState.selected_ids.clear()
	_apply_tool(pal, "select")
	t.ok(not (pal.find_child("ClassList", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("Radius", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("Swatches", true, false) as Control).is_visible_in_tree())
	var summary: Label = pal.find_child("SelectSummary", true, false)
	var hint: Label = pal.find_child("SelectHint", true, false)
	t.ok(summary != null and summary.is_visible_in_tree())
	t.eq(summary.text, "0 selected")
	t.ok(hint != null and hint.is_visible_in_tree())
	t.ok("nudge" in hint.text.to_lower())
	t.ok("rotate" in hint.text.to_lower())
	var snap_grid: OptionButton = pal.find_child("SnapGrid", true, false)
	var snap_ang: OptionButton = pal.find_child("SnapAngle", true, false)
	t.ok(snap_grid != null and snap_grid.is_visible_in_tree(), "select shows grid snap")
	t.ok(snap_ang != null and snap_ang.is_visible_in_tree(), "select shows angle snap")
	t.eq(snap_grid.item_count, 5)
	t.eq(snap_ang.item_count, 4)
	MapState.selected_ids = ["a"] as Array[String]
	pal.refresh_context()
	t.eq(summary.text, "1 selected")
	MapState.selected_ids = ["a", "b"] as Array[String]
	pal.refresh_context()
	t.eq(summary.text, "2 selected")
	MapState.selected_ids.clear()
	pal.refresh_context()
	t.eq(summary.text, "0 selected")

	_apply_tool(pal, "qsel")
	t.ok((pal.find_child("TerrainSelSection", true, false) as CanvasItem).visible)
	t.ok((pal.find_child("Radius", true, false) as Control).is_visible_in_tree())
	t.ok(not (pal.find_child("Strength", true, false) as Control).is_visible_in_tree(), "qsel hides strength")
	t.ok((pal.find_child("SelectByMaterial", true, false) as Button) != null)
	_apply_tool(pal, "wand")
	t.ok((pal.find_child("WandTolerance", true, false) as Control).is_visible_in_tree())
	# With a heightmap present but nothing selected, the truthful block
	# reason for Feather is the empty selection.
	var saved_field = MapState.field
	var hf := HeightField.new()
	hf.grid_x = 8
	hf.grid_z = 8
	hf.heights.resize(64)
	hf.heights.fill(200)
	MapState.field = hf
	pal.refresh_context()
	t.ok((pal.find_child("FeatherApply", true, false) as Button).disabled, "feather disabled with no selection")
	t.ok("no selection" in (pal.find_child("FeatherApply", true, false) as Button).tooltip_text.to_lower())
	MapState.field = saved_field
	pal.refresh_context()
	_apply_tool(pal, "clone")
	t.ok((pal.find_child("CloneMaterials", true, false) as Control).is_visible_in_tree())

	# Switching a tool twice is idempotent (raise → paint → raise, and raise ×2).
	_apply_tool(pal, "raise")
	var raise_a: Dictionary = _section_vis(pal)
	_apply_tool(pal, "paint")
	_apply_tool(pal, "raise")
	t.eq(_section_vis(pal), raise_a, "raise after paint matches first raise")
	_apply_tool(pal, "raise")
	t.eq(_section_vis(pal), raise_a, "second raise is a no-op")
	_apply_tool(pal, "paint")
	var paint_a: Dictionary = _section_vis(pal)
	_apply_tool(pal, "paint")
	t.eq(_section_vis(pal), paint_a, "second paint is a no-op")

	# Existing APIs still work while their section is hidden.
	_apply_tool(pal, "raise")
	t.eq(pal.sample_material(3), "sampled mat 3 (%s)" % MaterialPalette.type_name(3))
	t.eq(ToolState.paint_material, 3)


func _symmetry_selector(t, pal: Node) -> void:
	_apply_tool(pal, "raise")
	await t.tree.process_frame
	var sym: OptionButton = pal.find_child("Symmetry", true, false)
	t.ok(sym != null, "symmetry selector exists")
	t.ok(sym.is_visible_in_tree(), "symmetry visible on sculpt")
	t.eq(sym.item_count, 5, "Off / Mirror X / Mirror Z / Rot180 / Quad")
	var ids: Array[String] = []
	for i in sym.item_count:
		ids.append(str(sym.get_item_metadata(i)))
	t.eq(ids, [
		ToolState.SYMMETRY_OFF,
		ToolState.SYMMETRY_MIRROR_X,
		ToolState.SYMMETRY_MIRROR_Z,
		ToolState.SYMMETRY_ROT180,
		ToolState.SYMMETRY_QUAD,
	])
	var mx := _symmetry_index(sym, ToolState.SYMMETRY_MIRROR_X)
	t.ok(mx >= 0)
	sym.select(mx)
	sym.item_selected.emit(mx)
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_MIRROR_X, "selector writes ToolState")
	ToolState.set_symmetry(ToolState.SYMMETRY_ROT180)
	t.eq(str(sym.get_item_metadata(sym.selected)), ToolState.SYMMETRY_ROT180, "state syncs the selector")

	var quad := _symmetry_index(sym, ToolState.SYMMETRY_QUAD)
	t.ok(quad >= 0)
	MapState.has_session = true
	ToolState.set_symmetry(ToolState.SYMMETRY_QUAD)
	MapState.width_m = 2560
	MapState.depth_m = 1280
	pal.refresh_context()
	t.ok(sym.is_item_disabled(quad), "Quad disabled on a rectangular map")
	t.ok("square" in sym.get_item_tooltip(quad).to_lower())
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_QUAD, "stored mode stays quad")
	t.eq(ToolState.effective_symmetry(), ToolState.SYMMETRY_OFF, "stored Quad is off until the map is square")
	MapState.width_m = 1280
	MapState.depth_m = 1280
	pal.refresh_context()
	t.ok(not sym.is_item_disabled(quad), "Quad enabled on a square map")
	t.eq(ToolState.effective_symmetry(), ToolState.SYMMETRY_QUAD)
	sym.select(quad)
	sym.item_selected.emit(quad)
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_QUAD)
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)


func _symmetry_index(sym: OptionButton, id: String) -> int:
	for i in sym.item_count:
		if str(sym.get_item_metadata(i)) == id:
			return i
	return -1


func _apply_tool(pal: Node, tool: String) -> void:
	# set_tool no-ops when the name is unchanged; still force a layout pass.
	if ToolState.tool != tool:
		ToolState.set_tool(tool)
	pal.refresh_context()


func _section_vis(pal: Node) -> Dictionary:
	var terrain := pal.find_child("TerrainSelSection", true, false)
	return {
		"palette": (pal.find_child("PaletteSection", true, false) as CanvasItem).visible,
		"brush": (pal.find_child("BrushSection", true, false) as CanvasItem).visible,
		"mats": (pal.find_child("MatsSection", true, false) as CanvasItem).visible,
		"select": (pal.find_child("SelectSection", true, false) as CanvasItem).visible,
		"fly": (pal.find_child("FlySection", true, false) as CanvasItem).visible,
		"terrain": terrain != null and (terrain as CanvasItem).visible,
	}


func _assert_no_empty_gap(t, pal: Node, tool: String, want: Dictionary) -> void:
	var box: Node = pal.find_child("Box", true, false)
	t.ok(box != null, "section box exists")
	var visible_n := 0
	for child in box.get_children():
		if not (child is CanvasItem):
			continue
		if child.name == "Collapse":
			# The panel header toggle lives in Box and is always visible.
			continue
		if (child as CanvasItem).visible:
			visible_n += 1
			t.ok((child as Control).get_combined_minimum_size().y > 0.0, "%s visible section has height" % tool)
	var expect := 0
	for key in want.keys():
		expect += int(want[key])
	t.eq(visible_n, expect, "no leftover sections on %s" % tool)
	t.eq(
		int(want["palette"]) + int(want["brush"]) + int(want["mats"])
		+ int(want["select"]) + int(want["fly"]) + int(want.get("terrain", false)),
		expect,
	)


func _index_of(list: ItemList, prjid: String) -> int:
	for i in list.item_count:
		var rec = list.get_item_metadata(i)
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("prjid", "")) == prjid:
			return i
	return -1


func _select_option(btn: OptionButton, label: String) -> int:
	for i in btn.item_count:
		if btn.get_item_text(i) == label:
			btn.select(i)
			btn.item_selected.emit(i)
			return i
	return -1
