extends PanelContainer
## Minimap dock: a north-up overview you can steer from.
##
## docs/02 §"the editor's overview panel" promised this and it was never
## built. Left-click flies the camera to the clicked point — the same
## click-to-go-there affordance the findings panel has — so the panel is a
## navigation control, not decoration.
##
## The panel owns the wiring; MinimapRaster owns the pixels and MinimapView
## owns the drawing and the pointer. Nothing here reaches into the 3D scene:
## a camera node, a height range map and a scatter source are all handed in,
## and every one of them is optional (C15).

signal fly_requested(world: Vector3)
signal overlay_changed(mode: int)
signal collapsed_changed(collapsed: bool)
signal hover_changed(on: bool)

const MENU_FINDINGS := 100
## Longest a coalesced repaint may be deferred. A brush stroke emits
## rect_dirty many times per frame; repainting once per interval keeps the
## minimap live without turning it into a per-frame cost (C17).
const REPAINT_INTERVAL_S := 0.08
## Microseconds of rasterising a single frame may spend. A whole-image
## repaint of a big map is tens of milliseconds; it is paid a slice at a time
## so no frame ever wears it (C17).
const PUMP_BUDGET_USEC := 3000

@onready var _view: MinimapView = %View
@onready var _mode_label: Label = %Mode

var _collapse: Button
var _collapsed: bool = false
var _menu: PopupMenu
var _camera: Node3D = null
var _range_source: Object = null
var _scatter_source: Object = null
var _bound_field: HeightField = null
var _full_dirty: bool = true
var _rect_pending: bool = false
var _rx0: int = 0
var _rz0: int = 0
var _rx1: int = 0
var _rz1: int = 0
var _since_repaint: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(200, 200)
	_install_collapse()
	_build_menu()
	_view.fly_requested.connect(_on_fly)
	_view.context_menu_requested.connect(_on_context_menu)
	_view.hover_changed.connect(func(on: bool) -> void: hover_changed.emit(on))
	var head := find_child("Head", true, false) as CanvasItem
	if head:
		head.visible = false
	var icon := find_child("TitleIcon", true, false)
	if icon is TextureRect and (icon as TextureRect).texture == null:
		(icon as TextureRect).texture = EditorIcons.texture("frame")
	MapState.session_changed.connect(_on_session)
	MapState.materials_changed.connect(_on_materials)
	_bind_field()
	mark_dirty()


func view() -> MinimapView:
	return _view


func overlay_mode() -> int:
	return _view.raster.mode


func set_overlay_mode(mode: int) -> void:
	if _view.raster.mode == mode:
		return
	_view.raster.set_mode(mode)
	_sync_menu()
	mark_dirty()
	var msg := "minimap overlay %s" % _view.raster.mode_name().to_lower()
	var note := _view.raster.degraded()
	if not note.is_empty():
		msg += " — " + note
	EditorFeedback.log(msg)
	overlay_changed.emit(_view.raster.mode)


## Hand over the camera to draw as position + heading. Any Node3D will do.
func set_camera(node: Node3D) -> void:
	_camera = node
	if node == null:
		_view.clear_camera_pose()


## Optional HeightRangeMap (%Terrain.ranges). Supplying it replaces a rescan
## of the sampled grid with one mip lookup for the relief ramp.
func set_range_source(source: Object) -> void:
	_range_source = source
	_view.raster.range_source = source
	mark_dirty()


## Optional scatter occupancy source; see MinimapData.attach_scatter for the
## two shapes accepted. Absent, the scatter overlay says so and shows relief.
func set_scatter_source(source: Object) -> void:
	_scatter_source = source
	mark_dirty()


func set_findings(list: Array) -> void:
	_view.set_findings(list)


func is_collapsed() -> bool:
	return _collapsed


func set_collapsed(on: bool) -> void:
	if _collapsed == on:
		return
	_collapsed = on
	_apply_collapse()
	collapsed_changed.emit(on)


## Queue a full rebuild of the snapshot and the image.
func mark_dirty() -> void:
	_full_dirty = true


## Queue a repaint of one inclusive cell rect only.
func mark_cells_dirty(x0: int, z0: int, x1: int, z1: int) -> void:
	if _full_dirty:
		return
	if not _rect_pending:
		_rect_pending = true
		_rx0 = x0
		_rz0 = z0
		_rx1 = x1
		_rz1 = z1
		return
	_rx0 = mini(_rx0, x0)
	_rz0 = mini(_rz0, z0)
	_rx1 = maxi(_rx1, x1)
	_rz1 = maxi(_rz1, z1)


## Apply everything queued and finish the image before returning. Callers who
## need a complete picture right now (and the tests) use this; the frame loop
## does not.
func flush() -> void:
	_apply_queued(true)


