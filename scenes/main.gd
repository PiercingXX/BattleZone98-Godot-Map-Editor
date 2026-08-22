extends Control
## Coordinator: input, backend fan-out, session lifecycle.

const TerrainRaycastScript = preload("res://project/terrain/TerrainRaycast.gd")
const DarkThemeScript = preload("res://project/ui/DarkTheme.gd")
const SelectionGizmoScript = preload("res://project/objects/SelectionGizmo.gd")
const HeightStrokeCommandScript = preload("res://project/commands/HeightStrokeCommand.gd")

@onready var _console: Control = %Console
@onready var _toasts: Control = %ToastLayer
@onready var _prefs: Window = %PrefsDialog
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _new_dialog: ConfirmationDialog = %NewDialog
@onready var _new_guard: ConfirmationDialog = %NewGuardDialog
@onready var _template_option: OptionButton = %TemplateOption
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog
@onready var _stem_edit: LineEdit = %StemEdit
@onready var _world_option: OptionButton = %WorldOption
@onready var _size_option: OptionButton = %SizeOption
@onready var _size_z: OptionButton = %SizeZ
@onready var _pack_kind: OptionButton = %PackKind
@onready var _terrain: Node3D = %Terrain
@onready var _objects: Node3D = %Objects
@onready var _balance: Node3D = %BalanceOverlay
var _aipaths: AiPathOverlay
@onready var _camera: Camera3D = %Camera
@onready var _center: Control = %Center
@onready var _viewport: SubViewport = %SubViewport
@onready var _mid_split: HSplitContainer = %Mid
@onready var _right_col: Control = %Right
@onready var _top = %TopBar
@onready var _viewp = %ViewPanel
@onready var _rail = %ToolRail
@onready var _palette = %PalettePanel
@onready var _inspector = %InspectorPanel
@onready var _features = %FeaturesPanel
@onready var _findings = %FindingsPanel
@onready var _history = %HistoryPanel
@onready var _status = %StatusBar
@onready var _start = %StartScreen
@onready var _compass: Control = %CompassRose
@onready var _help = %HelpWindow
@onready var _probe = %ProbeDialog
@onready var _gallery = %MapGalleryDialog
@onready var _world_env: WorldEnvironment = %WorldEnvironment
@onready var _sun: DirectionalLight3D = %Sun

var _sculpt = SculptTool.new()
## Accumulator for 10 Hz UI work (status text, label culling).
var _ui_tick_acc: float = 0.0
var _io: SessionIO
var _game_test: GameTest
var _workshop: WorkshopPublish
var _stroking: bool = false
var _mask_stroking: bool = false
var _mask_erase: bool = false
var _show_grid: bool = false
var _setting_tool: bool = false
var _ramp_a: Vector3 = Vector3.INF
var _ramp_b: Vector3 = Vector3.INF
var _ramp_dragging: bool = false
var _last_stamp: Vector3 = Vector3.INF
var _pending_package: String = ""
var _probe_explicit: bool = false
var _save_as: bool = false
var _quit_after_save: bool = false
var _smoke_path: String = ""
var _smoke_save: String = ""
var _smoke_sculpt: bool = false
var _select_pressing: bool = false
var _select_marquee: bool = false
var _select_from: Vector2 = Vector2.ZERO
var _select_to: Vector2 = Vector2.ZERO
var _select_shift: bool = false
var _select_press_id: String = ""
var _hover_status: bool = false
var _marquee: Control
var _sel_stroking: bool = false
var _sel_subtract: bool = false
var _tsel_rect: bool = false
var _tsel_from: Vector3 = Vector3.INF
var _tsel_to: Vector3 = Vector3.INF
var _tsel_shift: bool = false
var _tsel_alt: bool = false
var _heightmap_export_dialog: FileDialog
var _heightmap_import_dialog: FileDialog
var _restore_dialog: ConfirmationDialog
var _restore_session_dir: String = ""
var _binary_dialog: AcceptDialog
var _binary_command: String = ""
var _measuring: bool = false
var _measure_from: Vector3 = Vector3.INF
var _measure_to: Vector3 = Vector3.INF
var _measure_mesh: MeshInstance3D
var _aipath_bar: HBoxContainer
var _btn_add_path: Button
var _btn_del_path: Button
var _btn_add_pt: Button
var _btn_del_pt: Button
var _aipath_dragging: bool = false
var _aipath_drag_path: int = -1
var _aipath_drag_point: int = -1
var _aipath_drag_before: Array = []
var _aipath_moved: bool = false
var _aipath_drag_was_dirty: bool = false
var _autosave: Timer
var _layout_timer: Timer
var _layout_applying: bool = false
var _compass_yaw: float = 0.0
var _gizmo: SelectionGizmo
var _gizmo_dragging: bool = false
var _gizmo_handle: String = ""
var _gizmo_start_hit: Vector3 = Vector3.ZERO
var _gizmo_pivot: Vector3 = Vector3.ZERO
var _gizmo_dx: float = 0.0
var _gizmo_dz: float = 0.0
var _gizmo_dyaw: float = 0.0


func _ready() -> void:
	randomize()
	theme = DarkThemeScript.make()
	Settings.apply_ui_scale(get_window())
	add_to_group("editor_shell")
	get_tree().auto_accept_quit = false
	_io = SessionIO.new(self, _log)
	_game_test = GameTest.new()
	_game_test.name = "GameTest"
	_game_test.log = _log
	add_child(_game_test)
	_workshop = WorkshopPublish.new()
	_workshop.name = "WorkshopPublish"
	_workshop.log = _log
	add_child(_workshop)
	_install_heightmap_dialogs()
	_install_restore_dialog()
	_install_binary_dialog()
	_install_measure_line()
	_install_aipath_overlay()
	_wire()
	_install_layout_persistence()
	_apply_layout_settings()
	_refresh_start_screen()
	_apply_world_lighting()
	MapState.world_changed.connect(_apply_world_lighting)
	_name_right_tabs()
	_try_load_asset_index()
	_pack_kind.add_item("BZP map", 0)
	_pack_kind.add_item("Base-game map", 1)
	for size in [1280, 2560, 3840, 5120]:
		_size_option.add_item("%s m" % size, size)
		_size_z.add_item("%s m" % size, size)
	_install_size_link()
	_autosave = Timer.new()
	_autosave.name = "Autosave"
	_autosave.timeout.connect(_on_autosave)
	add_child(_autosave)
	_apply_autosave()
	_refresh_map_label()
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if not version.is_empty():
		get_window().title = "BattleZone 98 Godot Map Editor  v%s" % version
	var auto_n := Settings.coerce_autosave_interval(Settings.autosave_interval_s)
	var auto_txt := "Autosave is off." if auto_n <= 0 else "Unsaved sessions autosave every %ds." % auto_n
	_log.call("BattleZone 98 Godot Map Editor v%s. F1 help. %s Open a map to sculpt and place." % [version, auto_txt])
	Backend.probe()
	_queue_smoke_open()
	if not _is_automated():
		call_deferred("_check_crash_recovery")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if MapState.unsaved:
			_quit_dialog.popup_centered()
		else:
			quit_clean()


func _wire() -> void:
	_top.open_requested.connect(_io.open_prompt)
	_top.gallery_requested.connect(_io.gallery_prompt)
	_top.recent_open_requested.connect(_io.open_file)
	if _gallery:
		_gallery.map_open_requested.connect(_io.open_file)
	if _start:
		_start.new_requested.connect(_io.new_prompt)
		_start.open_requested.connect(_io.open_prompt)
		_start.gallery_requested.connect(_io.gallery_prompt)
		_start.recent_open_requested.connect(_io.open_file)
		_start.template_requested.connect(_on_start_template)
	_top.new_requested.connect(_io.new_prompt)
	_top.save_requested.connect(_io.save)
	_top.save_as_requested.connect(func(): _save_as = true; _io.save(true))
	_top.validate_requested.connect(_io.validate)
	_top.test_requested.connect(_io.test_in_game)
	_top.more_selected.connect(_on_more_selected)
	_rail.tool_selected.connect(_set_tool)
	_top.variant_changed.connect(func():
		MapState.active_variant = _top.selected_variant()
		_on_objects_mutated()
	)
	_top.undo_requested.connect(func(): UndoStack.undo())
	_top.redo_requested.connect(func(): UndoStack.redo())
	_top.frame_requested.connect(camera_frame)
	_top.map_mode_requested.connect(_toggle_map_mode)
	_viewp.view_changed.connect(_apply_view_settings)
	if _status.has_signal("goto_submitted"):
		_status.goto_submitted.connect(_on_goto_submitted)
	_palette.class_armed.connect(func(rec):
		_arm_class(rec)
	)
	_palette.selection_query_applied.connect(func():
		if _objects:
			_objects.highlight(MapState.selected_ids)
		_fill_inspector()
	)
	_inspector.apply_requested.connect(func(edits):
		EditActions.apply_inspector(edits)
		_on_objects_mutated()
	)
	_inspector.delete_requested.connect(func():
		EditActions.delete_selected(_log)
		_on_objects_mutated()
	)
	_inspector.water_changed.connect(MapState.set_water_level)
	_findings.finding_selected.connect(_on_finding_select)
	_findings.finding_activated.connect(_on_finding_fly)
	_findings.validate_requested.connect(_io.validate)
	_rail.log_toggled.connect(_on_console_toggled)
	_wire_panel_collapse()
	_probe.install_chosen.connect(_io.choose_install)
	_quit_dialog.confirmed.connect(_io.quit_save)
	_quit_dialog.add_button("Discard", true, "discard")
	_quit_dialog.custom_action.connect(func(a):
		if a == "discard":
			quit_clean()
	)
	_new_guard.confirmed.connect(_io.new_after_save)
	_new_guard.add_button("Discard changes", true, "discard")
	_new_guard.custom_action.connect(func(a):
		if a == "discard":
			_new_guard.hide()
			_io.show_new_dialog()
	)
	%Center.gui_input.connect(_on_view_gui_input)
	%Center.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_dialog.canceled.connect(func():
		_quit_after_save = false
		_save_as = false
		_pending_package = ""
	)
	Backend.discovered.connect(_on_discovered)
	Backend.call_started.connect(_on_call_started)
	Backend.call_finished.connect(_on_call_finished)
	Backend.call_failed.connect(_on_call_failed)
	MapState.session_changed.connect(_on_session_changed)
	MapState.objects_mutated.connect(_on_objects_mutated)
	MapState.aipaths_changed.connect(_refresh_aipath_bar)
	MapState.materials_changed.connect(_on_materials_changed)
	MapState.object_poses_changed.connect(_on_object_poses_changed)
	MapState.dirty_changed.connect(func():
		if MapState.findings_stale and not MapState.findings.is_empty():
			_findings.set_findings(MapState.findings, true)
	)
	UndoStack.changed.connect(_refresh_map_label)
	ToolState.tool_changed.connect(_on_tool_state)
	ToolState.brush_changed.connect(_sync_sculpt)
	ToolState.armed_changed.connect(func():
		if ToolState.armed.is_empty():
			_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
	)
	ToolState.mask_target_changed.connect(_refresh_mask_overlay)
	ToolState.mask_paint_changed.connect(_refresh_mask_overlay)
	MapState.mask_changed.connect(_refresh_mask_overlay)
	MapState.features_changed.connect(_refresh_mask_overlay)
	MapState.water_changed.connect(func(_l): _refresh_mask_overlay())
	MapState.selection_changed.connect(_refresh_selection_overlay)
	if _camera.has_signal("speed_changed"):
		_camera.speed_changed.connect(func(mps): _status.set_status("transient", "cam %.0f m/s" % mps))
	if _camera.has_signal("map_mode_changed"):
		_camera.map_mode_changed.connect(_on_map_mode_changed)
	_install_compass()
	_sync_sculpt()
	if _features == null:
		push_error("FeaturesPanel missing from main.tscn")
	_marquee = Control.new()
	_marquee.name = "MarqueeOverlay"
	_marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marquee.z_index = 20
	_marquee.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marquee.draw.connect(_on_marquee_draw)
	_center.add_child(_marquee)
	_apply_view_settings()
	_refresh_aipath_bar()
	_install_selection_gizmo()


