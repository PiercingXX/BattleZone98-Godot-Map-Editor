extends RefCounted
## PoissonDisc (Bridson 2007): spacing, bounds, determinism.


func run(t) -> void:
	_spacing_and_bounds(t)
	_determinism(t)
	_degenerate(t)
	_k_affects_fill(t)


func _rng(seed_v: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	return rng


func _spacing_and_bounds(t) -> void:
	var rect := Rect2(0.0, 0.0, 200.0, 160.0)
	var r := 10.0
	var pts: PackedVector2Array = PoissonDisc.sample(rect, r, _rng(1234))
	t.ok(pts.size() > 40, "a 200x160 rect at r=10 holds plenty, got %d" % pts.size())
	var r2: float = r * r
	var worst := INF
	for i in pts.size():
		var p := pts[i]
		if not rect.has_point(p):
			t.fail("point %s escaped the rect" % p)
			break
		for j in range(i + 1, pts.size()):
			var d := p.distance_squared_to(pts[j])
			if d < worst:
				worst = d
	t.ok(worst >= r2, "no pair closer than r (worst %.3f m)" % sqrt(worst))
	# Poisson fill lands near 0.7 / r^2 per unit area; well short of that and
	# the annulus or the neighbour window is wrong.
	var expect: float = 0.7 * rect.size.x * rect.size.y / r2
	t.ok(float(pts.size()) > expect * 0.5, "fill %d vs expected ~%d" % [pts.size(), int(expect)])


func _determinism(t) -> void:
	var rect := Rect2(100.0, 50.0, 120.0, 120.0)
	var a: PackedVector2Array = PoissonDisc.sample(rect, 8.0, _rng(99))
	var b: PackedVector2Array = PoissonDisc.sample(rect, 8.0, _rng(99))
	t.eq(a, b, "same seed, same points, same order")
	var c: PackedVector2Array = PoissonDisc.sample(rect, 8.0, _rng(100))
	t.ne(a, c, "a different seed is a different field")
	# A shared generator must not be reused for a second set and still match:
	# resetting the seed per set is what makes rebuilds reproducible.
	var shared := _rng(99)
	var d: PackedVector2Array = PoissonDisc.sample(rect, 8.0, shared)
	var e: PackedVector2Array = PoissonDisc.sample(rect, 8.0, shared)
	t.eq(d, a, "first draw off a fresh generator matches")
	t.ne(e, a, "second draw off the same generator does not")


func _degenerate(t) -> void:
	var rng := _rng(1)
	t.eq(PoissonDisc.sample(Rect2(0, 0, 0, 0), 5.0, rng).size(), 0, "empty rect")
	t.eq(PoissonDisc.sample(Rect2(0, 0, 10, 10), 0.0, rng).size(), 0, "zero radius")
	t.eq(PoissonDisc.sample(Rect2(0, 0, 10, 10), -1.0, rng).size(), 0, "negative radius")
	t.eq(PoissonDisc.sample(Rect2(0, 0, 10, 10), 5.0, null).size(), 0, "no generator")
	var one: PackedVector2Array = PoissonDisc.sample(Rect2(0, 0, 10, 10), 5.0, _rng(3), 15, 1)
	t.eq(one.size(), 1, "the point cap truncates")
	# A radius larger than the rect still seeds one point.
	t.eq(PoissonDisc.sample(Rect2(0, 0, 4, 4), 50.0, _rng(3)).size(), 1)


func _k_affects_fill(t) -> void:
	var rect := Rect2(0.0, 0.0, 160.0, 160.0)
	var few: PackedVector2Array = PoissonDisc.sample(rect, 8.0, _rng(7), 1)
	var many: PackedVector2Array = PoissonDisc.sample(rect, 8.0, _rng(7), 30)
	t.ok(many.size() > few.size(), "more candidates pack tighter (%d > %d)" % [many.size(), few.size()])
