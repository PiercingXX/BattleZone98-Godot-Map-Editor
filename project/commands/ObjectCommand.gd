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
var items: Array = []


func do() -> void:
	if kind == Kind.EDIT and not items.is_empty():
		_apply_items(true)
		return
	_apply(after, true)


func undo() -> void:
	if kind == Kind.EDIT and not items.is_empty():
		_apply_items(false)
		return
	_apply(before, false)


func cost_bytes() -> int:
	if not items.is_empty():
		return maxi(1024, items.size() * 1024)
	return 1024


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