func _process(_delta: float) -> void:
	_refresh_compass()
	# Status text, hover pick, and label culling are 10 Hz work; running
	# them every frame (and per high-poll-rate mouse event) is the main
	# CPU cost of an idle frame.
	_ui_tick_acc += _delta
	var ui_tick := _ui_tick_acc >= 0.1
	if ui_tick:
		_ui_tick_acc = 0.0
		_status.set_debug("%d fps  chunks %d  up %d B" % [
			int(Engine.get_frames_per_second()),
			_terrain.get_child_count() if _terrain else 0,
			_sculpt.last_uploaded,
		])
	if _gizmo_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_gizmo_drag()
	elif _gizmo_dragging:
		_update_gizmo_drag()
	if _select_pressing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_select_gesture()
	elif _select_pressing:
		_update_select_drag(_viewport.get_mouse_position())
	if _aipath_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_aipath_drag()
	elif _aipath_dragging:
		_update_aipath_drag()
	if _ramp_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_ramp_drag()
	elif _ramp_dragging:
		_update_ramp_drag()
	if _measuring:
		_update_measure_drag()
	if not MapState.has_session:
		_status.set_selection_count(0, false)
		return
	_sync_gizmo()
	if ui_tick and _objects and _objects.has_method("refresh_labels"):
		_objects.refresh_labels(_camera)
	var over_view := _center.get_global_rect().has_point(get_global_mouse_position())
	if not over_view:
		_terrain.set_brush(false, Vector2.ZERO, 0.0, 0.0, false)
		_update_select_hover(false)
		_flush_live_gpu()
		return
	_update_select_hover(true)
	var hit := _pick()
	if hit.get("hit", false):
		var p: Vector3 = hit["position"]
		_camera.pivot = p
		var nav := (
			"wheel zoom  MMB/Space+LMB pan  WASD pan"
			if _camera.map_mode
			else "RMB look  Ctrl+RMB orbit  Shift+RMB pan  wheel zoom  WASD fly"
		)
		_status.set_cursor("xz %.1f, %.1f  h %.1f m  mat %d  %s   ·  %s" % [
			p.x, p.z, p.y, MapState.material_at(p.x, p.z), ToolState.tool, nav,
		])
		var sculpting := ToolState.is_mask_painting() or ToolState.tool in ["raise", "lower", "flatten", "smooth", "ramp", "noise", "paint", "qsel", "clone"]
		if sculpting:
			_terrain.set_brush(true, Vector2(p.x, p.z), ToolState.radius_m, ToolState.falloff, ToolState.shape == "square")
		elif ToolState.tool == "place" and ToolState.effective_symmetry() != ToolState.SYMMETRY_OFF:
			_terrain.set_brush(true, Vector2(p.x, p.z), 12.0, 0.35, false)
		else:
			_terrain.set_brush(false, Vector2.ZERO, 0.0, 0.0, false)
		if ToolState.tool == "place" and not ToolState.armed.is_empty():
			var ghost := ToolState.armed.duplicate()
			var snapped := EditActions.snap_world_xz(p.x, p.z)
			ghost["x"] = snapped.x
			ghost["z"] = snapped.y
			ghost["y"] = MapState.field.height_at(snapped.x, snapped.y) if MapState.field else p.y
			_objects.set_ghost(true, ghost, MapState.field, hit.get("normal", Vector3.UP))
	if _stroking and hit.get("hit", false) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var p2: Vector3 = hit["position"]
		# March along the drag segment at even spacing: a fast drag used
		# to land one dab per frame, leaving gaps that made strokes feel
		# jerky. Density per metre is now constant at any mouse speed.
		var spacing := maxf(HeightField.CELL_M, ToolState.radius_m * 0.15)
		# Never bridge a jump the mouse cannot have made continuously. At a
		# grazing camera angle one pixel of travel can move the terrain hit
		# hundreds of metres, and bridging that painted a streak from the
		# cursor to the far side of the map. Past the cutoff the stroke
		# teleports instead: the brush only ever touches ground within its
		# own radius of where the cursor actually is.
		var bridge_max := maxf(ToolState.radius_m * 3.0, HeightField.CELL_M * 8.0)
		if _last_stamp.distance_to(p2) > bridge_max:
			_last_stamp = p2
			_stamp_at(p2)
		var guard := 0
		while _last_stamp.distance_to(p2) >= spacing and guard < 64:
			guard += 1
			var dir := (p2 - _last_stamp) / _last_stamp.distance_to(p2)
			var at := _last_stamp + dir * spacing
			_stamp_at(at)
			_last_stamp = at
	_flush_live_gpu()


func _stamp_at(at: Vector3) -> void:
	## One dab of the live stroke at a world point.
	if _sel_stroking:
		var mode := MapState.SEL_SUBTRACT if _sel_subtract else MapState.SEL_ADD
		var pts: Array[Vector2] = ToolState.world_image_points(at.x, at.z)
		if pts.is_empty():
			pts = [Vector2(at.x, at.z)]
		for pt in pts:
			MapState.stamp_terrain_selection(
				pt.x, pt.y, ToolState.radius_m, ToolState.falloff, ToolState.shape, mode
			)
	else:
		_sculpt.stamp(MapState.field, at.x, at.z)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if Keymap.resolve(k) != Keymap.ACTION_FOCUS:
		return
	if EditActions.gui_text_focused(get_viewport()):
		return
	_toggle_focus_mode()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	var handled := true
	# Escape always disarms; in the GIMP scheme it is also tool.fly.
	if (
		Keymap.resolve(k) == Keymap.ACTION_FOCUS
		and EditActions.gui_text_focused(get_viewport())
	):
		return
	if k.keycode == KEY_ESCAPE:
		if _gizmo_dragging:
			_cancel_gizmo_drag()
		if _select_pressing:
			_cancel_select_gesture()
		if _aipath_dragging:
			_cancel_aipath_drag()
		if _tsel_rect:
			_cancel_terrain_rect()
		if _ramp_dragging:
			_cancel_ramp_drag()
		if _measuring:
			_clear_measure()
			_log.call("measure cancelled")
		ToolState.clear_armed()
		if ToolState.mask_paint:
			ToolState.set_mask_paint(false)
			_log.call("mask paint off")
	# Object-select rotate/nudge keeps R even when R is also rect-select.
	if (
		not k.ctrl_pressed
		and not k.alt_pressed
		and not EditActions.gui_text_focused(get_viewport())
		and EditActions.try_select_transform(k.keycode, k.shift_pressed, _log)
	):
		_on_objects_mutated()
		get_viewport().set_input_as_handled()
		return
	var action := Keymap.resolve(k)
	if not action.is_empty():
		if (
			(
				action.begins_with("team.")
				or action.begins_with("select.")
				or action.begins_with("bookmark.")
			)
			and EditActions.gui_text_focused(get_viewport())
		):
			handled = false
		elif action == Keymap.ACTION_MAP_MODE and EditActions.gui_text_focused(get_viewport()):
			handled = false
		else:
			_apply_keymap_action(action)
	elif k.keycode == KEY_QUOTELEFT:
		_set_console_visible(not Settings.console_visible, true)
	elif k.keycode == KEY_DELETE:
		if _try_delete_aipath():
			pass
		else:
			EditActions.delete_selected(_log)
			_on_objects_mutated()
	elif k.keycode == KEY_ESCAPE:
		_set_tool("fly")
	elif k.keycode == KEY_BRACKETLEFT:
		ToolState.set_strength(maxf(0.05, ToolState.strength - 0.05)) if k.shift_pressed else ToolState.set_radius(maxf(5, ToolState.radius_m - 5))
	elif k.keycode == KEY_BRACKETRIGHT:
		ToolState.set_strength(minf(1.0, ToolState.strength + 0.05)) if k.shift_pressed else ToolState.set_radius(minf(400, ToolState.radius_m + 5))
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _apply_keymap_action(action: String) -> void:
	if action.begins_with("tool."):
		_set_tool(action.get_slice(".", 1))
		return
	if action.begins_with("team."):
		var team := Keymap.team_from_action(action)
		if team < 0:
			return
		EditActions.set_selection_team(team, _log)
		_on_objects_mutated()
		return
	if action.begins_with("bookmark."):
		_handle_bookmark(action)
		return
	match action:
		"help":
			_help.popup_help()
		"grid":
			_show_grid = not _show_grid
			Settings.view_grid = _show_grid
			Settings.save()
			_apply_grid()
		"focus":
			if not EditActions.gui_text_focused(get_viewport()):
				_toggle_focus_mode()
		"undo":
			UndoStack.undo()
		"redo":
			UndoStack.redo()
		"save":
			_io.save()
		"walk":
			Settings.walk_mode = not Settings.walk_mode
			Settings.save()
			_log.call("walk mode %s" % Settings.walk_mode)
		"frame":
			camera_frame()
		"top_down":
			if _camera.map_mode:
				pass
			elif MapState.has_session:
				_camera.top_down(float(MapState.width_m), float(MapState.depth_m))
		"map_mode":
			_toggle_map_mode()
		"slope_overlay":
			if _terrain.has_method("set_slope_overlay"):
				_terrain._show_slope = not _terrain._show_slope
				_terrain.set_slope_overlay(_terrain._show_slope)
				Settings.view_slope = _terrain._show_slope
				Settings.save()
				_log.call("slope overlay %s" % ("on" if _terrain._show_slope else "off"))
		"select.all":
			EditActions.select_all_terrain(_log)
		"select.none":
			EditActions.deselect_terrain(_log)
		"select.invert":
			EditActions.invert_terrain(_log)


func _on_view_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.handle_event(event)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _camera.map_mode and (Input.is_key_pressed(KEY_SPACE) or _camera.panning):
				if mb.pressed:
					_camera.begin_pan()
				else:
					_camera.end_pan()
				accept_event()
				return
			if not mb.pressed:
				if _measuring:
					_finish_measure()
				_on_lmb_up()
				if _gizmo_dragging:
					_finish_gizmo_drag()
				if _aipath_dragging:
					_finish_aipath_drag()
				if _select_pressing:
					_finish_select_gesture()
				if _tsel_rect:
					_finish_terrain_rect()
				if _ramp_dragging:
					_finish_ramp_drag()
			elif ToolState.tool == "select" and Input.is_key_pressed(KEY_M):
				var measure_hit := _pick()
				if measure_hit.get("hit", false):
					_begin_measure(measure_hit["position"])
				else:
					_log.call("nothing to measure")
			elif ToolState.is_mask_painting():
				var mask_hit := _pick()
				if mask_hit.get("hit", false):
					_on_lmb_down(mask_hit["position"], mask_hit, mb.shift_pressed, mb.alt_pressed, mb.ctrl_pressed)
				else:
					_log.call("nothing to paint")
			elif ToolState.tool == "paint" and mb.alt_pressed:
				# Eyedropper: sample only — never start a paint stroke.
				var sample := _pick()
				if sample.get("hit", false):
					var p: Vector3 = sample["position"]
					_palette.sample_tile(MapState.material_word_at(p.x, p.z))
				else:
					_log.call("nothing to sample")
			elif ToolState.tool == "select" and _try_begin_gizmo_drag():
				pass
			elif ToolState.tool == "select" and _begin_aipath_gesture(mb.shift_pressed):
				pass
			elif ToolState.tool == "select" and _try_begin_object_drag(mb.shift_pressed):
				pass
			elif ToolState.tool == "select":
				_begin_select_gesture(mb.shift_pressed)
			else:
				var hit := _pick()
				if hit.get("hit", false):
					_on_lmb_down(hit["position"], hit, mb.shift_pressed, mb.alt_pressed, mb.ctrl_pressed)
			accept_event()
	elif event is InputEventMouseMotion:
		if _camera.map_mode and _camera.panning:
			_camera.handle_event(event)
			accept_event()
			return
		if _gizmo_dragging:
			_update_gizmo_drag()
			accept_event()
		elif _aipath_dragging:
			_update_aipath_drag()
			accept_event()
		elif _select_pressing:
			_update_select_drag(_viewport.get_mouse_position())
			accept_event()
		elif _tsel_rect:
			var hit2 := _pick()
			if hit2.get("hit", false):
				_tsel_to = hit2["position"]
			if _marquee:
				_marquee.queue_redraw()
			accept_event()
		elif _camera.looking or _camera.orbiting or _camera.pan_dragging:
			_camera.handle_event(event)
			accept_event()
		else:
			# The camera also owns the buttonless modifier moves
			# (Ctrl+move orbit, Shift+move pan); it ignores plain motion.
			_camera.handle_event(event)


