extends RefCounted
## The presets have to produce Battlezone maps, not landscape art.
##
## Each floor below is well under the measured value on a 1280 m map across
## several seeds, so ordinary seed-to-seed variation will not trip it, but a
## preset that stops producing buildable ground will. A generator that yields
## a few percent of flat ground is useless for this game — these numbers are
## the difference between a feature and a toy.
##
## Thresholds come from the validators: buildable is tan 5 degrees
## (BzCheckBalance rule E3/B1), drivable is tan 30 degrees
## (BzCheckConnectivity rule C1/C2), and rule B1 wants at least 4000 m2 of
## contiguous buildable ground for a base.

const GRID := 256  # a 1280 m map, the smallest legal size
const SEEDS: PackedInt32Array = [1, 12345]

const FLOORS := {
	"mesa": {"buildable": 0.55, "drivable": 0.85},
	"crater": {"buildable": 0.20, "drivable": 0.65},
	"highlands": {"buildable": 0.22, "drivable": 0.85},
	"canyon": {"buildable": 0.45, "drivable": 0.60},
}


func run(t) -> void:
	_test_catalogue(t)
	_test_playability(t)


func _test_catalogue(t) -> void:
	var names := GenPresets.names()
	t.eq(names.size(), 4, "four presets ship")
	for name in names:
		t.ok(GenPresets.has(name), "%s is in the catalogue" % name)
		t.ok(not GenPresets.title(name).is_empty(), "%s has a title" % name)
		t.ok(not GenPresets.describe(name).is_empty(), "%s has a description" % name)
		var p := GenPresets.make(name, 1)
		t.eq(p.validate(), "", "%s validates" % name)
		t.eq(p.preset, name, "%s records its own name" % name)
		t.ok(FLOORS.has(name), "%s has a playability floor" % name)
	t.ok(GenPresets.has(GenPresets.DEFAULT), "the default preset exists")
	var unknown := GenPresets.make("no-such-preset", 1)
	t.eq(unknown.validate(), "", "an unknown name still returns usable defaults")
	t.eq(unknown.preset, "", "an unknown name is not recorded as a preset")


func _test_playability(t) -> void:
	for name in GenPresets.names():
		var floors: Dictionary = FLOORS[name]
		for seed_value in SEEDS:
			var r := TerrainGenerator.generate(GenPresets.make(name, seed_value), GRID, GRID)
			t.ok(bool(r.get("ok", false)), "%s/%d generates" % [name, seed_value])
			if not bool(r.get("ok", false)):
				continue
			var heights: PackedInt32Array = r["heights"]
			var lo := 0x7FFFFFFF
			var hi := -1
			for v in heights:
				lo = mini(lo, v)
				hi = maxi(hi, v)
			t.ok(lo >= 1 and hi <= 4095, "%s/%d stays in raw 1..4095" % [name, seed_value])
			var s: Dictionary = r["stats"]
			t.ok(
				float(s["buildable_frac"]) >= float(floors["buildable"]),
				"%s/%d buildable %.3f >= %.2f" % [
					name, seed_value, s["buildable_frac"], floors["buildable"]
				],
			)
			t.ok(
				float(s["traversable_frac"]) >= float(floors["drivable"]),
				"%s/%d drivable %.3f >= %.2f" % [
					name, seed_value, s["traversable_frac"], floors["drivable"]
				],
			)
			t.ok(
				float(s["largest_buildable_m2"]) >= 4000.0,
				"%s/%d largest base pocket %.0f m2 clears rule B1" % [
					name, seed_value, s["largest_buildable_m2"]
				],
			)
			t.ok(
				float(s["relief_m"]) > 5.0,
				"%s/%d has actual relief (%.1f m)" % [name, seed_value, s["relief_m"]],
			)
			t.eq(int(s["clipped_high"]), 0, "%s/%d does not clip the ceiling" % [name, seed_value])
			t.eq(int(s["clipped_low"]), 0, "%s/%d does not clip the floor" % [name, seed_value])
			t.ok(
				not TerrainGenerator.describe_stats(s).is_empty(),
				"%s/%d summarises for the log" % [name, seed_value],
			)
