extends RefCounted
class_name BrushMaskLibrary
## Process-wide cache of the generated brush tips.
##
## Tips are pure functions of their id, so one copy serves every SculptTool and
## every panel preview. Built on first use and kept; prewarm() from an autoload
## pays the ~25 KB up front instead of during the first stroke (C17).

## Seed for the tips that use noise. Fixed, so tips never differ run to run.
const MASK_SEED := 0x627A98

static var _cache: Dictionary = {}


static func ids() -> PackedStringArray:
	return BrushMask.IDS


static func has(id: String) -> bool:
	return BrushMask.IDS.has(id)


## Null for an unknown or empty id — the caller falls back to the analytic
## circle/square, which is what "no mask selected" means.
static func get_mask(id: String) -> BrushMask:
	if id.is_empty() or not BrushMask.IDS.has(id):
		return null
	if not _cache.has(id):
		_cache[id] = BrushMask.generate(id, BrushMask.SIZE, MASK_SEED)
	return _cache[id]


static func prewarm() -> void:
	for id in BrushMask.IDS:
		get_mask(id)


## Test seam: drop the cache so a regenerated tip can be compared to the first.
static func clear_cache() -> void:
	_cache.clear()
