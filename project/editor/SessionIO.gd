extends RefCounted
class_name SessionIO
## Open / save / new / package / probe-install helpers.

const TopBarScript = preload("res://project/ui/top_bar/TopBar.gd")

var log: Callable
var shell: Node


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
		TopBarScript.MORE_INSTALL:
			install_mod()
		TopBarScript.MORE_PACK:
			if MapState.has_session:
				shell._pending_package = "pack"
				shell._save_dialog.title = "Assemble pack into…"
				shell._save_dialog.popup_centered_ratio(0.5)
		TopBarScript.MORE_PROBE:
			Backend.probe()
		TopBarScript.MORE_HELP:
			shell._help.popup_help()
		# MORE_SAVE_AS never reaches here — TopBar intercepts it and emits
		# save_as_requested instead.


func import_assets() -> void:
	if Settings.game_root.is_empty():
		log.call("probe an install first")
	else:
		Backend.assets(Settings.game_root, MapState.cache_dir(), true)


func install_mod() -> void:
	if not MapState.has_session:
		return
	if Settings.game_root.is_empty():
		log.call("no game root")
		return
	MapState.persist()
	Backend.package_install(MapState.session_dir, Settings.game_root)


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


func open_file(path: String) -> void:
	Settings.last_map_dir = path.get_base_dir()
	Settings.save()
	Backend.open_map(path, MapState.new_session_dir())


func new_prompt() -> void:
	if shell._world_option.item_count == 0 and not Settings.game_root.is_empty():
		Backend.worlds(Settings.game_root)
	shell._new_dialog.popup_centered()


func new_confirmed() -> void:
	var stem := String(shell._stem_edit.text).strip_edges()
	if stem.is_empty() or stem.length() > 8:
		log.call("stem must be 1–8 characters (engine truncates scripts above 8)")
		return
	var world := "mars"
	if shell._world_option.selected >= 0 and shell._world_option.get_item_metadata(shell._world_option.selected) != null:
		world = str(shell._world_option.get_item_metadata(shell._world_option.selected))
	var w: int = shell._size_option.get_item_id(shell._size_option.selected) if shell._size_option.selected >= 0 else 1280
	var d := shell._size_z.get_item_id(shell._size_z.selected) if shell._size_z.selected >= 0 else w
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
	else:
		do_save(dir)
	shell._pending_package = ""
	shell._save_as = false


func do_save(dir: String) -> void:
	Settings.last_save_dir = dir
	Settings.save()
	MapState.persist()
	Backend.save_map(MapState.session_dir, dir, MapState.stem)


func quit_save() -> void:
	if not MapState.has_session:
		shell.get_tree().quit()
		return
	shell._quit_after_save = true
	save()


func validate() -> void:
	if not MapState.has_session:
		log.call("nothing to validate")
		return
	MapState.persist()
	Backend.validate(MapState.session_dir, Settings.game_root)
