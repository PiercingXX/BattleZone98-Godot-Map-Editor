extends RefCounted
class_name WaterCommand
## One water-line edit. Inspector live-previews, then pushes this already-applied.

var before: float = -1.0
var after: float = -1.0


func describe() -> String:
	return "water level"


func do() -> void:
	MapState.set_water_level(after)


func undo() -> void:
	MapState.set_water_level(before)
