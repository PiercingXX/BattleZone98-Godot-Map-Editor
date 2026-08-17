extends RefCounted
class_name ObjectCommand
## Add / delete / move a single object record.

enum Kind { ADD, DELETE, EDIT }

var kind: int = Kind.EDIT
var variant: String = ""
var object_id: String = ""
var before: Dictionary = {}
var after: Dictionary = {}


func do() -> void:
	_apply(after, true)


func undo() -> void:
	_apply(before, false)


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