func _on_lmb_down(p: Vector3, hit: Dictionary, shift: bool, alt: bool = false, ctrl: bool = false) -> void:
	if ToolState.is_mask_painting():
		_begin_mask_stroke(p, alt)
		return
	if ToolState.tool == "place" and not ToolState.armed.is_empty():
		if shift:
			# Shift+click removes the object under the cursor instead of
			# stacking another one on top of it.
			var mouse := _viewport.get_mouse_position()
			var hit_id: String = _objects.pick(
				_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse)
			)
			if hit_id.is_empty():
				_log.call("nothing to delete here")
			else:
				MapState.selected_ids = [hit_id] as Array[String]
				EditActions.delete_selected(_log)
				_on_objects_mutated()
			return
		EditActions.place_at(p, hit.get("normal", Vector3.UP), true, _log)
		return
	if ToolState.tool == "clone" and ctrl:
		ToolState.set_clone_source(p.x, p.z)
		_log.call("clone source %.1f, %.1f" % [p.x, p.z])
		return
	if ToolState.tool == "qsel":
		_begin_selection_stroke(p, alt)
		return
	if ToolState.tool == "rsel":
		_begin_terrain_rect(p, shift, alt)
		return
	if ToolState.tool == "wand":
		_apply_wand(p, shift, alt)
		return
	if ToolState.tool == "ramp":
		_begin_ramp_drag(p)
		return
	if ToolState.tool == "clone":
		if not ToolState.has_clone_source():
			_log.call("Ctrl+click to set the clone source")
			return
		_sync_sculpt()
		_sculpt.begin_stroke(MapState.field, p.x, p.z, false)
		_stroking = true
		_last_stamp = p
		return
	if ToolState.tool in ["raise", "lower", "flatten", "smooth", "noise", "paint"]:
		_sync_sculpt()
		_sculpt.begin_stroke(MapState.field, p.x, p.z, ToolState.tool == "paint")
		_stroking = true
		_last_stamp = p


func _on_lmb_up() -> void:
	if not _stroking:
		return
	_stroking = false
	if _sel_stroking:
		_sel_stroking = false
		MapState.flush_gpu()
		_log.call(EditActions.terrain_selection_log("erase" if _sel_subtract else "add"))
		return
	if _mask_stroking:
		_mask_stroking = false
		var mask_cmd = _sculpt.end_mask_paint()
		if mask_cmd:
			UndoStack.push(mask_cmd)
			var mode := "erase" if _mask_erase else "paint"
			_log.call("%s mask %s" % [mode, ToolState.mask_stem])
		MapState.flush_gpu()
		return
	if ToolState.tool == "paint":
		var paint_cmd = _sculpt.end_paint()
		if paint_cmd:
			UndoStack.push(paint_cmd)
	else:
		var cmd2 = _sculpt.end_stroke(MapState.field)
		if cmd2:
			UndoStack.push(cmd2, true)
			if ToolState.tool == "clone":
				_log.call("clone stamp")
	MapState.flush_gpu()
	_on_object_poses_changed()


func _begin_selection_stroke(p: Vector3, subtract: bool) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log.call("open a map first")
		return
	if subtract and MapState.selection_empty():
		_log.call("no selection")
		return
	_sel_subtract = subtract
	_sel_stroking = true
	_stroking = true
	_last_stamp = p
	var mode := MapState.SEL_SUBTRACT if subtract else MapState.SEL_ADD
	var pts: Array[Vector2] = ToolState.world_image_points(p.x, p.z)
	if pts.is_empty():
		pts = [Vector2(p.x, p.z)]
	for pt in pts:
		MapState.stamp_terrain_selection(
			pt.x, pt.y, ToolState.radius_m, ToolState.falloff, ToolState.shape, mode
		)


func _begin_terrain_rect(p: Vector3, shift: bool, alt: bool) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log.call("open a map first")
		return
	_tsel_rect = true
	_tsel_from = p
	_tsel_to = p
	_tsel_shift = shift
	_tsel_alt = alt
	if _marquee:
		_marquee.queue_redraw()


func _finish_terrain_rect() -> void:
	if not _tsel_rect:
		return
	_tsel_rect = false
	if _marquee:
		_marquee.queue_redraw()
	if not MapState.has_heightmap():
		return
	var mode := EditActions.terrain_combine_mode(_tsel_shift, _tsel_alt)
	if mode == MapState.SEL_SUBTRACT and MapState.selection_empty():
		_log.call("no selection")
		return
	var cell := HeightField.CELL_M
	var x0 := int(floor(minf(_tsel_from.x, _tsel_to.x) / cell))
	var z0 := int(floor(minf(_tsel_from.z, _tsel_to.z) / cell))
	var x1 := int(floor(maxf(_tsel_from.x, _tsel_to.x) / cell))
	var z1 := int(floor(maxf(_tsel_from.z, _tsel_to.z) / cell))
	MapState.rect_terrain_selection(x0, z0, x1, z1, mode)
	_log.call(EditActions.terrain_selection_log("rect"))


func _cancel_terrain_rect() -> void:
	if not _tsel_rect:
		return
	_tsel_rect = false
	if _marquee:
		_marquee.queue_redraw()


func _apply_wand(p: Vector3, shift: bool, alt: bool) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		_log.call("open a map first")
		return
	var mode := EditActions.terrain_combine_mode(shift, alt)
	if mode == MapState.SEL_SUBTRACT and MapState.selection_empty():
		_log.call("no selection")
		return
	var cell := HeightField.CELL_M
	var sx := int(floor(p.x / cell))
	var sz := int(floor(p.z / cell))
	MapState.wand_terrain_selection(sx, sz, ToolState.wand_tolerance_m, mode)
	_log.call(EditActions.terrain_selection_log("wand"))


func _refresh_selection_overlay() -> void:
	if _terrain == null or not _terrain.has_method("set_selection_mask"):
		return
	if MapState.selection_empty():
		_terrain.set_selection_mask(false)
		return
	if MapState.selection_texture == null:
		MapState.upload_terrain_selection()
	if MapState.selection_texture == null:
		_terrain.set_selection_mask(false)
		return
	_terrain.set_selection_mask(true, MapState.selection_texture)


func _begin_mask_stroke(p: Vector3, erase: bool) -> void:
	if not MapState.has_session:
		_log.call("open a map to paint a region")
		return
	if ToolState.mask_stem.is_empty():
		_log.call("select a water body or plant region to paint")
		return
	if not MapState.has_heightmap():
		_log.call("map has no heightmap to paint")
		return
	_sync_sculpt()
	var value := 0 if erase else 255
	_mask_erase = erase
	_sculpt.begin_mask_stroke(MapState.field, p.x, p.z, ToolState.mask_stem, value)
	_stroking = true
	_mask_stroking = true
	_last_stamp = p


func _refresh_mask_overlay() -> void:
	if _terrain == null or not _terrain.has_method("set_feature_mask"):
		return
	var stem := ToolState.mask_stem
	var kind := ToolState.mask_kind
	if stem.is_empty() or kind.is_empty() or not MapState.has_session:
		_terrain.set_feature_mask(false)
		return
	MapState.upload_mask(stem)
	if MapState.mask_texture == null:
		_terrain.set_feature_mask(false)
		return
	var tint := Color(0.12, 0.32, 0.62) if kind == "water" else Color(0.16, 0.62, 0.28)
	var lvl := -1.0
	if kind == "water":
		var rec := MapState.find_feature("water", stem)
		lvl = float(rec.get("level_m", -1.0))
	_terrain.set_feature_mask(true, MapState.mask_texture, tint, lvl)


func _set_tool(name: String) -> void:
	if _setting_tool:
		return
	_setting_tool = true
	ToolState.set_tool(name)
	_setting_tool = false


func _on_tool_state(name: String) -> void:
	_sculpt.mode = name
	# TopBar subscribes to ToolState.tool_changed itself.
	_apply_grid()
	if name != "ramp":
		_cancel_ramp_drag()
	if name != "place":
		_objects.set_ghost(false, {}, MapState.field, Vector3.UP)
	if name != "select":
		_cancel_gizmo_drag()
		_cancel_select_gesture()
		if _measuring:
			_clear_measure()
		_objects.set_hover("")
		_clear_hover_status()
		_status.set_selection_count(0, false)
		if _gizmo:
			_gizmo.hide_gizmo()
	else:
		_status.set_selection_count(MapState.selected_ids.size(), MapState.has_session)
		_sync_gizmo()
	if name != "rsel":
		_cancel_terrain_rect()


func preview_sun_minutes(minutes: int) -> void:
	## Live drag feedback from the World panel: move the light now, leave the
	## map edit to the panel's release handler.
	_place_sun(minutes)


func _place_sun(minutes: int) -> void:
	if _sun == null:
		return
	var dir := WorldLighting.sun_to_light_direction(minutes)
	# Basis.looking_at needs an up that is not parallel to the direction, and
	# a noon sun points straight down.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var xf := _sun.global_transform
	xf.basis = Basis.looking_at(dir, up)
	_sun.global_transform = xf
	_sun.light_energy = WorldLighting.sun_energy(minutes)


func _apply_world_lighting() -> void:
	## Sun clock + fog, from the map's [NormalView] values onto the viewport.
	_place_sun(MapState.sun_minutes())
	if _world_env == null or _world_env.environment == null:
		return
	var env: Environment = _world_env.environment
	var on: bool = Settings.view_fog and MapState.has_session
	env.fog_enabled = on
	if not on:
		return
	# Linear depth fog, not the exponential default: the game's FogStart /
	# FogEnd are two distances with a straight ramp between them, and an
	# exponential falloff would not show the mapmaker what they are setting.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.0
	var fog := WorldLighting.clamp_fog(
		float(MapState.world_setting("fog_start_m")),
		float(MapState.world_setting("fog_end_m"))
	)
	env.fog_depth_begin = fog.x
	env.fog_depth_end = maxf(fog.y, fog.x + 1.0)
	env.fog_light_color = MapState.fog_color()
	env.fog_density = 1.0
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0


func _sync_sculpt() -> void:
	_sculpt.radius_m = ToolState.radius_m
	_sculpt.strength = ToolState.strength
	_sculpt.falloff = ToolState.falloff
	_sculpt.shape = ToolState.shape
	_sculpt.paint_material = ToolState.paint_material
	_sculpt.mode = ToolState.tool


func _apply_grid() -> void:
	if _terrain.has_method("set_show_grid"):
		_terrain.set_show_grid(_show_grid or ToolState.tool == "paint")


func _pick() -> Dictionary:
	if not MapState.has_session:
		return {"hit": false}
	var mouse := _viewport.get_mouse_position()
	return TerrainRaycastScript.intersect(_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse), MapState.field)


func _on_discovered(ok: bool, detail: String) -> void:
	_log.call(detail)
	_status.set_status("ok" if ok else "error", "backend ready" if ok else "backend missing")


func _on_call_started(verb: String) -> void:
	_status.set_status("busy", StatusBar.verb_activity_text(verb))
	_top.set_busy(true)


