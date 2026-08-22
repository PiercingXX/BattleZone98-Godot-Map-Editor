extends RefCounted
class_name ToolDoc
## What a tool is, declared by the tool itself, next to the code that
## implements it. The parameter half IS the PropertySchema dictionary the
## editors are generated from — one declaration, so the docs cannot describe
## a knob the panel does not show, or miss one it does.
##
##   const SCHEMA := {
##       "radius_m": {
##           "type": TYPE_FLOAT, "range": {"min": 5, "max": 200, "step": 1},
##           "default": 40.0, "suffix": "m",
##           "doc": "Footprint of the stamp on the heightfield.",
##           "warning": "Above ~120 m a stroke rebuilds several clipmap rings.",
##           "cost": PropertySchema.COST_MODERATE,
##       },
##   }
##
##   func _init() -> void:
##       doc = ToolDoc.make("raise", "Raise", "Sculpt",
##           "Pushes terrain up under the brush.", SCHEMA)

var id: String = ""
var display_name: String = ""
var category: String = "General"
var description: String = ""
var shortcut: String = ""
## Rough price of running the tool once, independent of its parameters.
var cost: String = PropertySchema.COST_LIGHT
## Normalized PropertySchema dictionary. PropertyGrid.build() consumes it
## verbatim.
var schema: Dictionary = {}
var see_also: PackedStringArray = []


static func make(id_value: String, display_name_value: String,
		category_value: String, description_value: String,
		schema_value: Dictionary = {}, shortcut_value: String = "",
		cost_value: String = PropertySchema.COST_LIGHT) -> ToolDoc:
	var doc := ToolDoc.new()
	doc.id = id_value
	doc.display_name = display_name_value
	doc.category = category_value
	doc.description = description_value
	doc.shortcut = shortcut_value
	doc.cost = cost_value if PropertySchema.COST_ORDER.has(cost_value) \
		else PropertySchema.COST_LIGHT
	doc.schema = PropertySchema.normalize(schema_value)
	return doc


func title() -> String:
	return display_name if not display_name.is_empty() else id


## One row per parameter, already flattened for rendering. Everything here is
## read out of the schema entry, so there is nothing to keep in sync.
func params() -> Array:
	var out: Array = []
	for key in schema.keys():
		var entry: Dictionary = schema[key]
		var prose := str(entry.get("doc", ""))
		if prose.is_empty():
			prose = str(entry.get("tooltip", ""))
		out.append({
			"key": str(key),
			"label": str(entry.get("label", key)),
			"type_name": PropertySchema.type_name(int(entry.get("type", 0))),
			"description": prose,
			"warning": str(entry.get("warning", "")),
			"cost": str(entry.get("cost", PropertySchema.COST_LIGHT)),
			"cost_order": int(PropertySchema.COST_ORDER.get(
				str(entry.get("cost", PropertySchema.COST_LIGHT)), 1)),
			"range_text": PropertySchema.range_text(entry),
			"default": entry.get("default"),
			"randomizable": bool(entry.get("randomizable", false)),
		})
	return out


func param(key: String) -> Dictionary:
	for p in params():
		if p["key"] == key:
			return p
	return {}


## Parameters with no prose. A tool that fails this is under-documented, and
## a test can say so out loud instead of a reviewer noticing years later.
func undocumented_params() -> PackedStringArray:
	var out: PackedStringArray = []
	for p in params():
		if str(p["description"]).is_empty():
			out.append(str(p["key"]))
	return out


## Free-text match over everything a user might type into a help search box.
func matches(query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return true
	var hay := "%s %s %s %s %s" % [
		id, display_name, category, description, shortcut,
	]
	for p in params():
		hay += " %s %s %s %s" % [
			p["key"], p["label"], p["description"], p["warning"],
		]
	return hay.to_lower().contains(q)


func header_line() -> String:
	var bits: PackedStringArray = [category]
	if not shortcut.is_empty():
		bits.append(shortcut)
	bits.append("cost: %s" % cost)
	return "  ·  ".join(bits)


## RichTextLabel markup, for the inline panel documentation and F1.
func to_bbcode() -> String:
	var out := "[b]%s[/b]  [i]%s[/i]\n" % [title(), header_line()]
	if not description.is_empty():
		out += description + "\n"
	for p in params():
		out += "\n[b]%s[/b] [i](%s%s)[/i]\n" % [
			p["label"], p["type_name"],
			"" if str(p["range_text"]).is_empty() else ", " + str(p["range_text"]),
		]
		if not str(p["description"]).is_empty():
			out += "  %s\n" % p["description"]
		if not str(p["warning"]).is_empty():
			out += "  [b]Warning:[/b] %s\n" % p["warning"]
		out += "  cost: %s\n" % p["cost"]
	return out


## Markdown, for a generated user manual. docs/ has no manual today; this is
## the source one would be built from.
func to_markdown() -> String:
	var out := "### %s\n\n" % title()
	out += "*%s*\n\n" % header_line()
	if not description.is_empty():
		out += description + "\n\n"
	if schema.is_empty():
		return out
	out += "| Parameter | Type | Range | Default | Cost | Notes |\n"
	out += "| --- | --- | --- | --- | --- | --- |\n"
	for p in params():
		var notes := str(p["description"])
		if not str(p["warning"]).is_empty():
			notes += (" " if not notes.is_empty() else "") \
				+ "**Warning:** " + str(p["warning"])
		out += "| `%s` | %s | %s | %s | %s | %s |\n" % [
			p["key"], p["type_name"],
			str(p["range_text"]) if not str(p["range_text"]).is_empty() else "—",
			str(p["default"]), p["cost"],
			notes if not notes.is_empty() else "—",
		]
	return out + "\n"
