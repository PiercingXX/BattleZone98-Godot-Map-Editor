extends RefCounted
class_name SessionIO
## Open / save / new / package / probe-install helpers.

const TopBarScript = preload("res://project/ui/top_bar/TopBar.gd")

const CLEAN_EXIT_PATH := "user://clean_exit"
const BOOKMARKS_FILE := "camera_bookmarks.json"
const STEAM_APP_ID := "301650"

## Stock world ids used when an install has not been probed yet.
const STOCK_WORLD_IDS: PackedStringArray = [
	"achilles", "elysium", "europa", "ganymede", "io",
	"mars", "moon", "titan", "venus",
]

var log: Callable
var shell: Node
## Path the user asked to open; recorded only after the open verb succeeds.
var _pending_open_path: String = ""
var _new_after_save := false
## Stem to apply to the session once a template open completes.
var template_stem := ""


func _init(p_shell: Node, p_log: Callable) -> void:
	shell = p_shell
	log = p_log


func handle_more(id: int) -> void:
	match id:
		TopBarScript.MORE_IMPORT:
			import_assets()
		TopBarScript.MORE_RENDER:
			if MapState.has_session:
				MapState.persist()
				Backend.render_map(MapState.session_dir, MapState.session_dir.path_join("thumbs"))
		TopBarScript.MORE_SCREENSHOT:
			screenshot_viewport()
		TopBarScript.MORE_INSTALL:
			install_mod()
		TopBarScript.MORE_PACK:
			if MapState.has_session:
				shell._pending_package = "pack"
				shell._save_dialog.title = "Assemble pack into…"
				shell._save_dialog.popup_centered_ratio(0.5)
		TopBarScript.MORE_PUBLISH:
			publish_workshop_prompt()
		TopBarScript.MORE_PROBE:
			shell._probe_explicit = true
			Backend.probe()
		TopBarScript.MORE_HELP:
			shell._help.popup_help()
		TopBarScript.MORE_SCHEME_GODOT:
			apply_keymap_scheme(Keymap.SCHEME_GODOT)
		TopBarScript.MORE_SCHEME_GIMP:
			apply_keymap_scheme(Keymap.SCHEME_GIMP)
		TopBarScript.MORE_EXPORT_HEIGHTMAP:
			export_heightmap_prompt()
		TopBarScript.MORE_IMPORT_HEIGHTMAP:
			import_heightmap_prompt()
		# MORE_SAVE_AS never reaches here — TopBar intercepts it and emits
		# save_as_requested instead.


func apply_keymap_scheme(scheme: String) -> void:
	var next := Keymap.normalize_scheme(scheme)
	Settings.keymap_scheme = next
	Settings.save()
	log.call("keyboard scheme %s" % next)
	if shell._help and shell._help.has_method("refresh"):
		shell._help.refresh()
	if shell._top and shell._top.has_method("refresh_keymap"):
		shell._top.refresh_keymap()
	if shell.get("_rail") and shell._rail.has_method("refresh_keymap"):
		shell._rail.refresh_keymap()


func import_assets() -> void:
	if Settings.game_root.is_empty():
		log.call("probe an install first")
	else:
		# Long job with no dialog: announce it so the button visibly did
		# something. Completion refills the palette and logs the counts.
		log.call(
			"importing assets from %s — runs in the background, can take minutes"
			% Settings.game_root, "info", true
		)
		Backend.assets(Settings.game_root, MapState.cache_dir(), true)


func test_in_game() -> void:
	var gt := _game_test()
	if gt == null:
		log.call("game test is not wired")
		return
	if gt.is_active():
		gt.cancel()
		return
	gt.begin()


func _game_test() -> GameTest:
	if shell == null:
		return null
	return shell.get("_game_test") as GameTest


func publish_workshop_prompt() -> void:
	if not MapState.has_session:
		log.call("open a map first")
		return
	if Backend.busy:
		log.call("Busy…")
		return
	var wp := _workshop()
	if wp == null:
		log.call("workshop publish is not wired")
		return
	if shell._save_dialog == null:
		log.call("workshop publish dialog missing")
		return
	shell._pending_package = "workshop"
	shell._save_dialog.title = "Publish workshop folder into…"
	shell._save_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	if not Settings.last_save_dir.is_empty():
		shell._save_dialog.current_dir = Settings.last_save_dir
	elif not Settings.last_map_dir.is_empty():
		shell._save_dialog.current_dir = Settings.last_map_dir
	shell._save_dialog.popup_centered_ratio(0.5)