func _on_call_finished(verb: String, result: Dictionary) -> void:
	_top.set_busy(false)
	_status.set_status("ok", "ok: %s" % verb)
	match verb:
		"probe":
			# Only interrupt with the install picker when there is a choice
			# to make (no saved root) or the user explicitly asked via More →
			# Re-probe; routine startup probes stay silent.
			var explicit := _probe_explicit
			_probe_explicit = false
			if not _is_smoke() and (
				explicit
				or Settings.game_root.is_empty()
				or (result.get("installs", []) as Array).is_empty()
			):
				_probe.show_probe(result)
			if not Settings.game_root.is_empty() and not _is_smoke():
				Backend.worlds(Settings.game_root)
				_try_load_asset_index()
			if not Settings.game_root.is_empty() and not FileAccess.file_exists(MapState.cache_dir().path_join("index.json")):
				_log.call("first run: importing asset index (icons). Import assets again to convert meshes.")
				Backend.assets(Settings.game_root, MapState.cache_dir(), false, false)
			if not _smoke_path.is_empty():
				var path := _smoke_path
				_smoke_path = ""
				Backend.open_map(path, MapState.new_session_dir())
		"worlds":
			MapState.worlds = result.get("worlds", [])
			if MapState.worlds.is_empty():
				SessionIO.fill_world_dropdown(_world_option, SessionIO.stock_worlds())
			else:
				SessionIO.fill_world_dropdown(_world_option, MapState.worlds)
			if MapState.has_session and _terrain.has_method("refresh_materials"):
				_terrain.refresh_materials()
			_palette.refresh_swatches()
		"open", "new":
			MapState.load_from_open(result)
			if verb == "open":
				_io.record_open_if_pending()
			if not _io.template_stem.is_empty():
				MapState.stem = _io.template_stem
				_io.template_stem = ""
				MapState.note_unsaved()
				_refresh_map_label()
			for w in result.get("warnings", []):
				_log.call("warning: %s" % w, "warning")
			if _is_smoke():
				if not _smoke_save.is_empty():
					var out := _smoke_save
					_smoke_save = ""
					if _smoke_sculpt:
						_smoke_sculpt = false
						if _smoke_apply_sculpt():
							_log.call("smoke: applied 11x11 plateau at raw 3333 from (250,250)")
						else:
							_log.call("smoke: sculpt skipped (no heightfield)", "warning")
					MapState.persist()
					Backend.save_map(MapState.session_dir, out, MapState.stem)
				else:
					quit_clean(0)
		"save":
			MapState.mark_saved()
			_refresh_map_label()
			_log.call("saved %d files to %s" % [
				(result.get("files", []) as Array).size(), Settings.last_save_dir,
			], "info", true)
			_log.call("byte-identical: %s" % ", ".join(PackedStringArray(result.get("byte_identical", []))))
			var regen: Array = result.get("regenerated", [])
			if not regen.is_empty():
				_log.call("regenerated: %s" % ", ".join(PackedStringArray(regen)))
			for w2 in result.get("warnings", []):
				_log.call("warning: %s" % w2, "warning")
			if result.has("features"):
				_log.call("features: %s" % result["features"])
			if _quit_after_save:
				quit_clean()
			if _is_smoke():
				quit_clean(0)
			if _io.consume_new_after_save():
				_io.show_new_dialog()
		"validate":
			MapState.findings = result.get("findings", [])
			MapState.findings_stale = false
			_findings.set_findings(MapState.findings, false)
			_log.call("%d findings (not an in-game verdict)" % MapState.findings.size())
		"assets":
			MapState.asset_index = result
			MapState.rebuild_lookups()
			Settings.last_cache_fingerprint = str(result.get("source_fingerprint", ""))
			Settings.save()
			_fill_palette()
			_log.call("%d classes  %d unresolved  fidelity mostly proxy" % [
				result.get("classes", []).size(), result.get("unresolved", []).size(),
			], "info", true)
		"render":
			_log.call("thumbnail %s" % result.get("png", ""))
		"package":
			var pkg_mode := str(result.get("mode", ""))
			_log.call("package %s: %d files → %s" % [
				pkg_mode, (result.get("files", []) as Array).size(),
				result.get("dest", ""),
			], "info", pkg_mode == "addon")
			var shared: Array = result.get("shared_lua", [])
			if not shared.is_empty():
				_log.call("bundled shared lua: %s" % ", ".join(PackedStringArray(shared)))
			# The save that staged this package can warn (runtime spawns,
			# dropped .lgt, skipped variants). Dropping those made a
			# half-encoded map look like a clean install.
			for w3 in result.get("warnings", []):
				_log.call("warning: %s" % w3, "warning")


func _on_call_failed(verb: String, error: Dictionary) -> void:
	if verb == "open":
		_io.clear_pending_open()
	if verb == "save":
		# A failed save must not leave quit / new-map / package intents
		# armed for the next save that succeeds.
		_quit_after_save = false
		_save_as = false
		_pending_package = ""
		_io.consume_new_after_save()
	_top.set_busy(false)
	_set_console_visible(true, true)
	_status.set_status("error", "error: %s" % verb)
	_log.call("ERROR [%s] %s" % [error.get("code", "?"), error.get("message", error)], "error", true)
	if error.has("hint"):
		_log.call("  hint: %s" % error["hint"], "warning")
	if verb == "open" and str(error.get("code", "")) == "binary_bzn_unsupported" and not _is_automated():
		_show_binary_bzn_dialog(error)
	if _is_smoke() and verb != "probe":
		quit_clean(1)


func _is_smoke() -> bool:
	return OS.get_cmdline_user_args().has("--smoke-open")


func _is_automated() -> bool:
	if _is_smoke():
		return true
	for arg in OS.get_cmdline_args():
		if str(arg).ends_with("run_tests.gd") or str(arg).contains("run_tests.gd"):
			return true
	return false


func quit_clean(code: int = 0) -> void:
	_flush_layout(true)
	SessionIO.write_clean_exit()
	get_tree().quit(code)


static func measure_meters(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b)


static func measure_log_line(meters: float) -> String:
	return "measured %.1f m" % meters


func _try_load_asset_index() -> void:
	var idx := MapState.cache_dir().path_join("index.json")
	if not FileAccess.file_exists(idx):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx))
	if typeof(parsed) == TYPE_DICTIONARY:
		MapState.asset_index = parsed
		MapState.rebuild_lookups()
		_fill_palette()


func _fill_palette() -> void:
	var pack: Dictionary = MapState.manifest.get("pack_context", {})
	_palette.set_classes(MapState.asset_index, str(pack.get("kind", "bzp")))


func _arm_class(rec: Dictionary) -> void:
	if str(rec.get("mesh", "")).is_empty() and not Settings.game_root.is_empty():
		var converted: Dictionary = BzAssets.ensure_converted_mesh(
			str(rec.get("prjid", "")),
			Settings.game_root,
			MapState.cache_dir(),
		)
		var mesh := str(converted.get("path", ""))
		if not mesh.is_empty():
			rec = rec.duplicate()
			rec["mesh"] = mesh
			rec["mesh_fidelity"] = str(converted.get("fidelity", "hd"))
			_patch_asset_mesh(str(rec.get("prjid", "")), mesh, str(rec.get("mesh_fidelity", "hd")))
	ToolState.set_armed(rec)
	_log.call("armed %s  %s  %s" % [rec.get("prjid"), rec.get("placement_mode"), rec.get("mesh_fidelity")])


func _patch_asset_mesh(prjid: String, mesh: String, fidelity: String) -> void:
	var classes: Variant = MapState.asset_index.get("classes", [])
	if typeof(classes) != TYPE_ARRAY:
		return
	var key := prjid.to_lower()
	for item in classes:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item.get("prjid", "")).to_lower() != key:
			continue
		item["mesh"] = mesh
		item["mesh_fidelity"] = fidelity
		break
	MapState.rebuild_lookups()


func _on_finding_select(f: Dictionary) -> void:
	var oid := str(f.get("object_id", ""))
	if oid.is_empty():
		return
	MapState.selected_ids = [oid] as Array[String]
	_objects.highlight(MapState.selected_ids)
	_fill_inspector()


func _on_finding_fly(f: Dictionary) -> void:
	_on_finding_select(f)
	var pos = f.get("world_pos", null)
	if typeof(pos) != TYPE_ARRAY or (pos as Array).size() < 3:
		var rec := MapState.find_object(str(f.get("object_id", "")))
		if not rec.is_empty():
			pos = [rec.get("x", 0.0), rec.get("y", 0.0), rec.get("z", 0.0)]
	if typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
		camera_hover(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))


func _fill_inspector() -> void:
	if MapState.selected_ids.is_empty():
		_inspector.clear()
	else:
		_inspector.show_object(MapState.find_object(MapState.selected_ids[0]))
	if ToolState.tool == "select" and MapState.has_session:
		_status.set_selection_count(MapState.selected_ids.size(), true)


func _install_selection_gizmo() -> void:
	if _gizmo != null:
		return
	var world := _objects.get_parent() if _objects else null
	if world == null:
		return
	_gizmo = SelectionGizmoScript.new()
	_gizmo.name = "SelectionGizmo"
	world.add_child(_gizmo)


func _selection_records() -> Array:
	var recs: Array = []
	for id in MapState.selected_ids:
		var rec := MapState.find_object(id)
		if rec.is_empty():
			continue
		recs.append(rec)
	return recs


func _sync_gizmo() -> void:
	if _gizmo == null:
		return
	var show := (
		ToolState.tool == "select"
		and MapState.has_session
		and not MapState.selected_ids.is_empty()
		and not _select_marquee
	)
	if not show:
		_gizmo.hide_gizmo()
		return
	var recs := _selection_records()
	if recs.is_empty():
		_gizmo.hide_gizmo()
		return
	var pivot := SelectionGizmo.selection_pivot(recs)
	if _gizmo_dragging:
		if is_zero_approx(_gizmo_dyaw):
			pivot.x += _gizmo_dx
			pivot.z += _gizmo_dz
			if MapState.field:
				pivot.y = MapState.field.height_at(pivot.x, pivot.z)
	var highlight := _gizmo_handle if _gizmo_dragging else _gizmo.hover_handle()
	_gizmo.sync_at(pivot, _camera, highlight)
	if _gizmo_dragging:
		_gizmo.set_active_handle(_gizmo_handle)


func _try_begin_object_drag(shift: bool) -> bool:
	## Press straight on an object and it starts moving on X/Z at once — no
	## trip through the gizmo handle. Shift is left to the selection gesture so
	## shift+click still adds to and removes from the selection.
	if shift or not MapState.has_session:
		return false
	var mouse := _viewport.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var id: String = _objects.pick(origin, dir)
	if id.is_empty():
		return false
	if not MapState.selected_ids.has(id):
		EditActions.select_id(id, false, _log)
		_objects.highlight(MapState.selected_ids)
		_fill_inspector()
	var recs := _selection_records()
	if recs.is_empty():
		return false
	_gizmo_pivot = SelectionGizmo.selection_pivot(recs)
	var plane := SelectionGizmo.ray_ground(origin, dir, _gizmo_pivot.y)
	if not plane.is_finite():
		return false
	_gizmo_dragging = true
	_gizmo_handle = SelectionGizmo.HANDLE_XZ
	_gizmo_start_hit = plane
	_gizmo_dx = 0.0
	_gizmo_dz = 0.0
	_gizmo_dyaw = 0.0
	if _gizmo:
		_gizmo.set_active_handle(SelectionGizmo.HANDLE_XZ)
	_objects.set_hover("")
	return true


func _try_begin_gizmo_drag() -> bool:
	_sync_gizmo()
	if _gizmo == null or not _gizmo.visible:
		return false
	var mouse := _viewport.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var hit: Dictionary = _gizmo.pick(origin, dir)
	var handle := str(hit.get("handle", ""))
	if handle.is_empty():
		return false
	var recs := _selection_records()
	if recs.is_empty():
		return false
	_gizmo_dragging = true
	_gizmo_handle = handle
	_gizmo_pivot = SelectionGizmo.selection_pivot(recs)
	var plane := SelectionGizmo.ray_ground(origin, dir, _gizmo_pivot.y)
	if not plane.is_finite():
		plane = hit.get("point", _gizmo_pivot)
	_gizmo_start_hit = plane
	_gizmo_dx = 0.0
	_gizmo_dz = 0.0
	_gizmo_dyaw = 0.0
	_gizmo.set_active_handle(handle)
	_objects.set_hover("")
	return true


func _update_gizmo_drag() -> void:
	if not _gizmo_dragging:
		return
	var mouse := _viewport.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var now := SelectionGizmo.ray_ground(origin, dir, _gizmo_pivot.y)
	if not now.is_finite():
		return
	if _gizmo_handle == SelectionGizmo.HANDLE_YAW:
		_gizmo_dx = 0.0
		_gizmo_dz = 0.0
		_gizmo_dyaw = SelectionGizmo.yaw_delta_deg(
			_gizmo_pivot, _gizmo_start_hit, now, ToolState.snap_angle
		)
	else:
		_gizmo_dyaw = 0.0
		var delta := SelectionGizmo.move_delta(
			_gizmo_handle, _gizmo_pivot, _gizmo_start_hit, now, ToolState.snap_grid_m
		)
		_gizmo_dx = delta.x
		_gizmo_dz = delta.z
	var recs := _selection_records()
	if _objects and _objects.has_method("preview_poses"):
		_objects.preview_poses(SelectionGizmo.preview_poses(
			recs, _gizmo_dx, _gizmo_dz, _gizmo_dyaw, _gizmo_pivot, MapState.field
		))
	_sync_gizmo()


