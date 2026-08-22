extends RefCounted
class_name PropertySchema
## One dictionary per tool describes its parameters. PropertyGrid turns that
## dictionary into editors and ToolDoc turns the SAME dictionary into prose,
## so a parameter cannot exist in the UI without existing in the docs.
##
## Entry shape, keyed by property name (every field optional but `type`):
##   type          Godot TYPE_* constant
##   range         {min, max, step}  — absent means unbounded
##   default       initial value; inferred from `type` when absent
##   randomizable  true adds a reroll button next to the editor
##   usage         USAGE_* hint (enum, file, dir, multiline, band, seed)
##   object_type   enum items, or file filters, for the matching usage
##   label         row caption; title-cased from the key when absent
##   tooltip       one-line hover text
##   doc           prose the inline documentation renders
##   warning       caveat the documentation renders in the warning slot
##   cost          COST_* rough runtime price of touching this parameter
##   suffix        unit shown inside numeric editors

const USAGE_PLAIN := ""
const USAGE_ENUM := "enum"
const USAGE_FILE := "file"
const USAGE_DIR := "dir"
const USAGE_MULTILINE := "multiline"
## Two-handle band over one axis (slope 12–34°, height 40–90 m).
const USAGE_BAND := "band"
## Integer seed: reroll spans the whole positive range, not `range`.
const USAGE_SEED := "seed"

const COST_TRIVIAL := "trivial"
const COST_LIGHT := "light"
const COST_MODERATE := "moderate"
const COST_HEAVY := "heavy"

## Ascending price. Renderers use it for badge weight and for sorting.
const COST_ORDER := {
	COST_TRIVIAL: 0,
	COST_LIGHT: 1,
	COST_MODERATE: 2,
	COST_HEAVY: 3,
}

const SUPPORTED_TYPES: Array[int] = [
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
	TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_COLOR,
]

const TYPE_NAMES := {
	TYPE_BOOL: "bool",
	TYPE_INT: "int",
	TYPE_FLOAT: "float",
	TYPE_STRING: "String",
	TYPE_VECTOR2: "Vector2",
	TYPE_VECTOR2I: "Vector2i",
	TYPE_VECTOR3: "Vector3",
	TYPE_COLOR: "Color",
}

## Stand-in bounds for an entry with no `range`. Wide enough that no editor
## silently clips a value, narrow enough that SpinBox arithmetic stays exact.
const UNBOUNDED := 1.0e9


static func type_name(type: int) -> String:
	return str(TYPE_NAMES.get(type, "Variant"))


## Fill in every optional field so consumers never branch on absence.
static func normalize_entry(key: String, entry: Dictionary) -> Dictionary:
	var out := entry.duplicate(true)
	var type := int(out.get("type", TYPE_NIL))
	if not SUPPORTED_TYPES.has(type):
		type = TYPE_FLOAT
	out["type"] = type
	out["usage"] = str(out.get("usage", USAGE_PLAIN))
	var label := str(out.get("label", ""))
	out["label"] = label if not label.is_empty() else label_from_key(key)
	out["tooltip"] = str(out.get("tooltip", ""))
	out["doc"] = str(out.get("doc", ""))
	out["warning"] = str(out.get("warning", ""))
	out["suffix"] = str(out.get("suffix", ""))
	out["section"] = str(out.get("section", ""))
	var cost := str(out.get("cost", COST_LIGHT))
	out["cost"] = cost if COST_ORDER.has(cost) else COST_LIGHT
	out["randomizable"] = bool(out.get("randomizable", false))
	if typeof(out.get("object_type")) != TYPE_ARRAY:
		var raw := str(out.get("object_type", ""))
		out["object_type"] = [] if raw.is_empty() else [raw]
	var rng_dict := {}
	if typeof(out.get("range")) == TYPE_DICTIONARY:
		rng_dict = out["range"]
	out["bounded"] = rng_dict.has("min") and rng_dict.has("max")
	out["range"] = {
		"min": float(rng_dict.get("min", -UNBOUNDED)),
		"max": float(rng_dict.get("max", UNBOUNDED)),
		"step": float(rng_dict.get("step", 1.0 if _is_integral(type) else 0.001)),
	}
	if not out.has("default"):
		out["default"] = default_for(out)
	out["default"] = coerce(out, out["default"])
	return out