func _workshop() -> WorkshopPublish:
	if shell == null:
		return null
	return shell.get("_workshop") as WorkshopPublish


func install_mod() -> void:
	if not MapState.has_session:
		return
	if Settings.game_root.is_empty():
		log.call("no game root")
		return
	MapState.persist()
	# The addon route is the one the live harness verified the engine
	# actually loads from; the mods/<id> + modEnabled.dat route is ignored
	# by the game (generator repo docs/17).
	Backend.package_addon(MapState.session_dir, Settings.game_root)


func choose_install(path: String) -> void:
	Settings.game_root = path
	Settings.save()
	log.call("using install %s" % path)
	Backend.worlds(path)
	if not FileAccess.file_exists(MapState.cache_dir().path_join("index.json")):
		Backend.assets(path, MapState.cache_dir(), false, false)
	else:
		Backend.assets(path, MapState.cache_dir(), true, false)


func open_prompt() -> void:
	shell._file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	if not Settings.last_map_dir.is_empty():
		shell._file_dialog.current_dir = Settings.last_map_dir
	shell._file_dialog.popup_centered_ratio(0.6)


func gallery_prompt() -> void:
	var dlg: Node = null
	if shell != null:
		dlg = shell.get("_gallery") as Node
	if dlg == null or not dlg.has_method("show_gallery"):
		log.call("gallery dialog missing")
		return
	dlg.call("show_gallery")


func open_file(path: String) -> void:
	var cleaned := path.strip_edges()
	if cleaned.is_empty():
		log.call("no map path to open")
		return
	if not FileAccess.file_exists(cleaned):
		log.call("file moved — %s" % cleaned)
		return
	Settings.last_map_dir = cleaned.get_base_dir()
	Settings.save()
	_pending_open_path = cleaned
	Backend.open_map(cleaned, MapState.new_session_dir())


## Call after a successful `open` verb. No-ops if this open was not a user file pick
## (template New, smoke-open).
func record_open_if_pending() -> void:
	if _pending_open_path.is_empty():
		return
	var path := _pending_open_path
	_pending_open_path = ""
	Settings.record_recent_map(path)
	Settings.save()
	log.call("opened %s" % path)


func clear_pending_open() -> void:
	_pending_open_path = ""


func new_prompt() -> void:
	# Guard: an open map with unsaved changes must be saved or explicitly
	# discarded before the new-map dialog appears.
	if MapState.has_session and MapState.unsaved:
		shell._new_guard.popup_centered()
		return
	show_new_dialog()


func new_after_save() -> void:
	_new_after_save = true
	save()


func consume_new_after_save() -> bool:
	var pending := _new_after_save
	_new_after_save = false
	return pending


static func stock_worlds() -> Array:
	var out: Array = []
	for world_id in STOCK_WORLD_IDS:
		out.append({"id": world_id, "label": String(world_id).capitalize()})
	return out


static func fill_world_dropdown(option: OptionButton, worlds: Array) -> void:
	if option == null:
		return
	option.clear()
	for world in worlds:
		if typeof(world) != TYPE_DICTIONARY:
			continue
		var world_id := str(world.get("id", "")).strip_edges()
		if world_id.is_empty():
			continue
		var label := str(world.get("label", world_id.capitalize()))
		if label.is_empty():
			label = world_id.capitalize()
		option.add_item(label)
		option.set_item_metadata(option.item_count - 1, world_id)


func show_new_dialog() -> void:
	if MapState.worlds.is_empty():
		fill_world_dropdown(shell._world_option, stock_worlds())
		if not Settings.game_root.is_empty():
			Backend.worlds(Settings.game_root)
	elif shell._world_option.item_count == 0:
		fill_world_dropdown(shell._world_option, MapState.worlds)
	_fill_templates()
	shell._new_dialog.popup_centered()


static func templates_dir() -> String:
	return ProjectSettings.globalize_path("res://templates").simplify_path()


