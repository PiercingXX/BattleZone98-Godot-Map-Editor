extends Control
class_name RangeSlider
## Two-handle band over one axis: slope 12–34°, height 40–90 m. Godot ships no
## such control, so band filters otherwise become two disconnected spinboxes
## that can cross over each other.

signal range_changed(low: float, high: float)
## Emitted once when a drag ends, for callers that want one undo per gesture.
signal drag_ended(low: float, high: float)

const HANDLE_R := 6.0
const TRACK_H := 4.0

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.0
var low_value: float = 0.0
var high_value: float = 1.0
## Handles may meet but never cross; the band is always [low, high].
var _dragging: int = 0  # 0 none, 1 low, 2 high


static func make(min_v: float, max_v: float, step_v: float,
		low: float, high: float) -> RangeSlider:
	var ctl := RangeSlider.new()
	ctl.configure(min_v, max_v, step_v)
	ctl.set_band(low, high)
	return ctl


func _init() -> void:
	name = "RangeSlider"
	custom_minimum_size = Vector2(80, 20)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_CLICK


func configure(min_v: float, max_v: float, step_v: float) -> void:
	min_value = min_v
	max_value = maxf(max_v, min_v)
	step = maxf(step_v, 0.0)
	set_band(low_value, high_value)


## Write the band without emitting; ordering and clamping are enforced here so
## no caller can install an inverted range.
func set_band(low: float, high: float) -> void:
	var a := _snap(minf(low, high))
	var b := _snap(maxf(low, high))
	low_value = a
	high_value = b
	queue_redraw()


func band() -> Vector2:
	return Vector2(low_value, high_value)


func set_band_notify(low: float, high: float) -> void:
	var before := band()
	set_band(low, high)
	if band() != before:
		range_changed.emit(low_value, high_value)


func _snap(v: float) -> float:
	var out := clampf(v, min_value, max_value)
	if step > 0.0:
		out = min_value + snappedf(out - min_value, step)
	return clampf(out, min_value, max_value)


## Fraction 0..1 of a value along the track.
func ratio_of(v: float) -> float:
	var span := max_value - min_value
	if is_zero_approx(span):
		return 0.0
	return clampf((v - min_value) / span, 0.0, 1.0)


func value_at_ratio(r: float) -> float:
	return _snap(min_value + clampf(r, 0.0, 1.0) * (max_value - min_value))


func _track_rect() -> Rect2:
	return Rect2(
		HANDLE_R, (size.y - TRACK_H) * 0.5,
		maxf(size.x - HANDLE_R * 2.0, 1.0), TRACK_H
	)


func _value_at_x(x: float) -> float:
	var track := _track_rect()
	return value_at_ratio((x - track.position.x) / track.size.x)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = _pick_handle(mb.position.x)
			_drag_to(mb.position.x)
			_consume()
		elif _dragging != 0:
			_dragging = 0
			drag_ended.emit(low_value, high_value)
			_consume()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging != 0:
		_drag_to(mm.position.x)
		_consume()


## accept_event() needs a viewport; the control must also work as a detached
## node so a headless test can drive it.
func _consume() -> void:
	if is_inside_tree():
		accept_event()


## Grab whichever handle is nearer the click; ties go to the low handle so a
## collapsed band can still be opened.
func _pick_handle(x: float) -> int:
	var track := _track_rect()
	var lx := track.position.x + ratio_of(low_value) * track.size.x
	var hx := track.position.x + ratio_of(high_value) * track.size.x
	return 1 if absf(x - lx) <= absf(x - hx) else 2


func _drag_to(x: float) -> void:
	var v := _value_at_x(x)
	var before := band()
	if _dragging == 1:
		low_value = minf(v, high_value)
	elif _dragging == 2:
		high_value = maxf(v, low_value)
	else:
		return
	if band() == before:
		return
	queue_redraw()
	range_changed.emit(low_value, high_value)


func _draw() -> void:
	var track := _track_rect()
	var accent := ThemeProbe.accent(self)
	var dim := ThemeProbe.dim_text(self)
	draw_rect(track, Color(dim.r, dim.g, dim.b, 0.35), true)
	var lx := track.position.x + ratio_of(low_value) * track.size.x
	var hx := track.position.x + ratio_of(high_value) * track.size.x
	draw_rect(
		Rect2(lx, track.position.y, maxf(hx - lx, 1.0), track.size.y),
		accent, true
	)
	var cy := size.y * 0.5
	draw_circle(Vector2(lx, cy), HANDLE_R, accent)
	draw_circle(Vector2(hx, cy), HANDLE_R, accent)


func _get_minimum_size() -> Vector2:
	return Vector2(80, maxf(HANDLE_R * 2.0 + 2.0, 20.0))
