extends Node
class_name WorkshopPublish
## Builds a Steam Workshop *upload kit* next to a user-chosen directory.
##
## Never talks to Steam. The folder is for steamcmd or the in-game uploader.
## Pipeline: validate (warn, do not block) → Backend package mode "pack" →
## preview.jpg (512×512) + README-UPLOAD.txt + workshop.vdf.

signal finished(result: Dictionary)

const STEAM_APP_ID := "301650"
const PREVIEW_SIZE := Vector2i(512, 512)
const PREVIEW_NAME := "preview.jpg"
const README_NAME := "README-UPLOAD.txt"
const VDF_NAME := "workshop.vdf"
const PREVIEW_JPG_QUALITY := 0.9

const PHASE_IDLE := ""
const PHASE_VALIDATE := "validate"
const PHASE_PACKAGE := "package"
const PHASE_RENDER := "render"

var log: Callable = Callable()

var _active: bool = false
var _phase: String = PHASE_IDLE
var _dest: String = ""
var _stem: String = ""
var _session: String = ""
var _parent_dir: String = ""


func _ready() -> void:
	Backend.call_finished.connect(_on_call_finished)
	Backend.call_failed.connect(_on_call_failed)


func _exit_tree() -> void:
	if Backend.call_finished.is_connected(_on_call_finished):
		Backend.call_finished.disconnect(_on_call_finished)
	if Backend.call_failed.is_connected(_on_call_failed):
		Backend.call_failed.disconnect(_on_call_failed)


func is_active() -> bool:
	return _active


static func workshop_dir(parent_dir: String, stem: String) -> String:
	var s := stem.strip_edges()
	if s.is_empty():
		s = "map"
	return parent_dir.path_join("%s-workshop" % s)


static func abs_path(path: String) -> String:
	var p := path.strip_edges()
	if p.is_empty():
		return p
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p).simplify_path()
	if p.is_absolute_path():
		return p.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return p.simplify_path()
	return cwd.get_current_dir().path_join(p).simplify_path()


static func default_title(contentfolder: String, title: String = "") -> String:
	var t := title.strip_edges()
	if not t.is_empty():
		return t
	var base := contentfolder.get_file()
	if base.ends_with("-workshop"):
		return base.substr(0, base.length() - "-workshop".length())
	if base.is_empty():
		return "map"
	return base