## Each subfolder of templates/ holding a .trn is one starter template.
## The folder is read-only to the editor: templates are opened into fresh
## sessions and never written back.
static func list_templates() -> Array:
	var out: Array = []
	var root := templates_dir()
	var da := DirAccess.open(root)
	if da == null:
		return out
	var dirs := da.get_directories()
	for d in dirs:
		var sub := root.path_join(str(d))
		var sda := DirAccess.open(sub)
		if sda == null:
			continue
		for f in sda.get_files():
			if str(f).to_lower().ends_with(".trn"):
				out.append({"name": str(d), "trn": sub.path_join(str(f))})
				break
	return out


func _fill_templates() -> void:
	var opt: OptionButton = shell._template_option
	opt.clear()
	opt.add_item("Blank map")
	opt.set_item_metadata(0, "")
	for t in list_templates():
		opt.add_item("Template: %s" % t["name"])
		opt.set_item_metadata(opt.item_count - 1, t["trn"])
	opt.select(0)


func new_confirmed() -> void:
	var stem := String(shell._stem_edit.text).strip_edges()
	if stem.is_empty() or stem.length() > 8:
		log.call("stem must be 1–8 characters (engine truncates scripts above 8)")
		return
	var template_trn := ""
	if shell._template_option.selected >= 0:
		template_trn = str(shell._template_option.get_item_metadata(shell._template_option.selected))
	if not template_trn.is_empty():
		# New from template: open the template file set into a fresh session
		# (copy semantics — the template itself is never touched) and adopt
		# the chosen stem for every later save.
		template_stem = stem
		Backend.open_map(template_trn, MapState.new_session_dir())
		log.call("new %s from template %s" % [stem, template_trn.get_base_dir().get_file()])
		return
	var world := "mars"
	if shell._world_option.selected >= 0 and shell._world_option.get_item_metadata(shell._world_option.selected) != null:
		world = str(shell._world_option.get_item_metadata(shell._world_option.selected))
	var w: int = shell._size_option.get_item_id(shell._size_option.selected) if shell._size_option.selected >= 0 else 1280
	var d: int = shell._size_z.get_item_id(shell._size_z.selected) if shell._size_z.selected >= 0 else w
	if w <= 0:
		w = 1280
	if d <= 0:
		d = w
	var kind := "bzp" if shell._pack_kind.selected == 0 else "base"
	Backend.new_map(stem, world, w, d, MapState.new_session_dir(), Settings.game_root, kind)
	log.call("new %s %sx%s %s" % [stem, w, d, kind])


func save(force_prompt: bool = false) -> void:
	if not MapState.has_session:
		log.call("nothing to save")
		return
	if not force_prompt and not shell._save_as and not Settings.last_save_dir.is_empty():
		do_save(Settings.last_save_dir)
		return
	shell._save_as = false
	shell._pending_package = "save"
	shell._save_dialog.title = "Save map to directory"
	shell._save_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	if not Settings.last_save_dir.is_empty():
		shell._save_dialog.current_dir = Settings.last_save_dir
	shell._save_dialog.popup_centered_ratio(0.5)


func dir_selected(dir: String) -> void:
	if shell._pending_package == "pack":
		MapState.persist()
		Backend.package_pack(MapState.session_dir, dir)
	elif shell._pending_package == "workshop":
		Settings.last_save_dir = dir
		Settings.save()
		var wp := _workshop()
		if wp == null:
			log.call("workshop publish is not wired")
		else:
			wp.begin(dir)
	else:
		do_save(dir)
	shell._pending_package = ""
	shell._save_as = false


func do_save(dir: String) -> void:
	if dir.simplify_path().begins_with(templates_dir()):
		log.call("templates/ is read-only — save to a different directory")
		save(true)
		return
	Settings.last_save_dir = dir
	Settings.save()
	MapState.persist()
	log.call("saving %s → %s" % [MapState.stem, dir])
	Backend.save_map(MapState.session_dir, dir, MapState.stem)


func quit_save() -> void:
	if not MapState.has_session:
		if shell != null and shell.has_method("quit_clean"):
			shell.call("quit_clean")
		elif shell != null:
			shell.get_tree().quit()
		return
	shell._quit_after_save = true
	save()


