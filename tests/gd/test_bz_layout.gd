extends RefCounted
## Graph construction + path APIs used by the Tier 2 validators.


func run(t) -> void:
	var g := BzLayout.new(1280.0, 1280.0, 2)
	t.near(g.diagonal_m(), sqrt(1280.0 * 1280.0 + 1280.0 * 1280.0), 0.0001, "diagonal")
	g.add_node("b0", 0.0, 0.0, BzLayout.BASE, 0)
	g.add_node("b1", 100.0, 0.0, BzLayout.BASE, 1)
	g.add_node("g0", 40.0, 0.0, BzLayout.GEYSER)
	g.add_node("s0", 80.0, 0.0, BzLayout.SCRAP)
	var len_ab: float = g.add_route("b0", "b1", 200.0)
	t.near(len_ab, 200.0, 0.0001)
	g.add_route("b0", "g0", 40.0)
	g.add_route("g0", "s0", 40.0)
	g.add_route("s0", "b1", 40.0)

	t.eq(g.base_ids().size(), 2)
	t.eq(g.geyser_ids(), ["g0"])
	t.eq(g.economy_ids().size(), 2)
	t.eq(g.path_distance("b0", "b0"), 0.0)
	t.near(float(g.path_distance("b0", "b1")), 120.0, 0.0001, "via geysers/scrap is 120")
	t.eq(g.path_distance("b0", "missing"), null, "unknown endpoint is null (no throw)")

	var nb: Variant = g.nearest_base("g0")
	t.ok(nb != null, "nearest base exists")
	t.eq(nb[0], "b0")
	t.near(float(nb[1]), 40.0, 0.0001)

	var allb: Array = g._nearest_bases("g0")
	t.eq(allb.size(), 2)
	t.eq(allb[0][0], "b0")

	var unknown: float = g.add_route("nope", "b0")
	t.ok(is_nan(unknown), "unknown route nodes return NAN")
	t.eq(BzLayout.SW_SPAWN_COUNT, 14)
	t.eq(BzLayout.E4_MAX_SPREAD, 0.05)
	t.eq(BzLayout.E5_GAP, 0.15)