static func normalize(schema: Dictionary) -> Dictionary:
	var out := {}
	for key in schema.keys():
		var raw: Variant = schema[key]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		out[str(key)] = normalize_entry(str(key), raw)
	return out


## "peak_height_m" -> "Peak height m" is wrong; drop a trailing unit token and
## title-case the rest so a schema rarely needs an explicit label.
static func label_from_key(key: String) -> String:
	var parts := key.replace("-", "_").split("_", false)
	var words: PackedStringArray = []
	for i in parts.size():
		var w := str(parts[i])
		if i == parts.size() - 1 and w.length() <= 2 and parts.size() > 1:
			continue
		words.append(w)
	if words.is_empty():
		words = parts
	var text := " ".join(words)
	return text.substr(0, 1).to_upper() + text.substr(1)


static func default_for(entry: Dictionary) -> Variant:
	var type := int(entry.get("type", TYPE_FLOAT))
	if str(entry.get("usage", "")) == USAGE_ENUM:
		var items := enum_items(entry)
		if not items.is_empty():
			return items[0]["value"]
	match type:
		TYPE_BOOL:
			return false
		TYPE_INT:
			return int(_lower(entry)) if bool(entry.get("bounded", false)) else 0
		TYPE_FLOAT:
			return _lower(entry) if bool(entry.get("bounded", false)) else 0.0
		TYPE_STRING:
			return ""
		TYPE_VECTOR2:
			if str(entry.get("usage", "")) == USAGE_BAND:
				return Vector2(_lower(entry), _upper(entry))
			return Vector2.ZERO
		TYPE_VECTOR2I:
			return Vector2i.ZERO
		TYPE_VECTOR3:
			return Vector3.ZERO
		TYPE_COLOR:
			return Color.WHITE
	return null


static func defaults(schema: Dictionary) -> Dictionary:
	var norm := _ensure(schema)
	var out := {}
	for key in norm.keys():
		out[key] = norm[key]["default"]
	return out