func _finish_gizmo_drag() -> void:
	if not _gizmo_dragging:
		return
	var dx := _gizmo_dx
	var dz := _gizmo_dz
	var dyaw := _gizmo_dyaw
	var pivot := _gizmo_pivot
	_gizmo_dragging = false
	_gizmo_handle = ""
	_gizmo_dx = 0.0
	_gizmo_dz = 0.0
	_gizmo_dyaw = 0.0
	if _gizmo:
		_gizmo.set_active_handle("")
	if _objects and _objects.has_method("restore_placed"):
		_objects.restore_placed()
	if is_zero_approx(dx) and is_zero_approx(dz) and is_zero_approx(dyaw):
		# A press with no travel is a click, not a move. Say nothing.
		_sync_gizmo()
		return
	EditActions.apply_selection_transform(dx, dz, dyaw, pivot, _log)
	_on_objects_mutated()


func _cancel_gizmo_drag() -> void:
	if not _gizmo_dragging:
		return
	_gizmo_dragging = false
	_gizmo_handle = ""
	_gizmo_dx = 0.0
	_gizmo_dz = 0.0
	_gizmo_dyaw = 0.0
	if _gizmo:
		_gizmo.set_active_handle("")
	if _objects and _objects.has_method("restore_placed"):
		_objects.restore_placed()
	_sync_gizmo()
	_log.call("gizmo cancelled")


func _begin_ramp_drag(p: Vector3) -> void:
	## Ramp is a press-drag-release gesture: A is where the button went down,
	## B follows the cursor, and the ramp is cut on release.
	if not MapState.has_session or not MapState.has_heightmap():
		_log.call("open a map first")
		return
	_ramp_a = p
	_ramp_b = p
	_ramp_dragging = true
	_sync_marquee_overlay()
	if _marquee:
		_marquee.queue_redraw()


func _update_ramp_drag() -> void:
	if not _ramp_dragging:
		return
	var hit := _pick()
	if hit.get("hit", false):
		_ramp_b = hit["position"]
	_sync_marquee_overlay()
	if _marquee:
		_marquee.queue_redraw()
	_status.set_cursor(_ramp_readout())


func _finish_ramp_drag() -> void:
	if not _ramp_dragging:
		return
	var a := _ramp_a
	var b := _ramp_b
	_ramp_dragging = false
	_ramp_a = Vector3.INF
	_ramp_b = Vector3.INF
	if _marquee:
		_marquee.queue_redraw()
	if not a.is_finite() or not b.is_finite():
		return
	if Vector2(b.x - a.x, b.z - a.z).length() < 1.0:
		_log.call("ramp needs a drag, not a click")
		return
	_sync_sculpt()
	EditActions.apply_ramp(_sculpt, a, b, _log)
	MapState.flush_gpu()
	_on_object_poses_changed()


func _cancel_ramp_drag() -> void:
	var was := _ramp_dragging
	_ramp_dragging = false
	_ramp_a = Vector3.INF
	_ramp_b = Vector3.INF
	if _marquee:
		_marquee.queue_redraw()
	if was:
		_log.call("ramp cancelled")


func _ramp_readout() -> String:
	var run := Vector2(_ramp_b.x - _ramp_a.x, _ramp_b.z - _ramp_a.z).length()
	var rise := _ramp_b.y - _ramp_a.y
	var deg := 0.0 if run < 0.001 else rad_to_deg(atan2(absf(rise), run))
	return "ramp  %.0f m   rise %+.1f m   %.1f°  (30° is the climb limit)" % [run, rise, deg]


func _begin_select_gesture(shift: bool) -> void:
	_select_from = _viewport.get_mouse_position()
	_select_to = _select_from
	_select_shift = shift
	_select_press_id = _objects.pick(
		_camera.project_ray_origin(_select_from),
		_camera.project_ray_normal(_select_from),
	)
	_select_pressing = true
	_select_marquee = false
	_sync_marquee_overlay()
	if _marquee:
		_marquee.queue_redraw()


func _sync_marquee_overlay() -> void:
	if _marquee == null or _center == null:
		return
	_marquee.position = Vector2.ZERO
	_marquee.size = _center.size


func _update_select_drag(pos: Vector2) -> void:
	_select_to = pos
	_sync_marquee_overlay()
	if _select_marquee:
		if _marquee:
			_marquee.queue_redraw()
		return
	if _select_press_id.is_empty() and EditActions.is_marquee_drag(_select_from, pos):
		_select_marquee = true
		_objects.set_hover("")
		if _marquee:
			_marquee.queue_redraw()


func _finish_select_gesture() -> void:
	if not _select_pressing:
		return
	var was_marquee := _select_marquee
	var press_id := _select_press_id
	var shift := _select_shift
	_select_pressing = false
	_select_marquee = false
	_select_press_id = ""
	if _marquee:
		_marquee.queue_redraw()
	if was_marquee:
		var rect := EditActions.screen_rect_from_drag(_select_from, _select_to)
		var ids := EditActions.filter_visible_ids(
			EditActions.ids_in_screen_rect(_objects.screen_points(_camera), rect)
		)
		EditActions.select_marquee(ids, shift, _log)
	elif not press_id.is_empty():
		EditActions.select_id(press_id, shift, _log)
	else:
		EditActions.select_click(_objects, _camera, _viewport, shift, _log)
	_objects.highlight(MapState.selected_ids)
	_fill_inspector()


func _cancel_select_gesture() -> void:
	if not _select_pressing and not _select_marquee:
		return
	_select_pressing = false
	_select_marquee = false
	_select_press_id = ""
	if _marquee:
		_marquee.queue_redraw()


func _update_select_hover(over_view: bool) -> void:
	if ToolState.tool != "select" or not MapState.has_session:
		_objects.set_hover("")
		_clear_hover_status()
		_status.set_selection_count(0, false)
		return
	_status.set_selection_count(MapState.selected_ids.size(), true)
	if not over_view or _select_marquee or _gizmo_dragging:
		if not _gizmo_dragging and _gizmo:
			_gizmo.set_hover_handle("")
		_objects.set_hover("")
		_clear_hover_status()
		return
	var mouse := _viewport.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if _gizmo and _gizmo.visible:
		var gh: Dictionary = _gizmo.pick(origin, dir)
		var handle := str(gh.get("handle", ""))
		_gizmo.set_hover_handle(handle)
		if not handle.is_empty():
			_objects.set_hover("")
			_clear_hover_status()
			return
	var hid: String = _objects.pick(origin, dir)
	_objects.set_hover(hid)
	if hid.is_empty():
		_clear_hover_status()
		return
	var rec := MapState.find_object(hid)
	_status.set_status("transient", EditActions.hover_status_text(
		str(rec.get("prjid", "")),
		str(rec.get("label", "")),
	))
	_hover_status = true


func _clear_hover_status() -> void:
	if not _hover_status:
		return
	_hover_status = false
	if _status.get("_kind") == "transient":
		_status.set_status("info", "")


func _on_marquee_draw() -> void:
	if _marquee == null:
		return
	if _select_marquee:
		var box := EditActions.screen_rect_from_drag(_select_from, _select_to)
		_marquee.draw_rect(box, Color(0.25, 0.7, 1.0, 0.14), true)
		_marquee.draw_rect(box, Color(0.55, 0.88, 1.0, 0.95), false, 1.5)
		return
	if _tsel_rect and _tsel_from.x < 1.0e8:
		var a := _camera.unproject_position(_tsel_from)
		var b := _camera.unproject_position(_tsel_to)
		var box2 := EditActions.screen_rect_from_drag(a, b)
		_marquee.draw_rect(box2, Color(0.35, 0.55, 1.0, 0.16), true)
		_marquee.draw_rect(box2, Color(0.70, 0.85, 1.0, 0.95), false, 1.5)
		return
	if _ramp_dragging and _ramp_a.is_finite() and _ramp_b.is_finite():
		_draw_ramp_guide()


func _draw_ramp_guide() -> void:
	## 2D overlay, drawn over the viewport image — the guide stays readable
	## across a hill that would swallow a line drawn in the 3D scene.
	var a := _camera.unproject_position(_ramp_a)
	var b := _camera.unproject_position(_ramp_b)
	var shadow := Color(0.05, 0.05, 0.07, 0.85)
	var ink := Color(0.98, 0.86, 0.28, 1.0)
	_marquee.draw_dashed_line(a + Vector2.ONE, b + Vector2.ONE, shadow, 3.0, 9.0)
	_marquee.draw_dashed_line(a, b, ink, 2.0, 9.0)
	_marquee.draw_circle(a, 4.0, shadow)
	_marquee.draw_circle(a, 2.5, ink)
	_marquee.draw_circle(b, 4.0, shadow)
	_marquee.draw_circle(b, 2.5, ink)
	var font := _marquee.get_theme_default_font()
	if font == null:
		return
	var size := _marquee.get_theme_default_font_size()
	var text := _ramp_readout()
	var at := b + Vector2(12.0, -10.0)
	_marquee.draw_string(font, at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	_marquee.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


func _on_session_changed() -> void:
	_cancel_gizmo_drag()
	if _gizmo:
		_gizmo.hide_gizmo()
	if _compass:
		_compass.visible = MapState.has_session
	if _top.has_method("set_map_mode"):
		_top.set_map_mode(_camera.map_mode)
	_refresh_start_screen()
	if _objects.has_method("reset"):
		_objects.reset()
	_refresh_map_label()
	_top.fill_variants(MapState.manifest.get("variants", [""]), MapState.active_variant)
	_try_load_asset_index()
	_fill_palette()
	_inspector.set_water(MapState.water_level())
	_findings.set_findings(MapState.findings, MapState.findings_stale)
	_refresh_mask_overlay()
	_refresh_selection_overlay()
	_apply_view_settings()
	_apply_world_lighting()
	if not MapState.has_session:
		return
	if _terrain.has_method("rebuild"):
		_terrain.rebuild(MapState.field)
	_on_objects_mutated()
	camera_frame()
	_terrain.refresh_materials()
	_palette.refresh_swatches()


func _flush_live_gpu() -> void:
	if not MapState.has_session:
		return
	var uploaded := MapState.flush_gpu()
	_sculpt.last_uploaded = uploaded
	if _objects and _objects.has_method("pump_meshes"):
		_objects.pump_meshes(1)


func _on_object_poses_changed() -> void:
	if _objects and _objects.has_method("sync_poses"):
		_objects.sync_poses(MapState.field)


func _on_objects_mutated() -> void:
	if _objects.has_method("rebuild"):
		_objects.rebuild(MapState.objects, MapState.field)
	_objects.highlight(MapState.selected_ids)
	_sync_gizmo()
	if _objects and _objects.has_method("refresh_labels"):
		_objects.refresh_labels(_camera)
	_fill_inspector()
	_refresh_map_label()
	if _balance and _balance.has_method("schedule_recompute"):
		_balance.schedule_recompute()
	if _aipaths and _aipaths.has_method("rebuild"):
		_aipaths.rebuild()
	_refresh_aipath_bar()


func _on_materials_changed() -> void:
	if _terrain.has_method("refresh_materials"):
		_terrain.refresh_materials()


func _refresh_map_label() -> void:
	if not MapState.has_session:
		_top.set_map_label("no map open")
		_status.set_map_info("")
		return
	_top.set_map_label("%s%s" % [MapState.stem, "*" if MapState.unsaved else ""])
	_status.set_map_info("%sx%s  %s" % [MapState.width_m, MapState.depth_m, MapState.world])
	if MapState.ceiling_hit:
		_status.set_status("error", "hit raw 4095 ceiling")


func _apply_view_settings() -> void:
	if _objects and _objects.has_method("apply_visibility"):
		_objects.apply_visibility()
	EditActions.deselect_hidden(_log)
	if _objects:
		_objects.highlight(MapState.selected_ids)
		if _objects.has_method("refresh_labels"):
			_objects.refresh_labels(_camera)
	_sync_gizmo()
	_fill_inspector()
	if _terrain and _terrain.has_method("set_water_visible"):
		_terrain.set_water_visible(Settings.view_water)
	_apply_plants_view()
	_apply_sky_view()
	_apply_balance_view()
	_apply_aipaths_view()


func _apply_balance_view() -> void:
	if _balance == null or not _balance.has_method("set_active"):
		return
	_balance.set_active(BalanceOverlay.enabled and MapState.has_session)


func _apply_aipaths_view() -> void:
	if _aipaths == null:
		return
	_aipaths.set_active(AiPathOverlay.enabled and MapState.has_session)
	_refresh_aipath_bar()


func _apply_plants_view() -> void:
	if _terrain == null:
		return
	if ToolState.mask_kind == "plants":
		if Settings.view_plants:
			_refresh_mask_overlay()
		else:
			_terrain.set_feature_mask(false)


func _apply_sky_view() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	if Settings.view_sky:
		env.background_mode = Environment.BG_SKY
		if env.sky == null:
			var sky := Sky.new()
			var mat := ProceduralSkyMaterial.new()
			mat.sky_top_color = Color(0.22, 0.42, 0.72)
			mat.sky_horizon_color = Color(0.68, 0.74, 0.82)
			mat.ground_bottom_color = Color(0.14, 0.13, 0.12)
			mat.ground_horizon_color = Color(0.38, 0.34, 0.28)
			sky.sky_material = mat
			env.sky = sky
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.04, 0.045, 0.055, 1)