static func write_clean_exit(path: String = CLEAN_EXIT_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("ok\n")
	f.close()


static func consume_clean_exit(path: String = CLEAN_EXIT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var abs_path := path
	if path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(abs_path)
	return true


static func should_offer_restore(clean_exit_present: bool, has_evidence: bool) -> bool:
	return (not clean_exit_present) and has_evidence


static func dirty_json_any_true(dirty: Variant) -> bool:
	match typeof(dirty):
		TYPE_BOOL:
			return dirty
		TYPE_INT, TYPE_FLOAT:
			return float(dirty) != 0.0
		TYPE_STRING:
			return not str(dirty).is_empty()
		TYPE_ARRAY:
			return not (dirty as Array).is_empty()
		TYPE_DICTIONARY:
			for v in (dirty as Dictionary).values():
				if dirty_json_any_true(v):
					return true
			return false
	return false


static func files_show_unsaved(objects_mtime: int, terrain_mtime: int, manifest_mtime: int) -> bool:
	return objects_mtime > manifest_mtime or terrain_mtime > manifest_mtime


static func session_has_unsaved_evidence(session_dir: String) -> bool:
	if session_dir.is_empty() or not DirAccess.dir_exists_absolute(session_dir):
		return false
	var dirty := _read_json_file(session_dir.path_join("dirty.json"))
	if dirty_json_any_true(dirty):
		return true
	var manifest := session_dir.path_join("manifest.json")
	if not FileAccess.file_exists(manifest):
		return false
	var mt := int(FileAccess.get_modified_time(manifest))
	var objects_mt := -1
	var terrain_mt := -1
	var objects_path := session_dir.path_join("objects.json")
	var terrain_path := session_dir.path_join("terrain.r16")
	if FileAccess.file_exists(objects_path):
		objects_mt = int(FileAccess.get_modified_time(objects_path))
	if FileAccess.file_exists(terrain_path):
		terrain_mt = int(FileAccess.get_modified_time(terrain_path))
	return files_show_unsaved(objects_mt, terrain_mt, mt)


static func newest_session_dir(sessions_root: String) -> String:
	if sessions_root.is_empty() or not DirAccess.dir_exists_absolute(sessions_root):
		return ""
	var da := DirAccess.open(sessions_root)
	if da == null:
		return ""
	var best := ""
	var best_t := -1
	for name in da.get_directories():
		var path := sessions_root.path_join(str(name))
		var manifest := path.path_join("manifest.json")
		if not FileAccess.file_exists(manifest):
			continue
		var t := int(FileAccess.get_modified_time(manifest))
		var dt := int(FileAccess.get_modified_time(path))
		if dt > t:
			t = dt
		if t >= best_t:
			best_t = t
			best = path
	return best


static func session_open_payload(session_dir: String) -> Dictionary:
	if session_dir.is_empty():
		return {}
	var manifest_path := session_dir.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return {}
	var manifest := _read_json_file(manifest_path)
	if manifest.is_empty():
		return {}
	return {"session": session_dir, "manifest": manifest}


static func store_bookmark(session_dir: String, slot: int, pose: Dictionary) -> bool:
	if session_dir.is_empty() or slot < 1 or slot > 5 or pose.is_empty():
		return false
	var all := load_bookmarks(session_dir)
	all[str(slot)] = pose
	return _write_json_file(session_dir.path_join(BOOKMARKS_FILE), all)


static func recall_bookmark(session_dir: String, slot: int) -> Dictionary:
	if session_dir.is_empty() or slot < 1 or slot > 5:
		return {}
	var all := load_bookmarks(session_dir)
	var raw: Variant = all.get(str(slot), {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


static func load_bookmarks(session_dir: String) -> Dictionary:
	if session_dir.is_empty():
		return {}
	return _read_json_file(session_dir.path_join(BOOKMARKS_FILE))


static func asciisave_launch_command(map_name: String) -> String:
	var name := map_name.get_file().strip_edges()
	if name.is_empty():
		name = "map.bzn"
	if not name.to_lower().ends_with(".bzn"):
		name += ".bzn"
	return "steam \"steam://run/%s//%s /asciisave /win\"" % [STEAM_APP_ID, name]


static func next_screenshot_path(dir: String, stem: String) -> String:
	var cleaned := stem.strip_edges()
	if cleaned.is_empty():
		cleaned = "viewport"
	var n := 1
	while n < 10000:
		var path := dir.path_join("%s-%d.png" % [cleaned, n])
		if not FileAccess.file_exists(path):
			return path
		n += 1
	return dir.path_join("%s-%d.png" % [cleaned, n])


func screenshot_viewport() -> void:
	if shell == null:
		log.call("screenshot: no viewport")
		return
	var vp: SubViewport = shell.get("_viewport") as SubViewport
	if vp == null:
		log.call("screenshot: no viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		log.call("screenshot: viewport has no texture")
		return
	var img := tex.get_image()
	if img == null:
		log.call("screenshot: capture failed")
		return
	var dir := OS.get_user_data_dir().path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := MapState.stem.strip_edges()
	if stem.is_empty():
		stem = "viewport"
	var path := next_screenshot_path(dir, stem)
	var err := img.save_png(path)
	if err != OK:
		log.call("screenshot failed: %s" % error_string(err))
		return
	log.call(path)


static func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


static func _write_json_file(path: String, data: Dictionary) -> bool:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


func validate() -> void:
	if not MapState.has_session:
		log.call("nothing to validate")
		return
	MapState.persist()
	Backend.validate(MapState.session_dir, Settings.game_root)


func export_heightmap_prompt() -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		log.call("open a map first" if not MapState.has_session else "map has no heightmap")
		return
	var dlg: FileDialog = shell.get("_heightmap_export_dialog") as FileDialog
	if dlg == null:
		log.call("heightmap export dialog missing")
		return
	dlg.title = "Export heightmap PNG…"
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	if not Settings.last_save_dir.is_empty():
		dlg.current_dir = Settings.last_save_dir
	dlg.popup_centered_ratio(0.5)


func import_heightmap_prompt() -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		log.call("open a map first" if not MapState.has_session else "map has no heightmap")
		return
	var dlg: FileDialog = shell.get("_heightmap_import_dialog") as FileDialog
	if dlg == null:
		log.call("heightmap import dialog missing")
		return
	dlg.title = "Import heightmap PNG…"
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.filters = PackedStringArray(["*.png, *.PNG ; Heightmap PNG"])
	if not Settings.last_save_dir.is_empty():
		dlg.current_dir = Settings.last_save_dir
	elif not Settings.last_map_dir.is_empty():
		dlg.current_dir = Settings.last_map_dir
	dlg.popup_centered_ratio(0.6)


func export_heightmap(dir: String) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		log.call("open a map first" if not MapState.has_session else "map has no heightmap")
		return
	var stem := MapState.stem if not MapState.stem.is_empty() else "map"
	var result := HeightmapIO.export_to_dir(dir, stem, MapState.field)
	if not bool(result.get("ok", false)):
		log.call(str(result.get("message", "heightmap export failed")))
		return
	log.call("exported heightmap %s (%dx%d)" % [
		str(result.get("png", "")),
		MapState.field.grid_x,
		MapState.field.grid_z,
	])


func import_heightmap(path: String) -> void:
	if not MapState.has_session or not MapState.has_heightmap():
		log.call("open a map first" if not MapState.has_session else "map has no heightmap")
		return
	var field: HeightField = MapState.field
	var decoded := HeightmapIO.import_png_file(path, field.grid_x, field.grid_z)
	if not bool(decoded.get("ok", false)):
		log.call(str(decoded.get("message", "heightmap import failed")))
		return
	var after: PackedInt32Array = decoded["heights"]
	var cmd := HeightmapImportCommand.new()
	cmd.setup(field.heights.duplicate(), after)
	cmd.snaps_before = HeightmapImportCommand.capture_ys()
	UndoStack.push(cmd)
	log.call("imported heightmap %s (%dx%d, %d-bit gray)" % [
		path.get_file(),
		int(decoded.get("grid_x", field.grid_x)),
		int(decoded.get("grid_z", field.grid_z)),
		int(decoded.get("bit_depth", 16)),
	])