func _process(delta: float) -> void:
	if _collapsed or not is_visible_in_tree():
		return
	_since_repaint += delta
	if (_full_dirty or _rect_pending) and _since_repaint >= REPAINT_INTERVAL_S:
		_since_repaint = 0.0
		_apply_queued(false)
	elif _view.raster.painting():
		_view.raster.pump(PUMP_BUDGET_USEC)
		_view.queue_redraw()
	_poll_camera()


func _apply_queued(complete: bool) -> void:
	if _full_dirty:
		_full_dirty = false
		_rect_pending = false
		_rebuild(complete)
	elif _rect_pending:
		_rect_pending = false
		_view.raster.render_cell_rect(_rx0, _rz0, _rx1, _rz1)
		_view.queue_redraw()
	_refresh_mode_label()


func _poll_camera() -> void:
	if _camera == null or not _camera.is_inside_tree():
		return
	var xf := _camera.global_transform
	var fwd := -xf.basis.z
	if absf(fwd.x) + absf(fwd.z) < 0.001:
		# Straight down — 2D map mode. The screen-up axis is then the heading,
		# and FlyCamera.map_mode_basis() puts +z (north) there.
		fwd = xf.basis.y
	_view.update_camera_pose(xf.origin, fwd)


func _rebuild(complete: bool) -> void:
	var data := MinimapData.from_state(MapState, _scatter_source)
	_view.raster.range_source = _range_source
	if _view.raster.configure(data):
		if complete:
			_view.raster.render_all()
		else:
			_view.raster.begin_full()
	_view.queue_redraw()


func _on_session() -> void:
	_bind_field()
	_view.reset_view()
	_view.set_findings(MapState.findings)
	if not MapState.has_session:
		_view.clear_camera_pose()
	mark_dirty()
	# Start the repaint on the next frame rather than at the end of the load.
	_since_repaint = REPAINT_INTERVAL_S


## A material edit only changes pixels in the material overlay, so every other
## mode ignores it instead of paying for a whole-image repaint per stroke.
func _on_materials() -> void:
	if _view.raster.mode == MinimapRaster.Mode.MATERIAL:
		mark_dirty()


## MapState.clear() replaces the HeightField outright, so the binding has to
## follow the current instance rather than being made once.
func _bind_field() -> void:
	var field: HeightField = MapState.field
	if field == _bound_field:
		return
	if _bound_field != null:
		if _bound_field.rect_dirty.is_connected(mark_cells_dirty):
			_bound_field.rect_dirty.disconnect(mark_cells_dirty)
		if _bound_field.rebuilt.is_connected(mark_dirty):
			_bound_field.rebuilt.disconnect(mark_dirty)
	_bound_field = field
	if _bound_field == null:
		return
	_bound_field.rect_dirty.connect(mark_cells_dirty)
	_bound_field.rebuilt.connect(mark_dirty)


func _on_fly(world: Vector3) -> void:
	if not MapState.has_session:
		return
	fly_requested.emit(world)


func _on_context_menu(at: Vector2) -> void:
	if _menu == null:
		return
	_sync_menu()
	var p := _view.get_global_rect().position + at
	_menu.popup(Rect2i(int(p.x), int(p.y), 0, 0))


func _build_menu() -> void:
	_menu = PopupMenu.new()
	_menu.name = "OverlayMenu"
	for mode in [
		MinimapRaster.Mode.RELIEF, MinimapRaster.Mode.SLOPE,
		MinimapRaster.Mode.MATERIAL, MinimapRaster.Mode.SCATTER,
	]:
		_menu.add_radio_check_item(str(MinimapRaster.MODE_NAMES[mode]), mode)
	_menu.add_separator()
	_menu.add_check_item("Findings markers", MENU_FINDINGS)
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	_sync_menu()


func _on_menu_id(id: int) -> void:
	if id == MENU_FINDINGS:
		_view.show_findings = not _view.show_findings
		_view.queue_redraw()
		_sync_menu()
		return
	set_overlay_mode(id)


func _sync_menu() -> void:
	if _menu == null:
		return
	for i in _menu.item_count:
		var id := _menu.get_item_id(i)
		if id == MENU_FINDINGS:
			_menu.set_item_checked(i, _view.show_findings)
		elif not _menu.is_item_separator(i):
			_menu.set_item_checked(i, id == _view.raster.mode)


func _refresh_mode_label() -> void:
	if _mode_label == null:
		return
	var note := _view.raster.degraded()
	_mode_label.text = _view.raster.mode_name() if note.is_empty() else note
	_mode_label.tooltip_text = "Right-click the map to change the overlay"


func _install_collapse() -> void:
	var title := find_child("Title", true, false) as Label
	if title == null:
		return
	_collapse = PanelCollapse.make_toggle("Minimap", true)
	var parent := title.get_parent()
	parent.add_child(_collapse)
	parent.move_child(_collapse, title.get_index())
	title.visible = false
	_collapse.toggled.connect(func(on: bool) -> void: set_collapsed(not on))


func _apply_collapse() -> void:
	if _view:
		_view.visible = not _collapsed
	PanelCollapse.apply_toggle(_collapse, "Minimap", not _collapsed)