func camera_frame() -> void:
	if not MapState.has_session or MapState.field.grid_x < 2:
		return
	_camera.frame_map(float(MapState.width_m), float(MapState.depth_m), MapState.field.height_at(float(MapState.width_m) * 0.5, float(MapState.depth_m) * 0.5))


func camera_hover(world: Vector3) -> void:
	if _camera.has_method("hover_point"):
		_camera.hover_point(world)
	else:
		_camera.global_position = FlyCamera.hover_perspective_position(world)
		_camera.look_at(world, Vector3.UP)


func _toggle_map_mode() -> void:
	if not MapState.has_session:
		_log.call("open a map first")
		if _top.has_method("set_map_mode"):
			_top.set_map_mode(_camera.map_mode)
		return
	_camera.set_map_mode(not _camera.map_mode)


func _on_map_mode_changed(on: bool) -> void:
	if _top.has_method("set_map_mode"):
		_top.set_map_mode(on)
	if _compass:
		_compass.queue_redraw()
	_log.call("2D map mode" if on else "3D camera")


func _on_goto_submitted(text: String) -> void:
	if not MapState.has_session:
		_log.call("open a map first")
		return
	var xz := FlyCamera.parse_goto(text)
	if not xz.is_finite():
		_log.call("cannot parse go-to")
		return
	var y := 0.0
	if MapState.field != null and MapState.field.grid_x > 1:
		y = MapState.field.height_at(xz.x, xz.y)
	camera_hover(Vector3(xz.x, y, xz.y))
	_log.call("go to %.1f, %.1f" % [xz.x, xz.y])


func _install_compass() -> void:
	if _compass == null:
		_compass = Control.new()
		_compass.name = "CompassRose"
		_compass.custom_minimum_size = Vector2(76, 76)
		_compass.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_compass.offset_left = -84.0
		_compass.offset_top = 8.0
		_compass.offset_right = -8.0
		_compass.offset_bottom = 84.0
		_compass.mouse_filter = Control.MOUSE_FILTER_STOP
		_center.add_child(_compass)
	_compass.mouse_filter = Control.MOUSE_FILTER_STOP
	_compass.visible = MapState.has_session
	if not _compass.draw.is_connected(_on_compass_draw):
		_compass.draw.connect(_on_compass_draw)
	if not _compass.gui_input.is_connected(_on_compass_gui_input):
		_compass.gui_input.connect(_on_compass_gui_input)
	_compass.queue_redraw()


func _refresh_compass() -> void:
	if _compass == null or not _compass.visible:
		return
	var rose := 0.0
	if _camera and not _camera.map_mode:
		rose = FlyCamera.rose_radians_from_look(-_camera.global_transform.basis.z)
	if absf(rose - _compass_yaw) < 0.0005:
		return
	_compass_yaw = rose
	_compass.queue_redraw()


func _on_compass_draw() -> void:
	if _compass == null:
		return
	var center := _compass.size * 0.5
	var radius := minf(_compass.size.x, _compass.size.y) * 0.5 - 1.0
	var rose := 0.0 if (_camera != null and _camera.map_mode) else _compass_yaw
	_compass.draw_circle(center, radius, Color(0.08, 0.09, 0.11, 0.82))
	_compass.draw_arc(center, radius, 0.0, TAU, 36, Color(0.38, 0.40, 0.44, 0.95), 1.4, true)
	var arms: Array = [
		{"id": "N", "dir": Vector2(0.0, -1.0), "color": Color(0.95, 0.38, 0.34)},
		{"id": "E", "dir": Vector2(1.0, 0.0), "color": Color(0.78, 0.80, 0.84)},
		{"id": "S", "dir": Vector2(0.0, 1.0), "color": Color(0.78, 0.80, 0.84)},
		{"id": "W", "dir": Vector2(-1.0, 0.0), "color": Color(0.78, 0.80, 0.84)},
	]
	for arm in arms:
		var dir: Vector2 = (arm["dir"] as Vector2).rotated(rose)
		var tip := center + dir * (radius - 4.0)
		var side := Vector2(-dir.y, dir.x) * 3.0
		var base := center + dir * 12.0
		var col: Color = arm["color"]
		_compass.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), col)
		var label_at := center + dir * (radius - 13.0)
		var font := _compass.get_theme_default_font()
		var fs := 11
		if font:
			var txt := str(arm["id"])
			var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			_compass.draw_string(
				font,
				label_at - Vector2(sz.x * 0.5, -sz.y * 0.25),
				txt,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				fs,
				col,
			)
	_compass.draw_circle(center, 10.0, Color(0.22, 0.52, 0.78, 0.96))
	_compass.draw_arc(center, 10.0, 0.0, TAU, 20, Color(0.90, 0.92, 0.95, 0.9), 1.2, true)


func _on_compass_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var rose := 0.0 if (_camera != null and _camera.map_mode) else _compass_yaw
	var hit := FlyCamera.compass_hit(mb.position, _compass.size, rose)
	if hit.is_empty():
		return
	if hit == "center":
		_toggle_map_mode()
		_compass.accept_event()
		return
	if hit == "n":
		if _camera.has_method("snap_yaw_north"):
			_camera.snap_yaw_north()
		_log.call("facing north")
		_compass_yaw = 0.0
		if _compass:
			_compass.queue_redraw()
		_compass.accept_event()


func _refresh_start_screen() -> void:
	if _start == null:
		return
	if MapState.has_session:
		_start.hide_start()
	else:
		_start.show_start()


func _on_start_template(trn: String) -> void:
	_io.new_prompt()
	if _template_option == null:
		return
	var want := trn.strip_edges()
	for i in _template_option.item_count:
		if str(_template_option.get_item_metadata(i)) == want:
			_template_option.select(i)
			_log.call("new-from-template prefilled %s" % want.get_base_dir().get_file())
			return


func _on_console_toggled(on: bool) -> void:
	_set_console_visible(on, true)


func _set_console_visible(on: bool, persist: bool) -> void:
	if persist:
		Settings.console_visible = on
		Settings.save()
	if _console:
		_console.visible = on
	if _status:
		_rail.set_log_visible(on)


func _toggle_focus_mode() -> void:
	Settings.focus_mode = not Settings.focus_mode
	Settings.save()
	_apply_focus_mode()
	_log.call("focus mode %s" % ("on" if Settings.focus_mode else "off"))


func _apply_focus_mode() -> void:
	var focus := Settings.focus_mode
	if _palette:
		_palette.visible = not focus
	if _right_col:
		_right_col.visible = not focus
	if focus:
		if _console:
			_console.visible = false
		if _status:
			_rail.set_log_visible(false)
	else:
		_apply_split_offsets()
		if _console:
			_console.visible = Settings.console_visible
		if _status:
			_rail.set_log_visible(Settings.console_visible)


func _install_layout_persistence() -> void:
	_layout_timer = Timer.new()
	_layout_timer.name = "LayoutSaveTimer"
	_layout_timer.one_shot = true
	_layout_timer.wait_time = Settings.LAYOUT_SAVE_IDLE_S
	_layout_timer.timeout.connect(_on_layout_idle)
	add_child(_layout_timer)
	for split in [
		_mid_split,
		_right_col,
		find_child("SplitB", true, false),
	]:
		if split == null:
			continue
		if split.has_signal("dragged"):
			split.dragged.connect(_on_split_dragged)


func _wire_panel_collapse() -> void:
	_connect_collapse(_palette, "collapse_palette")
	_connect_collapse(_inspector, "collapse_inspector")
	_connect_collapse(_features, "collapse_features")
	_connect_collapse(_findings, "collapse_findings")
	_connect_collapse(_history, "collapse_history")


func _connect_collapse(panel: Object, key: String) -> void:
	if panel == null or not panel.has_signal("collapsed_changed"):
		return
	panel.collapsed_changed.connect(func(on: bool) -> void:
		match key:
			"collapse_palette":
				Settings.collapse_palette = on
			"collapse_inspector":
				Settings.collapse_inspector = on
			"collapse_features":
				Settings.collapse_features = on
			"collapse_findings":
				Settings.collapse_findings = on
			"collapse_history":
				Settings.collapse_history = on
		Settings.save()
	)


func _on_split_dragged(_offset: int = 0) -> void:
	if _layout_applying or _layout_timer == null:
		return
	_layout_timer.start()


func _on_layout_idle() -> void:
	_flush_layout(true)


func _flush_layout(persist: bool) -> void:
	if not Settings.focus_mode:
		if _mid_split:
			Settings.layout_split_mid = _mid_split.split_offset
		if _right_col is SplitContainer:
			Settings.layout_split_right = (_right_col as SplitContainer).split_offset
		var split_b := find_child("SplitB", true, false) as SplitContainer
		if split_b:
			Settings.layout_split_upper = split_b.split_offset
		Settings.layout_docks = DockLayout.snapshot(_docks())
	if persist:
		Settings.save()


func _apply_layout_settings() -> void:
	Settings.apply_runtime_view()
	_layout_applying = true
	if _palette and _palette.has_method("set_collapsed"):
		_palette.set_collapsed(Settings.collapse_palette)
	if _inspector and _inspector.has_method("set_collapsed"):
		_inspector.set_collapsed(Settings.collapse_inspector)
	if _features and _features.has_method("set_collapsed"):
		_features.set_collapsed(Settings.collapse_features)
	if _findings and _findings.has_method("set_collapsed"):
		_findings.set_collapsed(Settings.collapse_findings)
	if _history and _history.has_method("set_collapsed"):
		_history.set_collapsed(Settings.collapse_history)
	_show_grid = Settings.view_grid
	_apply_grid()
	if _terrain and _terrain.has_method("set_slope_overlay"):
		_terrain.set_slope_overlay(Settings.view_slope)
	_apply_split_offsets()
	_apply_focus_mode()
	if not Settings.focus_mode:
		_set_console_visible(Settings.console_visible, false)
	_layout_applying = false


func _apply_split_offsets() -> void:
	if _mid_split:
		_mid_split.split_offset = Settings.layout_split_mid
	if _right_col is SplitContainer:
		(_right_col as SplitContainer).split_offset = Settings.layout_split_right
	var split_b := find_child("SplitB", true, false) as SplitContainer
	if split_b:
		split_b.split_offset = Settings.layout_split_upper


func _on_more_selected(id: int) -> void:
	if id == _top.MORE_PREFS:
		if _prefs and _prefs.has_method("popup_prefs"):
			_prefs.call("popup_prefs")
		elif _prefs:
			_prefs.popup_centered()
		return
	_io.handle_more(id)


func _on_autosave() -> void:
	if not MapState.has_session or not MapState.unsaved:
		return
	if _stroking or Backend.busy:
		return
	MapState.persist()
	_log.call("autosaved session")


