extends RefCounted
## Balance overlay: object list → circles / spawn pairs / team pocket totals.


func run(t) -> void:
	var snap := _snapshot()
	_thresholds(t)
	_circles(t)
	_pairs_fair(t)
	_pairs_outlier(t)
	_team_totals(t)
	_variant_scope(t)
	_empty(t)
	await _view_menu(t)
	_restore(snap)


func _thresholds(t) -> void:
	t.eq(BalanceOverlay.ECONOMY_RADIUS_M, BzCheckBalance.B3_MAX_SPACING_M, "pocket N is B3 max spacing")
	t.eq(BalanceOverlay.FAIR_PAIR_FRAC, BzLayout.E5_GAP, "pair fairness is E5 15% gap")
	t.ok(BalanceOverlay.GEYSER_RADIUS_M > BalanceOverlay.SCRAP_RADIUS_M, "geyser disc larger than scrap")


func _circles(t) -> void:
	var recs := [
		{"id": "g1", "prjid": "eggeizr1", "team": 0, "x": 10.0, "z": 20.0},
		{"id": "s1", "prjid": "npscr1", "team": 0, "x": 30.0, "z": 40.0},
		{"id": "s2", "prjid": "sscr_1", "team": 0, "x": 50.0, "z": 0.0},
		{"id": "p1", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
		{"id": "u1", "prjid": "player", "team": 1, "x": 8.0, "z": 8.0},
		{"id": "junk", "prjid": "avapc", "team": 1, "x": 90.0, "z": 90.0},
	]
	var out := BalanceOverlay.compute(recs)
	var circles: Array = out["circles"]
	t.eq(circles.size(), 3, "geyser + two scrap, no spawn/player/unit")
	var by := _by_id(circles)
	t.ok(by.has("g1") and by.has("s1") and by.has("s2"))
	t.eq(str(by["g1"]["kind"]), "geyser")
	t.eq(str(by["s1"]["kind"]), "scrap")
	t.eq(str(by["s2"]["kind"]), "scrap")
	t.near(float(by["g1"]["x"]), 10.0)
	t.near(float(by["g1"]["z"]), 20.0)
	t.near(float(by["g1"]["radius"]), BalanceOverlay.GEYSER_RADIUS_M)
	t.near(float(by["s1"]["radius"]), BalanceOverlay.SCRAP_RADIUS_M)
	t.ok(float(by["g1"]["radius"]) > float(by["s1"]["radius"]))


func _pairs_fair(t) -> void:
	# Near-equilateral: every edge within 15% of the mean.
	var recs := [
		{"id": "a", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
		{"id": "b", "prjid": "pspwn_1", "team": 1, "x": 100.0, "z": 0.0},
		{"id": "c", "prjid": "pspwn_1", "team": 2, "x": 50.0, "z": 86.6},
	]
	var out := BalanceOverlay.compute(recs)
	var pairs: Array = out["pairs"]
	t.eq(pairs.size(), 3, "C(3,2) pairs")
	t.near(float(out["mean_pair_m"]), 100.0, 0.05)
	for pair in pairs:
		t.ok(bool(pair["fair"]), "equilateral pair is fair: %s" % pair)
	var two := BalanceOverlay.compute([
		{"id": "a", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
		{"id": "b", "prjid": "pspwn_1", "team": 2, "x": 400.0, "z": 0.0},
	])
	t.eq((two["pairs"] as Array).size(), 1)
	t.ok(bool(two["pairs"][0]["fair"]), "single pair is the mean, so fair")
	t.near(float(two["mean_pair_m"]), 400.0, 0.01)


func _pairs_outlier(t) -> void:
	# 100 / 150 / 150 — mean 133.3; only the 100 m base is outside ±15%.
	var recs := [
		{"id": "a", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
		{"id": "b", "prjid": "pspwn_1", "team": 2, "x": 100.0, "z": 0.0},
		{"id": "c", "prjid": "pspwn_1", "team": 3, "x": 50.0, "z": 141.421356},
	]
	var out := BalanceOverlay.compute(recs)
	var pairs: Array = out["pairs"]
	t.eq(pairs.size(), 3)
	var by := {}
	for pair in pairs:
		by["%s-%s" % [pair["a_id"], pair["b_id"]]] = pair
	t.ok(by.has("a-b") and by.has("a-c") and by.has("b-c"))
	t.ok(not bool(by["a-b"]["fair"]), "100 m is an outlier vs mean 133")
	var d_ab := float(by["a-b"]["distance"])
	var d_ac := float(by["a-c"]["distance"])
	var d_bc := float(by["b-c"]["distance"])
	var mean: float = float(out["mean_pair_m"])
	t.near(mean, (d_ab + d_ac + d_bc) / 3.0, 0.01)
	t.eq(bool(by["a-b"]["fair"]), absf(d_ab - mean) <= mean * BalanceOverlay.FAIR_PAIR_FRAC)
	t.eq(bool(by["a-c"]["fair"]), absf(d_ac - mean) <= mean * BalanceOverlay.FAIR_PAIR_FRAC)
	t.eq(bool(by["b-c"]["fair"]), absf(d_bc - mean) <= mean * BalanceOverlay.FAIR_PAIR_FRAC)
	t.ok(not bool(by["a-b"]["fair"]))
	t.ok(bool(by["a-c"]["fair"]), "150 m sits in the 15% band")
	t.ok(bool(by["b-c"]["fair"]), "the matching 150 m leg is fair")


func _team_totals(t) -> void:
	var n: float = BalanceOverlay.ECONOMY_RADIUS_M
	var recs := [
		{"id": "sp1a", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
		{"id": "sp1b", "prjid": "pspwn_1", "team": 1, "x": 20.0, "z": 0.0},
		{"id": "sp2", "prjid": "pspwn_1", "team": 2, "x": 400.0, "z": 400.0},
		{"id": "g_near1", "prjid": "eggeizr1", "team": 0, "x": 10.0, "z": 10.0},
		{"id": "s_near1", "prjid": "npscr2", "team": 0, "x": n - 1.0, "z": 0.0},
		{"id": "s_far1", "prjid": "npscr3", "team": 0, "x": 20.0 + n + 5.0, "z": 0.0},
		{"id": "g_near2", "prjid": "eggeizr1", "team": 0, "x": 400.0, "z": 400.0 + (n - 2.0)},
		{"id": "g_mid", "prjid": "eggeizr1", "team": 0, "x": 200.0, "z": 200.0},
		{"id": "s_both", "prjid": "npscr1", "team": 0, "x": 35.0, "z": 0.0},
	]
	var out := BalanceOverlay.compute(recs)
	t.eq((out["circles"] as Array).size(), 6, "every geyser and scrap gets a disc")
	var teams: Array = out["teams"]
	t.eq(teams.size(), 2)
	t.eq(int(teams[0]["team"]), 1)
	t.eq(int(teams[1]["team"]), 2)
	t.eq(int(teams[0]["spawns"]), 2)
	t.eq(int(teams[1]["spawns"]), 1)
	t.eq(int(teams[0]["geysers"]), 1, "only the geyser inside N of team 1")
	t.eq(int(teams[0]["scrap"]), 2, "near scrap + scrap within N of a team-1 spawn")
	t.eq(int(teams[1]["geysers"]), 1, "geyser sitting on team 2 cluster")
	t.eq(int(teams[1]["scrap"]), 0)
	t.near(float(teams[0]["x"]), 10.0, 0.01, "team 1 centroid")
	t.near(float(teams[0]["z"]), 0.0, 0.01)
	t.near(float(teams[1]["x"]), 400.0, 0.01)
	t.near(float(teams[1]["z"]), 400.0, 0.01)


func _variant_scope(t) -> void:
	var objects := {
		"": [
			{"id": "dm-g", "prjid": "eggeizr1", "x": 0.0, "z": 0.0},
			{"id": "dm-s", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
			{"id": "dm-s2", "prjid": "pspwn_1", "team": 2, "x": 100.0, "z": 0.0},
		],
		"_SW": [
			{"id": "sw-g", "prjid": "eggeizr1", "x": 8.0, "z": 0.0},
			{"id": "sw-sc", "prjid": "npscr1", "x": 4.0, "z": 0.0},
			{"id": "sw-s", "prjid": "pspwn_1", "team": 1, "x": 0.0, "z": 0.0},
		],
	}
	var dm := BalanceOverlay.compute_objects(objects, "")
	t.eq((dm["circles"] as Array).size(), 1, "DM geyser only")
	t.eq(str(dm["circles"][0]["id"]), "dm-g")
	t.eq((dm["pairs"] as Array).size(), 1)
	t.eq((dm["teams"] as Array).size(), 2)
	var sw := BalanceOverlay.compute_objects(objects, "_SW")
	t.eq((sw["circles"] as Array).size(), 2, "SW geyser + scrap")
	t.eq((sw["pairs"] as Array).size(), 0, "one spawn → no pairs")
	t.eq((sw["teams"] as Array).size(), 1)
	t.eq(int(sw["teams"][0]["geysers"]), 1)
	t.eq(int(sw["teams"][0]["scrap"]), 1)
	var missing := BalanceOverlay.compute_objects(objects, "_ST")
	t.eq((missing["circles"] as Array).size(), 0)
	t.eq((missing["teams"] as Array).size(), 0)


func _empty(t) -> void:
	var out := BalanceOverlay.compute([])
	t.eq((out["circles"] as Array).size(), 0)
	t.eq((out["pairs"] as Array).size(), 0)
	t.eq((out["teams"] as Array).size(), 0)
	t.near(float(out["mean_pair_m"]), 0.0)
	var one := BalanceOverlay.compute([
		{"id": "only", "prjid": "pspwn_1", "team": 1, "x": 5.0, "z": 5.0},
	])
	t.eq((one["pairs"] as Array).size(), 0)
	t.eq((one["teams"] as Array).size(), 1)
	t.eq(int(one["teams"][0]["geysers"]), 0)
	t.eq(int(one["teams"][0]["scrap"]), 0)
	t.eq(BalanceOverlay.compute(["not-a-dict"])["circles"].size(), 0)


func _view_menu(t) -> void:
	BalanceOverlay.enabled = false
	var saved_session := MapState.has_session
	MapState.has_session = false
	var bar: Node = load("res://project/ui/top_bar/TopBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame
	var view: MenuButton = bar.find_child("View", true, false)
	var pop: PopupMenu = view.get_popup()
	var idx := pop.get_item_index(bar.VIEW_BALANCE)
	t.ok(idx >= 0, "View menu lists Balance")
	t.eq(pop.get_item_text(idx), "Balance")
	t.ok(pop.is_item_disabled(idx), "Balance disabled with no map")
	t.eq(pop.get_item_tooltip(idx), "Open a map first")
	var was := BalanceOverlay.enabled
	pop.id_pressed.emit(bar.VIEW_BALANCE)
	t.eq(BalanceOverlay.enabled, was, "disabled Balance does not flip")

	MapState.has_session = true
	bar._refresh_view_menu()
	idx = pop.get_item_index(bar.VIEW_BALANCE)
	t.ok(not pop.is_item_disabled(idx), "Balance enabled with a session")
	var saw := [0]
	bar.view_changed.connect(func(): saw[0] += 1)
	pop.id_pressed.emit(bar.VIEW_BALANCE)
	t.ok(BalanceOverlay.enabled, "View → Balance turns on")
	t.eq(saw[0], 1)
	t.ok(pop.is_item_checked(pop.get_item_index(bar.VIEW_BALANCE)))
	pop.id_pressed.emit(bar.VIEW_BALANCE)
	t.ok(not BalanceOverlay.enabled, "second click turns it off")
	t.eq(saw[0], 2)

	bar.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
	BalanceOverlay.enabled = false


func _by_id(rows: Array) -> Dictionary:
	var out := {}
	for row in rows:
		out[str(row.get("id", ""))] = row
	return out


func _snapshot() -> Dictionary:
	return {
		"enabled": BalanceOverlay.enabled,
		"session": MapState.has_session,
	}


func _restore(snap: Dictionary) -> void:
	BalanceOverlay.enabled = bool(snap["enabled"])
	MapState.has_session = bool(snap["session"])
