extends Node
## Live tool / brush / armed-class state. Panels and the sculpt tool subscribe.

signal tool_changed(name: String)
signal brush_changed()
signal armed_changed()

var tool: String = "fly"
var radius_m: float = 40.0
var strength: float = 0.45
var falloff: float = 0.65
var shape: String = "circle"
var paint_material: int = 0
var armed: Dictionary = {}


func _ready() -> void:
	MapState.session_changed.connect(_on_session_changed)


func _on_session_changed() -> void:
	if armed.is_empty():
		return
	clear_armed()
	EditorFeedback.log("disarmed (map changed)")


func set_tool(name: String) -> void:
	if tool == name:
		return
	tool = name
	if name != "place":
		clear_armed()
	tool_changed.emit(name)


func set_radius(v: float) -> void:
	if is_equal_approx(radius_m, v):
		return
	radius_m = v
	brush_changed.emit()


func set_strength(v: float) -> void:
	if is_equal_approx(strength, v):
		return
	strength = v
	brush_changed.emit()


func set_falloff(v: float) -> void:
	if is_equal_approx(falloff, v):
		return
	falloff = v
	brush_changed.emit()


func set_shape(v: String) -> void:
	if shape == v:
		return
	shape = v
	brush_changed.emit()


func set_paint_material(id: int) -> void:
	id = clampi(id, 0, 15)
	if paint_material == id:
		return
	paint_material = id
	brush_changed.emit()


func set_armed(rec: Dictionary) -> void:
	armed = rec
	if not rec.is_empty() and tool != "place":
		tool = "place"
		tool_changed.emit("place")
	armed_changed.emit()


func clear_armed() -> void:
	if armed.is_empty():
		return
	armed = {}
	armed_changed.emit()