## GIMP/Photoshop-style link between the New-map size dropdowns: depth
## follows width while "square" is checked (the common case; the engine
## also loads rectangular maps, e.g. stock misn04 at 5120x3840).
func _install_size_link() -> void:
	if _size_option == null or _size_z == null:
		return
	var link := CheckBox.new()
	link.name = "SizeLink"
	link.text = "square"
	link.button_pressed = true
	link.focus_mode = Control.FOCUS_NONE
	link.tooltip_text = "Depth follows width. Uncheck for a rectangular map."
	var row := _size_z.get_parent()
	row.add_child(link)
	var sync := func() -> void:
		if link.button_pressed:
			_size_z.select(_size_option.selected)
		_size_z.disabled = link.button_pressed
	_size_option.item_selected.connect(func(_i: int) -> void: sync.call())
	link.toggled.connect(func(_on: bool) -> void: sync.call())
	sync.call()


func _docks() -> Dictionary:
	var out := {}
	for dock_name in ["Dock1", "Dock2", "Dock3"]:
		out[dock_name] = find_child(dock_name, true, false) as TabContainer
	return out


func _name_right_tabs() -> void:
	var docks := _docks()
	if not Settings.layout_docks.is_empty():
		DockLayout.apply(docks, Settings.layout_docks)
	DockLayout.retitle(docks)
	for dock_name in docks:
		var dock: TabContainer = docks[dock_name]
		if dock == null:
			continue
		# Retitle and schedule a layout save whenever tabs move — within
		# a dock or dragged across docks (GIMP-style rearranging).
		dock.active_tab_rearranged.connect(func(_i: int) -> void: _on_docks_changed())
		dock.child_entered_tree.connect(func(_n: Node) -> void:
			call_deferred("_on_docks_changed")
		)
		dock.child_exiting_tree.connect(func(_n: Node) -> void:
			call_deferred("_on_docks_changed")
		)
		dock.tab_changed.connect(func(_i: int) -> void: _on_split_dragged())


func _on_docks_changed() -> void:
	DockLayout.retitle(_docks())
	_on_split_dragged()


func _apply_autosave() -> void:
	if _autosave == null:
		return
	var sec := Settings.coerce_autosave_interval(Settings.autosave_interval_s)
	if sec <= 0:
		_autosave.stop()
		return
	_autosave.stop()
	_autosave.wait_time = float(sec)
	_autosave.start()


func _log(text: String, level: String = "", toast: bool = false) -> void:
	var routed := LogRouter.route(text, level, toast)
	if _console != null and _console.has_method("append_line"):
		_console.call("append_line", routed.text, routed.level)
	elif _console != null:
		var cur := str(_console.get("text"))
		_console.set("text", routed.text if cur.is_empty() else cur + "\n" + routed.text)
		if _console.has_method("get_line_count"):
			_console.set("scroll_vertical", _console.call("get_line_count"))
	if bool(routed.toast) and _toasts != null and _toasts.has_method("push"):
		_toasts.call("push", routed.text, routed.level)


func _queue_smoke_open() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--smoke-open" and i + 1 < args.size():
			_smoke_path = args[i + 1]
		if args[i] == "--smoke-save" and i + 1 < args.size():
			_smoke_save = args[i + 1]
		if args[i] == "--smoke-sculpt":
			_smoke_sculpt = true


## Smoke-only deterministic edit: an 11x11 plateau at raw 3333 centered on
## cell (255, 255), which straddles the 256-sample zone boundary on any map
## bigger than one zone. Goes through HeightStrokeCommand + UndoStack like a
## real brush stroke, so a smoke save exercises the same path a user's sculpt
## does. Returns false when the session has no heightfield to edit.
func _smoke_apply_sculpt() -> bool:
	var field: HeightField = MapState.field
	if field == null or field.grid_x < 266 or field.grid_z < 266:
		return false
	var x0 := 250
	var z0 := 250
	var w := 11
	var d := 11
	var before := PackedInt32Array()
	var after := PackedInt32Array()
	before.resize(w * d)
	after.resize(w * d)
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			before[i] = field.heights[z * field.grid_x + x]
			after[i] = 3333
			i += 1
	var cmd := HeightStrokeCommandScript.new()
	cmd.setup(x0, z0, w, d, before, after)
	cmd.tool = "smoke"
	UndoStack.push(cmd)
	return true


func _install_heightmap_dialogs() -> void:
	_heightmap_export_dialog = FileDialog.new()
	_heightmap_export_dialog.name = "HeightmapExportDialog"
	_heightmap_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_heightmap_export_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_heightmap_export_dialog.title = "Export heightmap PNG…"
	_heightmap_export_dialog.ok_button_text = "Export"
	_heightmap_export_dialog.dir_selected.connect(_io.export_heightmap)
	add_child(_heightmap_export_dialog)
	_heightmap_import_dialog = FileDialog.new()
	_heightmap_import_dialog.name = "HeightmapImportDialog"
	_heightmap_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_heightmap_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_heightmap_import_dialog.title = "Import heightmap PNG…"
	_heightmap_import_dialog.ok_button_text = "Import"
	_heightmap_import_dialog.filters = PackedStringArray(["*.png, *.PNG ; Heightmap PNG"])
	_heightmap_import_dialog.file_selected.connect(_io.import_heightmap)
	add_child(_heightmap_import_dialog)


func _install_restore_dialog() -> void:
	_restore_dialog = ConfirmationDialog.new()
	_restore_dialog.name = "RestoreSessionDialog"
	_restore_dialog.title = "Restore last session?"
	_restore_dialog.dialog_text = "The editor did not shut down cleanly. Restore the last unsaved session?"
	_restore_dialog.ok_button_text = "Restore"
	_restore_dialog.cancel_button_text = "Discard"
	_restore_dialog.confirmed.connect(_on_restore_session)
	add_child(_restore_dialog)


func _check_crash_recovery() -> void:
	var had_clean := SessionIO.consume_clean_exit()
	var newest := SessionIO.newest_session_dir(MapState.session_root())
	if not SessionIO.should_offer_restore(had_clean, SessionIO.session_has_unsaved_evidence(newest)):
		return
	_restore_session_dir = newest
	if _restore_dialog:
		_restore_dialog.popup_centered()


func _on_restore_session() -> void:
	var dir := _restore_session_dir
	_restore_session_dir = ""
	var payload := SessionIO.session_open_payload(dir)
	if payload.is_empty():
		_log.call("could not restore last session")
		return
	MapState.load_from_open(payload)
	if SessionIO.session_has_unsaved_evidence(MapState.session_dir):
		MapState.note_unsaved()
	var label := MapState.stem if not MapState.stem.is_empty() else dir.get_file()
	_log.call("restored session %s" % label)


func _install_binary_dialog() -> void:
	_binary_dialog = AcceptDialog.new()
	_binary_dialog.name = "BinaryBznDialog"
	_binary_dialog.title = "Binary BZN"
	_binary_dialog.ok_button_text = "Close"
	_binary_dialog.dialog_autowrap = true
	_binary_dialog.min_size = Vector2i(520, 280)
	_binary_dialog.add_button("Copy launch command", true, "copy")
	_binary_dialog.custom_action.connect(func(a):
		if a == "copy":
			if _binary_command.is_empty():
				_log.call("no launch command to copy")
				return
			DisplayServer.clipboard_set(_binary_command)
			_log.call("copied launch command")
	)
	add_child(_binary_dialog)


func _show_binary_bzn_dialog(error: Dictionary) -> void:
	if _binary_dialog == null:
		return
	var path := str(error.get("path", "")).strip_edges()
	var map_name := path.get_file()
	if map_name.is_empty():
		map_name = "map.bzn"
	_binary_command = SessionIO.asciisave_launch_command(map_name)
	var where := path if not path.is_empty() else map_name
	_binary_dialog.dialog_text = (
		"This map is a binary BZN. The editor cannot open binary saves — the game must re-save it as ASCII.\n\n"
		+ "1. Copy the launch command (button below).\n"
		+ "2. Run it while Steam is running (terminal, or Win+R).\n"
		+ "3. The game loads the map and writes an ASCII .bzn.\n\n"
		+ "Where the file lands: the game overwrites the .bzn it loaded, in the same folder as:\n"
		+ "%s\n"
		+ "For stock maps, check the game install's addon/ folder for a new .bzn of the same name.\n\n"
		+ "Then open that ASCII file here.\n\n"
		+ "Command:\n%s"
	) % [where, _binary_command]
	_binary_dialog.popup_centered()


func _install_measure_line() -> void:
	_measure_mesh = MeshInstance3D.new()
	_measure_mesh.name = "MeasureLine"
	_measure_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.15)
	mat.no_depth_test = true
	_measure_mesh.material_override = mat
	if _terrain:
		_terrain.get_parent().add_child(_measure_mesh)


func _begin_measure(p: Vector3) -> void:
	_measuring = true
	_measure_from = p
	_measure_to = p
	if _measure_mesh == null:
		_install_measure_line()
	_update_measure_line(p, p)
	_status.set_status("transient", "measure 0.0 m")


func _update_measure_drag() -> void:
	if not _measuring:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_measure()
		return
	var hit := _pick()
	if hit.get("hit", false):
		_measure_to = hit["position"]
		_update_measure_line(_measure_from, _measure_to)
		_status.set_status("transient", "measure %.1f m" % measure_meters(_measure_from, _measure_to))


func _update_measure_line(a: Vector3, b: Vector3) -> void:
	if _measure_mesh == null:
		return
	var mesh := ImmediateMesh.new()
	var lift := Vector3(0.0, 0.4, 0.0)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(a + lift)
	mesh.surface_add_vertex(b + lift)
	mesh.surface_end()
	_measure_mesh.mesh = mesh


func _finish_measure() -> void:
	if not _measuring:
		return
	var d := measure_meters(_measure_from, _measure_to)
	_clear_measure()
	_log.call(measure_log_line(d))


func _clear_measure() -> void:
	_measuring = false
	_measure_from = Vector3.INF
	_measure_to = Vector3.INF
	if _measure_mesh:
		_measure_mesh.mesh = null


func _handle_bookmark(action: String) -> void:
	var slot := Keymap.bookmark_slot(action)
	if slot < 1:
		return
	if not MapState.has_session:
		_log.call("open a map first")
		return
	if Keymap.is_bookmark_store(action):
		var pose: Dictionary = {}
		if _camera.has_method("capture_bookmark"):
			pose = _camera.capture_bookmark()
		else:
			pose = FlyCamera.make_bookmark(_camera.global_position, _camera.rotation, _camera.pivot)
		if SessionIO.store_bookmark(MapState.session_dir, slot, pose):
			_log.call("stored camera bookmark %d" % slot)
		else:
			_log.call("could not store camera bookmark %d" % slot)
		return
	var recalled := SessionIO.recall_bookmark(MapState.session_dir, slot)
	if recalled.is_empty():
		_log.call("no bookmark %d" % slot)
		return
	if _camera.has_method("apply_bookmark"):
		_camera.apply_bookmark(recalled)
	_log.call("recalled camera bookmark %d" % slot)


func _on_file_dialog_file_selected(path: String) -> void:
	_io.open_file(path)


func _on_new_dialog_confirmed() -> void:
	_io.new_confirmed()


func _on_save_dialog_dir_selected(dir: String) -> void:
	_io.dir_selected(dir)


func _install_aipath_overlay() -> void:
	_aipaths = AiPathOverlay.new()
	_aipaths.name = "AiPathOverlay"
	if _balance:
		_balance.get_parent().add_child(_aipaths)
	elif _terrain:
		_terrain.get_parent().add_child(_aipaths)
	_aipath_bar = HBoxContainer.new()
	_aipath_bar.name = "AiPathBar"
	_aipath_bar.add_theme_constant_override("separation", 6)
	_aipath_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_aipath_bar.position = Vector2(8, 8)
	_btn_add_path = _make_aipath_btn("Add path")
	_btn_del_path = _make_aipath_btn("Delete path")
	_btn_add_pt = _make_aipath_btn("Add point")
	_btn_del_pt = _make_aipath_btn("Delete point")
	_btn_add_path.pressed.connect(_on_add_aipath)
	_btn_del_path.pressed.connect(_on_delete_aipath)
	_btn_add_pt.pressed.connect(_on_add_aipath_point)
	_btn_del_pt.pressed.connect(_on_delete_aipath_point)
	_aipath_bar.add_child(_btn_add_path)
	_aipath_bar.add_child(_btn_del_path)
	_aipath_bar.add_child(_btn_add_pt)
	_aipath_bar.add_child(_btn_del_pt)
	_center.add_child(_aipath_bar)
	_aipath_bar.visible = false


