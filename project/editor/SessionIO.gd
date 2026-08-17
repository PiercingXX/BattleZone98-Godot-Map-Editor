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
			shell._probe_explicit = true
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


func open_file(path: String) -> void:
	Settings.last_map_dir = path.get_base_dir()
	Settings.save()
	Backend.open_map(path, MapState.new_session_dir())


var _new_after_save := false
## Stem to apply to the session once a template open completes.
var template_stem := ""


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


func show_new_dialog() -> void:
	if shell._world_option.item_count == 0 and not Settings.game_root.is_empty():
		Backend.worlds(Settings.game_root)
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