## Enum items as [{label: String, value: Variant}]. `object_type` accepts a
## plain Array of names (value = index for ints, the name itself for strings)
## or an Array of {label, value} for sparse or non-index values.
static func enum_items(entry: Dictionary) -> Array:
	var raw: Variant = entry.get("object_type", [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	var type := int(entry.get("type", TYPE_INT))
	var out: Array = []
	var idx := 0
	for item in raw:
		if typeof(item) == TYPE_DICTIONARY:
			var d: Dictionary = item
			out.append({
				"label": str(d.get("label", d.get("value", idx))),
				"value": d.get("value", idx),
			})
		else:
			out.append({
				"label": str(item),
				"value": str(item) if type == TYPE_STRING else idx,
			})
		idx += 1
	return out


static func file_filters(entry: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var raw: Variant = entry.get("object_type", [])
	if typeof(raw) == TYPE_ARRAY:
		for f in raw:
			out.append(str(f))
	return out


## Cast to the declared type, snap to `step`, clamp into `range`. Out-of-range
## input is pulled in, never rejected: an editor must always show something.
static func coerce(entry: Dictionary, value: Variant) -> Variant:
	var type := int(entry.get("type", TYPE_FLOAT))
	var usage := str(entry.get("usage", USAGE_PLAIN))
	if usage == USAGE_ENUM:
		return _coerce_enum(entry, value)
	match type:
		TYPE_BOOL:
			return bool(value) if typeof(value) != TYPE_STRING \
				else str(value).to_lower() in ["1", "true", "yes", "on"]
		TYPE_INT:
			return int(round(_snap_clamp(entry, _as_float(value))))
		TYPE_FLOAT:
			return _snap_clamp(entry, _as_float(value))
		TYPE_STRING:
			return str(value)
		TYPE_VECTOR2:
			var v2 := _as_vector2(value)
			if usage == USAGE_BAND:
				return _coerce_band(entry, v2)
			return Vector2(_snap_clamp(entry, v2.x), _snap_clamp(entry, v2.y))
		TYPE_VECTOR2I:
			var vi := _as_vector2(value)
			return Vector2i(
				int(round(_snap_clamp(entry, vi.x))),
				int(round(_snap_clamp(entry, vi.y)))
			)
		TYPE_VECTOR3:
			var v3 := _as_vector3(value)
			return Vector3(
				_snap_clamp(entry, v3.x),
				_snap_clamp(entry, v3.y),
				_snap_clamp(entry, v3.z)
			)
		TYPE_COLOR:
			if typeof(value) == TYPE_COLOR:
				return value
			if typeof(value) == TYPE_STRING:
				return Color.html(str(value))
			return Color.WHITE
	return value


## Coerce a whole value dict; unknown keys are dropped, missing keys default.
static func coerce_values(schema: Dictionary, values: Dictionary) -> Dictionary:
	var norm := _ensure(schema)
	var out := {}
	for key in norm.keys():
		var entry: Dictionary = norm[key]
		out[key] = coerce(entry, values[key]) if values.has(key) else entry["default"]
	return out


## Deterministic by construction: the caller owns the RNG, so a rebuild that
## reseeds the same way reproduces the same values (C6).
static func random_value(entry: Dictionary,
		rng: RandomNumberGenerator) -> Variant:
	var type := int(entry.get("type", TYPE_FLOAT))
	var usage := str(entry.get("usage", USAGE_PLAIN))
	if usage == USAGE_ENUM:
		var items := enum_items(entry)
		if items.is_empty():
			return entry.get("default")
		return items[rng.randi_range(0, items.size() - 1)]["value"]
	if usage == USAGE_SEED:
		if type == TYPE_STRING:
			return "%08x" % (rng.randi() & 0x7fffffff)
		# Kept under UNBOUNDED so the spinbox showing it is not silently
		# clamping every reroll.
		return rng.randi_range(0, int(UNBOUNDED) - 1)
	var lo := _lower(entry)
	var hi := _upper(entry)
	var bounded := bool(entry.get("bounded", false))
	match type:
		TYPE_BOOL:
			return rng.randi() % 2 == 1
		TYPE_INT:
			return rng.randi_range(int(lo), int(hi)) if bounded \
				else rng.randi_range(0, int(UNBOUNDED) - 1)
		TYPE_FLOAT:
			return coerce(entry, rng.randf_range(lo, hi)) if bounded else rng.randf()
		TYPE_STRING:
			return "%08x" % (rng.randi() & 0x7fffffff)
		TYPE_VECTOR2:
			if usage == USAGE_BAND:
				var a := rng.randf_range(lo, hi)
				var b := rng.randf_range(lo, hi)
				return coerce(entry, Vector2(minf(a, b), maxf(a, b)))
			return coerce(entry, Vector2(
				rng.randf_range(lo, hi), rng.randf_range(lo, hi)))
		TYPE_VECTOR2I:
			return coerce(entry, Vector2(
				rng.randf_range(lo, hi), rng.randf_range(lo, hi)))
		TYPE_VECTOR3:
			return coerce(entry, Vector3(
				rng.randf_range(lo, hi),
				rng.randf_range(lo, hi),
				rng.randf_range(lo, hi)))
		TYPE_COLOR:
			return Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
	return entry.get("default")


## Human-readable range for docs: "1 – 200 m, step 0.5".
static func range_text(entry: Dictionary) -> String:
	if not bool(entry.get("bounded", false)):
		return ""
	var suffix := str(entry.get("suffix", ""))
	var rng_dict: Dictionary = entry.get("range", {})
	var step := float(rng_dict.get("step", 0.0))
	var lo := _fmt(float(rng_dict.get("min", 0.0)), step)
	var hi := _fmt(float(rng_dict.get("max", 0.0)), step)
	var text := "%s – %s" % [lo, hi]
	if not suffix.is_empty():
		text += " " + suffix
	if step > 0.0:
		text += ", step %s" % _fmt(step, step)
	return text


## Hover text for a generated editor: the one-liner, then the prose, then the
## caveat. Panels get documentation on hover for free.
static func tooltip_for(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	var tip := str(entry.get("tooltip", ""))
	var doc := str(entry.get("doc", ""))
	var warn := str(entry.get("warning", ""))
	if not tip.is_empty():
		parts.append(tip)
	if not doc.is_empty() and doc != tip:
		parts.append(doc)
	var rt := range_text(entry)
	if not rt.is_empty():
		parts.append(rt)
	if not warn.is_empty():
		parts.append("Warning: " + warn)
	return "\n".join(parts)


## Author-facing lint. Empty means the schema is well formed.
static func validate(schema: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for key in schema.keys():
		var raw: Variant = schema[key]
		if typeof(raw) != TYPE_DICTIONARY:
			out.append("%s: entry is not a Dictionary" % key)
			continue
		var entry: Dictionary = raw
		if not entry.has("type"):
			out.append("%s: no type" % key)
		elif not SUPPORTED_TYPES.has(int(entry.get("type", TYPE_NIL))):
			out.append("%s: unsupported type %d" % [key, int(entry.get("type", 0))])
		if str(entry.get("usage", "")) == USAGE_ENUM \
				and enum_items(normalize_entry(str(key), entry)).is_empty():
			out.append("%s: enum usage with no object_type items" % key)
		if typeof(entry.get("range")) == TYPE_DICTIONARY:
			var r: Dictionary = entry["range"]
			if r.has("min") and r.has("max") \
					and float(r["min"]) > float(r["max"]):
				out.append("%s: range min above max" % key)
	return out


## Type-tolerant equality, so an int 2 read back from a control still matches
## a float 2.0 written by a caller.
static func values_equal(a: Variant, b: Variant) -> bool:
	return _same_value(a, b)


static func _ensure(schema: Dictionary) -> Dictionary:
	# Idempotent: normalize_entry fills "bounded", so a normalized schema is
	# recognisable and re-normalizing is free rather than lossy.
	if schema.is_empty():
		return {}
	for key in schema.keys():
		var raw: Variant = schema[key]
		if typeof(raw) != TYPE_DICTIONARY or not (raw as Dictionary).has("bounded"):
			return normalize(schema)
	return schema


static func _is_integral(type: int) -> bool:
	return type == TYPE_INT or type == TYPE_VECTOR2I


static func _lower(entry: Dictionary) -> float:
	var r: Dictionary = entry.get("range", {})
	return float(r.get("min", -UNBOUNDED))


static func _upper(entry: Dictionary) -> float:
	var r: Dictionary = entry.get("range", {})
	return float(r.get("max", UNBOUNDED))


static func _step(entry: Dictionary) -> float:
	var r: Dictionary = entry.get("range", {})
	return float(r.get("step", 0.0))


static func _snap_clamp(entry: Dictionary, v: float) -> float:
	var step := _step(entry)
	var out := v
	if step > 0.0:
		var base := _lower(entry) if bool(entry.get("bounded", false)) else 0.0
		out = base + snappedf(out - base, step)
	if bool(entry.get("bounded", false)):
		out = clampf(out, _lower(entry), _upper(entry))
	return out


static func _coerce_band(entry: Dictionary, v: Vector2) -> Vector2:
	var lo := _snap_clamp(entry, minf(v.x, v.y))
	var hi := _snap_clamp(entry, maxf(v.x, v.y))
	return Vector2(lo, hi)


static func _coerce_enum(entry: Dictionary, value: Variant) -> Variant:
	var items := enum_items(entry)
	if items.is_empty():
		return value
	for item in items:
		if _same_value(item["value"], value):
			return item["value"]
	var fallback: Variant = entry.get("default", items[0]["value"])
	for item in items:
		if _same_value(item["value"], fallback):
			return item["value"]
	return items[0]["value"]


static func _same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) == typeof(b):
		return a == b
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


static func _as_float(value: Variant) -> float:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT, TYPE_BOOL:
			return float(value)
		TYPE_STRING:
			return str(value).to_float()
	return 0.0


static func _as_vector2(value: Variant) -> Vector2:
	match typeof(value):
		TYPE_VECTOR2:
			return value
		TYPE_VECTOR2I:
			return Vector2(value)
		TYPE_ARRAY:
			var a: Array = value
			if a.size() >= 2:
				return Vector2(_as_float(a[0]), _as_float(a[1]))
	return Vector2.ZERO


static func _as_vector3(value: Variant) -> Vector3:
	match typeof(value):
		TYPE_VECTOR3:
			return value
		TYPE_ARRAY:
			var a: Array = value
			if a.size() >= 3:
				return Vector3(_as_float(a[0]), _as_float(a[1]), _as_float(a[2]))
	return Vector3.ZERO


static func _fmt(v: float, step: float) -> String:
	if step >= 1.0 or is_zero_approx(step):
		return str(int(round(v)))
	return String.num(v, 3).rstrip("0").rstrip(".")
