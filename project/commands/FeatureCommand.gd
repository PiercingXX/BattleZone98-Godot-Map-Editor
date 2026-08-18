extends RefCounted
class_name FeatureCommand
## Add / remove / edit one water or plant feature. Mask bytes travel with it.

enum Kind { ADD, REMOVE, EDIT }

var kind: int = Kind.EDIT
var group: String = "water"
var record: Dictionary = {}
var mask_bytes: PackedByteArray = PackedByteArray()
var before: Dictionary = {}
var after: Dictionary = {}
var stem_before: String = ""
var stem_after: String = ""
var mask_before: PackedByteArray = PackedByteArray()
var mask_after: PackedByteArray = PackedByteArray()


func describe() -> String:
	var noun := "water" if group == "water" else "plant"
	match kind:
		Kind.ADD:
			return "add %s" % noun
		Kind.REMOVE:
			return "remove %s" % noun
		Kind.EDIT:
			return "edit %s" % noun
	return get_class()


func cost_bytes() -> int:
	return 1024 + mask_bytes.size() + mask_before.size() + mask_after.size()


func do() -> void:
	match kind:
		Kind.ADD:
			MapState.insert_feature(group, record.duplicate(true), mask_bytes)
		Kind.REMOVE:
			MapState.remove_feature(group, str(record.get("stem", "")))
		Kind.EDIT:
			MapState.apply_feature_edit(group, stem_before, after.duplicate(true), mask_after)


func undo() -> void:
	match kind:
		Kind.ADD:
			MapState.remove_feature(group, str(record.get("stem", "")))
		Kind.REMOVE:
			MapState.insert_feature(group, record.duplicate(true), mask_bytes)
		Kind.EDIT:
			MapState.apply_feature_edit(group, stem_after, before.duplicate(true), mask_before)