func _make_aipath_btn(caption: String) -> Button:
	var b := Button.new()
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	return b


func _refresh_aipath_bar() -> void:
	if _aipath_bar == null:
		return
	var show := MapState.has_session and AiPathOverlay.enabled
	_aipath_bar.visible = show
	if not show:
		return
	var recs: Array = MapState.active_paths()
	var pi := MapState.selected_path_index
	var qi := MapState.selected_point_index
	var rec := {}
	if pi >= 0 and pi < recs.size() and typeof(recs[pi]) == TYPE_DICTIONARY:
		rec = recs[pi]
	var editable := not rec.is_empty() and AiPathOverlay.is_editable(rec)
	var pts: Array = rec.get("points", []) if typeof(rec.get("points", [])) == TYPE_ARRAY else []
	_set_aipath_btn(_btn_add_path, true, "")
	if rec.is_empty():
		_set_aipath_btn(_btn_del_path, false, "Select an AI path first")
		_set_aipath_btn(_btn_add_pt, false, "Select an AI path first")
		_set_aipath_btn(_btn_del_pt, false, "Select a path point first")
	elif not editable:
		_set_aipath_btn(_btn_del_path, false, "unlabeled paths are preserved, not edited")
		_set_aipath_btn(_btn_add_pt, false, "unlabeled paths are preserved, not edited")
		_set_aipath_btn(_btn_del_pt, false, "unlabeled paths are preserved, not edited")
	else:
		_set_aipath_btn(_btn_del_path, true, "")
		_set_aipath_btn(_btn_add_pt, true, "")
		if qi < 0 or qi >= pts.size():
			_set_aipath_btn(_btn_del_pt, false, "Select a path point first")
		elif pts.size() <= 1:
			_set_aipath_btn(_btn_del_pt, false, "path needs at least one point")
		else:
			_set_aipath_btn(_btn_del_pt, true, "")


func _set_aipath_btn(btn: Button, on: bool, why: String) -> void:
	if btn == null:
		return
	btn.disabled = not on
	btn.tooltip_text = why


func _begin_aipath_gesture(shift: bool) -> bool:
	if _aipaths == null or not _aipaths.is_active() or not MapState.has_session:
		return false
	if ToolState.tool != "select":
		return false
	var mouse := _viewport.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var phit: Dictionary = _aipaths.pick_point(origin, dir)
	if not phit.is_empty():
		var pi := int(phit.get("path", -1))
		var qi := int(phit.get("point", -1))
		var rec := MapState.path_record(pi, MapState.active_variant)
		if rec.is_empty() or not AiPathOverlay.is_editable(rec):
			_log.call("unlabeled path is preserved, not edited")
			return true
		MapState.select_aipath(pi, qi)
		_aipath_dragging = true
		_aipath_drag_path = pi
		_aipath_drag_point = qi
		_aipath_drag_before = AiPathCommand._dup(MapState.active_paths())
		_aipath_moved = false
		var slot: Variant = MapState.dirty.get("aipaths")
		_aipath_drag_was_dirty = typeof(slot) == TYPE_DICTIONARY and bool((slot as Dictionary).get(MapState.active_variant, false))
		_refresh_aipath_bar()
		_log.call("selected path %s point %d" % [str(rec.get("name", "")), qi])
		return true
	var lhit: Dictionary = _aipaths.pick_path(origin, dir)
	if not lhit.is_empty():
		var pi2 := int(lhit.get("path", -1))
		var rec2 := MapState.path_record(pi2, MapState.active_variant)
		if rec2.is_empty() or not AiPathOverlay.is_editable(rec2):
			_log.call("unlabeled path is preserved, not edited")
			return true
		if shift and AiPathOverlay.is_editable(rec2):
			var ground := _pick()
			if ground.get("hit", false):
				var p: Vector3 = ground["position"]
				_insert_aipath_point_at(pi2, int(lhit.get("point", 0)) + 1, p.x, p.z)
				return true
		MapState.select_aipath(pi2, -1)
		_refresh_aipath_bar()
		_log.call("selected path %s" % str(rec2.get("name", "")))
		return true
	return false


func _update_aipath_drag() -> void:
	if not _aipath_dragging:
		return
	var hit := _pick()
	if not hit.get("hit", false):
		return
	var p: Vector3 = hit["position"]
	_set_aipath_point_live(_aipath_drag_path, _aipath_drag_point, p.x, p.z)
	_aipath_moved = true


func _finish_aipath_drag() -> void:
	if not _aipath_dragging:
		return
	var moved := _aipath_moved
	var before := _aipath_drag_before
	var pi := _aipath_drag_path
	var qi := _aipath_drag_point
	_aipath_dragging = false
	_aipath_moved = false
	if not moved:
		_refresh_aipath_bar()
		return
	var after := AiPathCommand._dup(MapState.active_paths())
	var cmd := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.MOVE_POINT, MapState.active_variant, before, after, pi, qi
	)
	UndoStack.push(cmd, true)
	_log.call("moved AI path point")
	_refresh_aipath_bar()


func _cancel_aipath_drag() -> void:
	if not _aipath_dragging:
		return
	if _aipath_moved and not _aipath_drag_before.is_empty():
		MapState.replace_variant_paths(MapState.active_variant, _aipath_drag_before)
		MapState.select_aipath(_aipath_drag_path, _aipath_drag_point)
		if not _aipath_drag_was_dirty:
			var slot: Variant = MapState.dirty.get("aipaths")
			if typeof(slot) == TYPE_DICTIONARY:
				(slot as Dictionary)[MapState.active_variant] = false
	_aipath_dragging = false
	_aipath_moved = false
	_log.call("AI path drag cancelled")
	_refresh_aipath_bar()


func _set_aipath_point_live(path_i: int, point_i: int, x: float, z: float) -> void:
	var recs: Array = AiPathCommand._dup(MapState.active_paths())
	if path_i < 0 or path_i >= recs.size() or typeof(recs[path_i]) != TYPE_DICTIONARY:
		return
	var rec: Dictionary = recs[path_i]
	var pts: Array = rec.get("points", []) if typeof(rec.get("points", [])) == TYPE_ARRAY else []
	if point_i < 0 or point_i >= pts.size():
		return
	pts[point_i] = [x, z]
	rec["points"] = pts
	rec["pointCount"] = pts.size()
	recs[path_i] = rec
	MapState.replace_variant_paths(MapState.active_variant, recs)
	MapState.select_aipath(path_i, point_i)


func _on_add_aipath() -> void:
	if _btn_add_path != null and _btn_add_path.disabled:
		return
	if not MapState.has_session:
		_log.call("open a map first")
		return
	if not AiPathOverlay.enabled:
		_log.call("turn on View → AI Paths first")
		return
	var before := AiPathCommand._dup(MapState.active_paths())
	var after := AiPathCommand._dup(before)
	var rec := MapState.default_new_path(MapState.active_variant)
	rec["size"] = str(rec.get("name", "")).length()
	after.append(rec)
	var cmd := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.ADD_PATH, MapState.active_variant, before, after, after.size() - 1, 0
	)
	UndoStack.push(cmd)
	_log.call("added AI path %s" % str(rec.get("name", "")))
	_refresh_aipath_bar()


func _on_delete_aipath() -> void:
	if _btn_del_path != null and _btn_del_path.disabled:
		return
	var pi := MapState.selected_path_index
	var recs := MapState.active_paths()
	if pi < 0 or pi >= recs.size():
		_log.call("select an AI path first")
		return
	var rec: Dictionary = recs[pi] if typeof(recs[pi]) == TYPE_DICTIONARY else {}
	if not AiPathOverlay.is_editable(rec):
		_log.call("unlabeled paths are preserved, not edited")
		return
	var before := AiPathCommand._dup(recs)
	var after := AiPathCommand._dup(recs)
	after.remove_at(pi)
	var cmd := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.DELETE_PATH, MapState.active_variant, before, after, -1, -1
	)
	UndoStack.push(cmd)
	_log.call("deleted AI path %s" % str(rec.get("name", "")))
	_refresh_aipath_bar()


func _on_add_aipath_point() -> void:
	if _btn_add_pt != null and _btn_add_pt.disabled:
		return
	var pi := MapState.selected_path_index
	var recs := MapState.active_paths()
	if pi < 0 or pi >= recs.size() or typeof(recs[pi]) != TYPE_DICTIONARY:
		_log.call("select an AI path first")
		return
	var rec: Dictionary = recs[pi]
	if not AiPathOverlay.is_editable(rec):
		_log.call("unlabeled paths are preserved, not edited")
		return
	var pts: Array = rec.get("points", []) if typeof(rec.get("points", [])) == TYPE_ARRAY else []
	var insert_at := pts.size()
	var x := float(MapState.width_m) * 0.5
	var z := float(MapState.depth_m) * 0.5
	if MapState.selected_point_index >= 0 and MapState.selected_point_index < pts.size():
		insert_at = MapState.selected_point_index + 1
		var cur: Array = BzOpen._aipath_point(pts[MapState.selected_point_index])
		x = float(cur[0]) + 40.0
		z = float(cur[1]) + 40.0
	elif not pts.is_empty():
		var last: Array = BzOpen._aipath_point(pts[pts.size() - 1])
		x = float(last[0]) + 40.0
		z = float(last[1]) + 40.0
	_insert_aipath_point_at(pi, insert_at, x, z)


func _insert_aipath_point_at(path_i: int, at: int, x: float, z: float) -> void:
	var before := AiPathCommand._dup(MapState.active_paths())
	var after := AiPathCommand._dup(before)
	if path_i < 0 or path_i >= after.size() or typeof(after[path_i]) != TYPE_DICTIONARY:
		return
	var rec: Dictionary = after[path_i]
	var pts: Array = rec.get("points", []) if typeof(rec.get("points", [])) == TYPE_ARRAY else []
	var idx := clampi(at, 0, pts.size())
	pts.insert(idx, [x, z])
	rec["points"] = pts
	rec["pointCount"] = pts.size()
	after[path_i] = rec
	var cmd := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.ADD_POINT, MapState.active_variant, before, after, path_i, idx
	)
	UndoStack.push(cmd)
	_log.call("added AI path point")
	_refresh_aipath_bar()


func _on_delete_aipath_point() -> void:
	if _btn_del_pt != null and _btn_del_pt.disabled:
		return
	_delete_selected_aipath_point()


func _delete_selected_aipath_point() -> bool:
	var pi := MapState.selected_path_index
	var qi := MapState.selected_point_index
	var recs := MapState.active_paths()
	if pi < 0 or pi >= recs.size() or typeof(recs[pi]) != TYPE_DICTIONARY:
		return false
	var rec: Dictionary = recs[pi]
	if not AiPathOverlay.is_editable(rec):
		return false
	var pts: Array = rec.get("points", []) if typeof(rec.get("points", [])) == TYPE_ARRAY else []
	if qi < 0 or qi >= pts.size():
		return false
	if pts.size() <= 1:
		_log.call("path needs at least one point")
		return true
	var before := AiPathCommand._dup(recs)
	var after := AiPathCommand._dup(recs)
	var rec2: Dictionary = after[pi]
	var pts2: Array = rec2.get("points", [])
	pts2.remove_at(qi)
	rec2["points"] = pts2
	rec2["pointCount"] = pts2.size()
	after[pi] = rec2
	var next_pt := mini(qi, pts2.size() - 1)
	var cmd := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.DELETE_POINT, MapState.active_variant, before, after, pi, next_pt
	)
	UndoStack.push(cmd)
	_log.call("deleted AI path point")
	_refresh_aipath_bar()
	return true


func _try_delete_aipath() -> bool:
	if not AiPathOverlay.enabled or not MapState.has_session:
		return false
	if MapState.selected_point_index >= 0:
		return _delete_selected_aipath_point()
	if MapState.selected_path_index >= 0:
		if _btn_del_path != null and _btn_del_path.disabled:
			return true
		_on_delete_aipath()
		return true
	return false

