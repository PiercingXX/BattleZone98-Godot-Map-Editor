extends Control
class_name MinimapView
## The minimap drawing + interaction surface. North is up, always (C8).
##
## Overlay: always the full map. Hold LMB to fly the camera to the world point
## under the cursor (emits while pressed and on motion). Right-click asks for
## the overlay menu. Hover is announced so the shell can park the 3D camera.

signal fly_requested(world: Vector3)
signal context_menu_requested(at: Vector2)
signal hover_changed(on: bool)

const MARGIN := 6.0
## Camera movement below these is not worth a repaint (C17).
const CAM_MOVE_EPS_M := 4.0
const CAM_TURN_EPS_RAD := 0.026

const EDGE := Color(1, 1, 1, 0.14)
const BACKDROP := Color(0.10, 0.10, 0.12, 1)
const CAM_FILL := Color(0.36, 0.72, 1.0, 0.95)
const CAM_EDGE := Color(0.04, 0.06, 0.10, 0.9)
const NORTH_TICK := Color(0.90, 0.90, 0.94, 0.75)
const SEVERITY := {
	"error": Color(0.95, 0.38, 0.34),
	"critical": Color(0.95, 0.38, 0.34),
	"warning": Color(0.95, 0.74, 0.28),
	"warn": Color(0.95, 0.74, 0.28),
	"info": Color(0.70, 0.74, 0.80),
	"note": Color(0.70, 0.74, 0.80),
}

var raster: MinimapRaster = MinimapRaster.new()
var show_findings: bool = true
var placeholder: String = "Open a map to see the overview."

var _zoom: float = 1.0
var _center: Vector2 = Vector2(0.5, 0.5)
var _findings: Array = []
var _cam_pos: Vector3 = Vector3.ZERO
var _cam_dir: Vector3 = Vector3.FORWARD
var _has_cam: bool = false
var _pressed: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size = Vector2(200, 200)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: hover_changed.emit(true))
	mouse_exited.connect(func() -> void: hover_changed.emit(false))


func data() -> MinimapData:
	return raster.data


func set_findings(list: Array) -> void:
	_findings = list
	queue_redraw()


## Store a camera pose, redrawing only when it moved enough to look different.
## Returns true when a repaint was scheduled.
func update_camera_pose(pos: Vector3, forward: Vector3) -> bool:
	var moved := not _has_cam \
			or Vector2(pos.x - _cam_pos.x, pos.z - _cam_pos.z).length() > CAM_MOVE_EPS_M \
			or absf(heading_map_dir(forward).angle_to(heading_map_dir(_cam_dir))) \
				> CAM_TURN_EPS_RAD
	_cam_pos = pos
	_cam_dir = forward
	_has_cam = true
	if moved:
		queue_redraw()
	return moved


func clear_camera_pose() -> void:
	_has_cam = false
	queue_redraw()


func reset_view() -> void:
	_zoom = 1.0
	_center = Vector2(0.5, 0.5)
	queue_redraw()


func zoom() -> float:
	return _zoom


## Screen-space rectangle the whole map occupies, aspect preserved.
func map_rect() -> Rect2:
	var inner := Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN * 2.0, MARGIN * 2.0))
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		return inner
	var d := data()
	var aspect := 1.0
	if d.depth_m() > 0.0:
		aspect = d.width_m() / d.depth_m()
	var w := inner.size.x
	var h := w / aspect
	if h > inner.size.y:
		h = inner.size.y
		w = h * aspect
	return Rect2(inner.position + (inner.size - Vector2(w, h)) * 0.5, Vector2(w, h))


## Visible slice of normalised map space. Overlay always shows the full map.
func region_uv() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2.ONE)


func norm_to_point(n: Vector2) -> Vector2:
	var m := map_rect()
	var r := region_uv()
	return m.position + Vector2(
		(n.x - r.position.x) / r.size.x, (n.y - r.position.y) / r.size.y
	) * m.size


func point_to_norm(p: Vector2) -> Vector2:
	var m := map_rect()
	var r := region_uv()
	if m.size.x <= 0.0 or m.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var t := (p - m.position) / m.size
	return r.position + t * r.size


func world_to_point(x_m: float, z_m: float) -> Vector2:
	return norm_to_point(data().world_to_norm(x_m, z_m))


