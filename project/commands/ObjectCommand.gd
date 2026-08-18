extends RefCounted
class_name ObjectCommand
## Add / delete / move a single object record, or a batch of EDITs.


enum Kind { ADD, DELETE, EDIT }

var kind: int = Kind.EDIT
var variant: String = ""
var object_id: String = ""
var before: Dictionary = {}
var after: Dictionary = {}
## EDIT batch: [{object_id, variant, before, after}, ...]. One undo step.
## ADD batch:  [{object_id, variant, after}, ...]. One undo step (copy-to-variant).
var items: Array = []


func describe() -> String:
	var prjid := _describe_prjid()
	match kind:
		Kind.ADD:
			return "place %s" % prjid
		Kind.DELETE:
			return "delete %s" % prjid
		Kind.EDIT:
			return "edit %s" % prjid
	return get_class()


func _describe_prjid() -> String:
	var from_after := str(after.get("prjid", "")).strip_edges()
	if not from_after.is_empty():
		return from_after
	var from_before := str(before.get("prjid", "")).strip_edges()
	if not from_before.is_empty():
		return from_before
	if not items.is_empty() and typeof(items[0]) == TYPE_DICTIONARY:
		var item: Dictionary = items[0]
		var rec: Variant = item.get("after", item.get("before", {}))
		if typeof(rec) == TYPE_DICTIONARY:
			var from_item := str((rec as Dictionary).get("prjid", "")).strip_edges()
			if not from_item.is_empty():
				return from_item
	return "object"


func do() -> void:
	if kind == Kind.EDIT and not items.is_empty():
		_apply_items(true)
		return
	if kind == Kind.ADD and not items.is_empty():
		_apply_add_items(true)
		return
	_apply(after, true)


func undo() -> void:
	if kind == Kind.EDIT and not items.is_empty():
		_apply_items(false)
		return
	if kind == Kind.ADD and not items.is_empty():
		_apply_add_items(false)
		return
	_apply(before, false)


func cost_bytes() -> int:
	if not items.is_empty():
		return maxi(1024, items.size() * 1024)
	return 1024


func _apply_add_items(is_do: bool) -> void:
	if is_do:
		for item in items:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = item.get("after", {})
			if rec.is_empty():
				continue
			MapState.add_object_record(str(item.get("variant", variant)), rec.duplicate(true))
		return
	var i := items.size() - 1
	while i >= 0:
		var item: Variant = items[i]
		i -= 1
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = item
		MapState.remove_object_record(
			str(rec.get("variant", variant)),
			str(rec.get("object_id", "")),
		)


func _apply_items(is_do: bool) -> void:
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var oid := str(item.get("object_id", ""))
		var rec := MapState.find_object(oid)
		if rec.is_empty():
			continue
		var src: Dictionary = item["after"] if is_do else item["before"]
		for key in src.keys():
			rec[key] = src[key]
		MapState.touch_object(str(item.get("variant", "")), oid)
	MapState.objects_changed()


func _apply(state: Dictionary, is_do: bool) -> void:
	match kind:
		Kind.ADD:
			if is_do:
				MapState.add_object_record(variant, after.duplicate(true))
			else:
				MapState.remove_object_record(variant, object_id)
		Kind.DELETE:
			if is_do:
				MapState.remove_object_record(variant, object_id)
			else:
				MapState.add_object_record(variant, before.duplicate(true))
		Kind.EDIT:
			var rec := MapState.find_object(object_id)
			if rec.is_empty():
				return
			var src := after if is_do else before
			for key in src.keys():
				rec[key] = src[key]
			MapState.touch_object(variant, object_id)
			MapState.objects_changed()
