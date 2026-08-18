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
	var saved_armed: Dictionary = ToolState.armed.duplicate(true)
	MapState.has_session = false
	ToolState.clear_armed()
	ToolState.set_tool("fly")

	var pal: Node = load("res://project/ui/palette/PalettePanel.tscn").instantiate()
	t.tree.root.add_child(pal)
	await t.tree.process_frame

	var list: ItemList = pal.find_child("ClassList", true, false)
	t.ok(list.item_count >= 1, "empty placeholder present")
	t.ok(list.is_item_disabled(0), "placeholder disabled")

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

	pal.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")
	ToolState.set_radius(saved_r)
	ToolState.set_strength(saved_s)
	ToolState.set_falloff(saved_f)
	ToolState.set_shape(saved_shape)
	ToolState.set_paint_material(saved_mat)
	if saved_armed.is_empty():
		ToolState.clear_armed()
	else:
		ToolState.set_armed(saved_armed)


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