func point_to_world(p: Vector2) -> Vector2:
	return data().norm_to_world(point_to_norm(p))


## Camera pose in normalised map space: position plus a unit heading.
## Empty when no pose has been supplied.
func camera_marker() -> Dictionary:
	if not _has_cam or not raster.ready():
		return {}
	return {
		"pos": data().world_to_norm(_cam_pos.x, _cam_pos.z),
		"dir": heading_map_dir(_cam_dir),
	}


## World XZ heading → normalised map space. North (+z) points at -y because
## north is the TOP of the image; east (+x) keeps +x. Getting this wrong is
## the mirrored-render defect docs/02 §north-up records, so it lives in one
## named function with a test on it.
static func heading_map_dir(forward: Vector3) -> Vector2:
	var v := Vector2(forward.x, -forward.z)
	if v.length_squared() < 0.000001:
		return Vector2.UP
	return v.normalized()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP, true)
	if not raster.ready() or raster.texture == null:
		_draw_placeholder()
		return
	var m := map_rect()
	var r := region_uv()
	var src := Rect2(
		r.position * Vector2(float(raster.tex_w), float(raster.tex_h)),
		r.size * Vector2(float(raster.tex_w), float(raster.tex_h))
	)
	draw_texture_rect_region(raster.texture, m, src)
	draw_rect(m, EDGE, false, 1.0)
	_draw_north(m)
	if show_findings:
		_draw_findings(m)
	_draw_camera(m)


func _draw_placeholder() -> void:
	var font := get_theme_font("font", "Label")
	if font == null:
		return
	var px := get_theme_font_size("font_size", "Label")
	var w := font.get_string_size(placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(
		font, Vector2((size.x - w) * 0.5, size.y * 0.5), placeholder,
		HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.62, 0.62, 0.64)
	)


func _draw_north(m: Rect2) -> void:
	var cx := m.position.x + m.size.x * 0.5
	draw_line(Vector2(cx, m.position.y), Vector2(cx, m.position.y + 5.0), NORTH_TICK, 1.0)
	var font := get_theme_font("font", "Label")
	if font == null:
		return
	draw_string(
		font, Vector2(cx + 3.0, m.position.y + 10.0), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, NORTH_TICK
	)


func _draw_findings(m: Rect2) -> void:
	for f in _findings:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var pos: Variant = (f as Dictionary).get("world_pos", null)
		if typeof(pos) != TYPE_ARRAY or (pos as Array).size() < 3:
			continue
		var p := world_to_point(float(pos[0]), float(pos[2]))
		if not m.has_point(p):
			continue
		var col: Color = SEVERITY.get(
			str((f as Dictionary).get("severity", "")).to_lower(),
			Color(0.88, 0.88, 0.90)
		)
		var d := PackedVector2Array([
			p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0),
		])
		draw_colored_polygon(d, col)
		draw_polyline(d + PackedVector2Array([d[0]]), CAM_EDGE, 1.0)


func _draw_camera(m: Rect2) -> void:
	var marker := camera_marker()
	if marker.is_empty():
		return
	var p := norm_to_point(marker["pos"])
	if not m.has_point(p):
		return
	var dir: Vector2 = marker["dir"]
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([
		p + dir * 9.0, p - dir * 5.0 + side * 5.0, p - dir * 5.0 - side * 5.0,
	])
	draw_colored_polygon(tri, CAM_FILL)
	draw_polyline(tri + PackedVector2Array([tri[0]]), CAM_EDGE, 1.0)


func _gui_input(event: InputEvent) -> void:
	if not raster.ready():
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)


func _on_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				context_menu_requested.emit(mb.position)
				accept_event()
		MOUSE_BUTTON_LEFT:
			_pressed = mb.pressed
			if mb.pressed:
				_fly_to(mb.position)
			accept_event()


func _on_motion(mm: InputEventMouseMotion) -> void:
	if not _pressed:
		return
	_fly_to(mm.position)
	accept_event()


func _fly_to(at: Vector2) -> void:
	if not map_rect().has_point(at):
		return
	var w := point_to_world(at)
	fly_requested.emit(Vector3(w.x, data().height_at_world(w.x, w.y), w.y))
