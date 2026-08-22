extends RefCounted
class_name ToolDocs
## Registry of every ToolDoc a tool declared. Gives F1 something to search and
## a manual something to be generated from, without any file listing tools by
## hand: registration happens where the tool is constructed.

static var _docs: Dictionary = {}
static var _order: PackedStringArray = []


## Idempotent: re-registering an id replaces it, so a reloaded tool does not
## leave a stale copy behind.
static func register(doc: ToolDoc) -> ToolDoc:
	if doc == null or doc.id.is_empty():
		return doc
	if not _docs.has(doc.id):
		_order.append(doc.id)
	_docs[doc.id] = doc
	return doc


static func get_doc(id: String) -> ToolDoc:
	return _docs.get(id, null)


static func has(id: String) -> bool:
	return _docs.has(id)


static func all() -> Array:
	var out: Array = []
	for id in _order:
		if _docs.has(id):
			out.append(_docs[id])
	return out


static func size() -> int:
	return _docs.size()


static func clear() -> void:
	_docs.clear()
	_order.clear()


## Registration order within a category, categories in first-seen order.
static func categories() -> PackedStringArray:
	var out: PackedStringArray = []
	for doc in all():
		if not out.has(doc.category):
			out.append(doc.category)
	return out


static func in_category(category: String) -> Array:
	var out: Array = []
	for doc in all():
		if doc.category == category:
			out.append(doc)
	return out


static func search(query: String) -> Array:
	var out: Array = []
	for doc in all():
		if doc.matches(query):
			out.append(doc)
	return out


static func to_bbcode(query: String = "") -> String:
	var parts: PackedStringArray = []
	for cat in categories():
		var hits: Array = []
		for doc in in_category(cat):
			if doc.matches(query):
				hits.append(doc)
		if hits.is_empty():
			continue
		var body := "[b]%s[/b]\n" % cat.to_upper()
		for doc in hits:
			body += doc.to_bbcode() + "\n"
		parts.append(body)
	return "\n".join(parts)


## The user manual, generated. Every heading is a tool that exists.
static func manual_markdown(title: String = "Tool reference") -> String:
	var out := "# %s\n\n" % title
	out += "Generated from the ToolDoc each tool declares in its own "
	out += "constructor. Do not edit by hand.\n\n"
	for cat in categories():
		out += "## %s\n\n" % cat
		for doc in in_category(cat):
			out += doc.to_markdown()
	return out