## Scale / convert any image to a 512×512 RGB8 preview. Empty/null → empty.
static func scale_preview(src: Image) -> Image:
	if src == null or src.is_empty():
		return Image.new()
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_width() != PREVIEW_SIZE.x or img.get_height() != PREVIEW_SIZE.y:
		img.resize(PREVIEW_SIZE.x, PREVIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


static func write_preview_jpg(src: Image, dest_path: String) -> Dictionary:
	var scaled := scale_preview(src)
	if scaled.is_empty():
		return {"ok": false, "message": "no preview image"}
	var parent := dest_path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		var mk: Error = DirAccess.make_dir_recursive_absolute(parent)
		if mk != OK and not DirAccess.dir_exists_absolute(parent):
			return {"ok": false, "message": "cannot create directory: %s" % parent}
	var err: Error = scaled.save_jpg(dest_path, PREVIEW_JPG_QUALITY)
	if err != OK:
		return {"ok": false, "message": "cannot write %s (%s)" % [dest_path, error_string(err)]}
	return {
		"ok": true,
		"path": dest_path,
		"width": scaled.get_width(),
		"height": scaled.get_height(),
	}


static func write_preview_from_path(src_path: String, dest_path: String) -> Dictionary:
	var img := _load_image(src_path)
	if img == null:
		return {"ok": false, "message": "cannot load preview %s" % src_path}
	return write_preview_jpg(img, dest_path)


static func find_preview_source(session_dir: String, dest_dir: String, stem: String) -> String:
	var s := stem.strip_edges()
	var names: Array[String] = ["preview.png", "preview.jpg"]
	if not s.is_empty():
		names.append("%s.png" % s)
		names.append("%s.BMP" % s)
		names.append("%s.bmp" % s)
	var thumbs := session_dir.path_join("thumbs")
	for n in names:
		var p := thumbs.path_join(n)
		if FileAccess.file_exists(p):
			return p
	if not dest_dir.is_empty():
		for n2 in names:
			var p2 := dest_dir.path_join(n2)
			if FileAccess.file_exists(p2):
				return p2
	return ""


## steamcmd workshop_build_item VDF. Paths are embedded verbatim.
static func generate_vdf(
	contentfolder: String,
	previewfile: String,
	title: String = "",
	publishedfileid: String = "0",
	visibility: String = "2"
) -> String:
	var item_title := default_title(contentfolder, title)
	var pid := publishedfileid.strip_edges()
	if pid.is_empty():
		pid = "0"
	var vis := visibility.strip_edges()
	if vis.is_empty():
		vis = "2"
	var lines := PackedStringArray([
		"\"workshopitem\"",
		"{",
		"\t\"appid\"\t\t\"%s\"" % STEAM_APP_ID,
		"\t\"publishedfileid\"\t\t\"%s\"" % pid,
		"\t\"contentfolder\"\t\t\"%s\"" % contentfolder,
		"\t\"previewfile\"\t\t\"%s\"" % previewfile,
		"\t\"visibility\"\t\t\"%s\"" % vis,
		"\t\"title\"\t\t\"%s\"" % item_title,
		"\t\"description\"\t\t\"BattleZone 98 Redux map. Replace this description before you make the item public.\"",
		"\t\"changenote\"\t\t\"Initial upload from the BattleZone 98 Godot Map Editor.\"",
		"}",
		"",
	])
	return "\n".join(lines)


## README-UPLOAD.txt. Paths are embedded verbatim (including the VDF block).
static func generate_readme(contentfolder: String, previewfile: String, title: String = "") -> String:
	var vdf := generate_vdf(contentfolder, previewfile, title)
	var vdf_path := contentfolder.path_join(VDF_NAME)
	var item_title := default_title(contentfolder, title)
	var lines := PackedStringArray([
		"BattleZone 98 Redux — workshop upload kit",
		"==========================================",
		"",
		"This folder was built by the BattleZone 98 Godot Map Editor.",
		"The editor NEVER uploads anything to Steam. You upload it with",
		"steamcmd or the in-game workshop uploader.",
		"",
		"App ID: 301650 (Battlezone 98 Redux)",
		"Title:          %s" % item_title,
		"Content folder: %s" % contentfolder,
		"Preview file:   %s" % previewfile,
		"",
		"Contents of this folder",
		"-----------------------",
		"- Assembled map pack (this folder is the Steam Workshop contentfolder)",
		"- preview.jpg — 512×512 Steam preview",
		"- README-UPLOAD.txt — these instructions",
		"- workshop.vdf — steamcmd workshop_build_item file (paths already filled in)",
		"",
		"=== steamcmd (workshop_build_item) ===",
		"",
		"1. Install SteamCMD from Valve.",
		"2. Log in and publish (paths already filled in):",
		"",
		"   steamcmd +login <steam_username> +workshop_build_item \"%s\" +quit" % vdf_path,
		"",
		"3. First upload: publishedfileid is 0. SteamCMD writes the new item id",
		"   back into workshop.vdf. Keep that file to update the same item later.",
		"",
		"Visibility (the \"visibility\" field in the VDF):",
		"  0 = public",
		"  1 = friends only",
		"  2 = hidden / private",
		"This kit defaults to 2 (hidden) so you can review the item page before",
		"going public. Change the number and re-run workshop_build_item.",
		"",
		"--- workshop.vdf ---",
		vdf.strip_edges(),
		"--- end workshop.vdf ---",
		"",
		"=== In-game workshop uploader ===",
		"",
		"BattleZone 98 Redux can publish from inside the game:",
		"1. Copy this folder's map files into the game addon/ directory",
		"   (More → Install into game (addon) does that from the editor).",
		"2. Launch the game, open the Workshop / extras uploader, and create",
		"   or update an item. Attach preview.jpg as the item preview.",
		"3. Set visibility there the same way (public / friends / hidden).",
		"",
		"Do not point either uploader at the game install, the BZP pack, or",
		"subscribed workshop items. This editor never uploads anything itself.",
		"",
	])
	return "\n".join(lines)


func begin(parent_dir: String) -> bool:
	if _active:
		_emit_log("workshop publish already running")
		return false
	if not MapState.has_session:
		_emit_log("open a map first")
		return false
	if MapState.session_dir.is_empty():
		_emit_log("map has no session directory")
		return false
	if Backend.busy:
		_emit_log("Busy…")
		return false
	var parent := abs_path(parent_dir)
	if parent.is_empty():
		_emit_log("no output directory")
		return false
	var blocked := _forbidden_dest(parent)
	if not blocked.is_empty():
		_emit_log(blocked)
		return false
	var stem := MapState.stem.strip_edges()
	if stem.is_empty():
		stem = "map"
	var dest := workshop_dir(parent, stem)
	blocked = _forbidden_dest(dest)
	if not blocked.is_empty():
		_emit_log(blocked)
		return false
	var mk: Error = DirAccess.make_dir_recursive_absolute(dest)
	if mk != OK and not DirAccess.dir_exists_absolute(dest):
		_emit_log("cannot create %s" % dest)
		return false
	_active = true
	_phase = PHASE_VALIDATE
	_parent_dir = parent
	_dest = dest
	_stem = stem
	_session = MapState.session_dir
	MapState.persist()
	_emit_log("publishing workshop folder → %s" % dest)
	Backend.validate(_session, Settings.game_root)
	return true


func _on_call_finished(verb: String, result: Dictionary) -> void:
	if not _active:
		return
	if _phase == PHASE_VALIDATE and verb == "validate":
		_after_validate(result)
		return
	if _phase == PHASE_PACKAGE and verb == "package":
		_after_package(result)
		return
	if _phase == PHASE_RENDER and verb == "render":
		_after_render(result)
		return


func _on_call_failed(verb: String, error: Dictionary) -> void:
	if not _active:
		return
	if _phase == PHASE_VALIDATE and verb == "validate":
		var report := _read_session_report()
		if _validate_should_continue(error, report):
			_after_validate(report if not report.is_empty() else {"ok": false, "findings": []})
			return
		_fail("workshop publish aborted — validate failed: %s" % error.get("message", error))
		return
	if _phase == PHASE_PACKAGE and verb == "package":
		_fail("workshop publish aborted — pack failed: %s" % error.get("message", error))
		return
	if _phase == PHASE_RENDER and verb == "render":
		_emit_log("workshop preview render skipped: %s" % error.get("message", error))
		_write_sidecars("")
		return


func _validate_should_continue(error: Dictionary, report: Dictionary) -> bool:
	if not report.get("findings", []).is_empty():
		return true
	if report.has("findings"):
		return true
	var code := str(error.get("code", ""))
	if code == "failed":
		return true
	if code.is_empty():
		return true
	return false


func _after_validate(result: Dictionary) -> void:
	var findings: Array = result.get("findings", [])
	_push_findings(findings)
	if findings.is_empty():
		_emit_log("workshop publish: validate clean")
	else:
		_emit_log("workshop publish: %d validate findings (not blocking) — see the Findings panel" % findings.size())
	_phase = PHASE_PACKAGE
	Backend.package_pack(_session, _dest)


func _after_package(result: Dictionary) -> void:
	var dest := str(result.get("dest", _dest))
	if not dest.is_empty():
		_dest = dest
	_emit_log("workshop pack %s" % _dest)
	var src := find_preview_source(_session, _dest, _stem)
	if src.is_empty():
		_phase = PHASE_RENDER
		Backend.render_map(_session, _session.path_join("thumbs"))
		return
	_write_sidecars(src)


func _after_render(result: Dictionary) -> void:
	var src := str(result.get("preview", ""))
	if src.is_empty() or not FileAccess.file_exists(src):
		src = str(result.get("png", ""))
	if src.is_empty() or not FileAccess.file_exists(src):
		src = find_preview_source(_session, _dest, _stem)
	_write_sidecars(src)


func _write_sidecars(src_path: String) -> void:
	var dest := abs_path(_dest)
	var jpg := dest.path_join(PREVIEW_NAME)
	var preview_ok := false
	if src_path.is_empty() or not FileAccess.file_exists(src_path):
		_emit_log("workshop preview missing — no render output or session thumbs")
	else:
		var wr := write_preview_from_path(src_path, jpg)
		if bool(wr.get("ok", false)):
			preview_ok = true
			_emit_log("workshop preview %s" % jpg)
		else:
			_emit_log("workshop preview failed: %s" % wr.get("message", "write failed"))
	var readme_path := dest.path_join(README_NAME)
	var vdf_path := dest.path_join(VDF_NAME)
	var content := generate_readme(dest, jpg, _stem)
	var vdf := generate_vdf(dest, jpg, _stem)
	if not _write_text(readme_path, content):
		_fail("workshop publish aborted — cannot write %s" % readme_path)
		return
	_emit_log("workshop readme %s" % readme_path)
	if not _write_text(vdf_path, vdf):
		_fail("workshop publish aborted — cannot write %s" % vdf_path)
		return
	_emit_log("workshop vdf %s" % vdf_path)
	_emit_log("workshop folder %s (not uploaded)" % dest)
	var result := {
		"ok": true,
		"dest": dest,
		"preview": jpg if preview_ok else "",
		"readme": readme_path,
		"vdf": vdf_path,
	}
	_reset()
	finished.emit(result)


func _fail(msg: String) -> void:
	_emit_log(msg)
	var result := {"ok": false, "message": msg, "dest": _dest}
	_reset()
	finished.emit(result)


func _reset() -> void:
	_active = false
	_phase = PHASE_IDLE
	_dest = ""
	_stem = ""
	_session = ""
	_parent_dir = ""


func _push_findings(findings: Array) -> void:
	MapState.findings = findings
	MapState.findings_stale = false
	var shell := _shell()
	if shell == null:
		return
	var panel: Variant = shell.get("_findings")
	if panel is Object and (panel as Object).has_method("set_findings"):
		(panel as Object).call("set_findings", findings, false)


func _read_session_report() -> Dictionary:
	if _session.is_empty():
		return {}
	var path := _session.path_join("report.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _forbidden_dest(dir: String) -> String:
	var p := dir.simplify_path()
	if p.is_empty():
		return "no output directory"
	var templates := SessionIO.templates_dir()
	if not templates.is_empty() and (p == templates or p.begins_with(templates + "/")):
		return "templates/ is read-only — pick a different directory"
	if not Settings.game_root.is_empty():
		var game := Settings.game_root.simplify_path()
		if not game.is_empty() and (p == game or p.begins_with(game + "/")):
			return "refusing to write into the game install"
	return ""


func _write_text(path: String, text: String) -> bool:
	var parent := path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


static func _load_image(path: String) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return img


func _emit_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
	else:
		EditorFeedback.log(text)


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")
