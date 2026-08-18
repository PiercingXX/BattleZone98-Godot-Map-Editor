extends RefCounted
class_name BzDiscover
## Install and workshop discovery for the `probe` verb (docs/02 §3).
## Port of `backend/bzmap/editor/discover.py`.
##
## A directory is a BZ98R install only if it contains `battlezone98redux.exe`
## and `BZ_ASSETS/common/models/`. Workshop items are the union of
## `steamapps/workshop/content/301650/<id>/` and `<install>/packaged_mods/<id>/`,
## keyed by ID, with `packaged_mods` preferred when both exist.
##
## Windows discrepancy vs Python: Godot has no `winreg`. Steam/GOG registry
## keys are not read; discovery uses `OS.get_environment` plus well-known
## Program Files / user folders. Pass `override` for a non-default install.

const STEAM_APP_ID := "301650"
const INSTALL_DIR_NAME := "Battlezone 98 Redux"
const EXE_NAME := "battlezone98redux.exe"
const CONTRACT_VERSION := 1
const BZMAP_VERSION := "0.1.0"

## Asset suffixes that mean "this workshop item is an asset pack".
const _ASSET_SUFFIXES := {
	".odf": true,
	".mesh": true,
	".skeleton": true,
	".material": true,
	".dds": true,
	".png": true,
	".geo": true,
	".vdf": true,
	".sdf": true,
	".map": true,
	".act": true,
	".bzn": true,
	".trn": true,
	".hg2": true,
	".mat": true,
	".lgt": true,
	".vxt": true,
	".des": true,
}

## Tests set this to an Array/PackedStringArray (possibly empty) to replace
## OS steam-root probing. `null` (default) uses real OS locations.
static var test_steam_roots: Variant = null
## Same hook for GOG candidate directories.
static var test_gog_installs: Variant = null


static func parse_libraryfolders_vdf(text: String) -> Array:
	## Return every `"path"` value in a Steam `libraryfolders.vdf`.
	##
	## The schema has changed across Steam versions; we pull every path
	## regardless of nesting rather than matching a fixed tree.
	var paths: Array = []
	var re := RegEx.new()
	var err := re.compile("(?i)\"path\"\\s*\"([^\"]+)\"")
	if err != OK:
		return paths
	for m in re.search_all(text):
		var raw := m.get_string(1)
		raw = raw.replace("\\\\", "\\")
		paths.append(raw)
	return paths


static func is_game_install(path: String) -> bool:
	## True when `path` has the exe and `BZ_ASSETS/common/models/`.
	if path.is_empty():
		return false
	if not DirAccess.dir_exists_absolute(path):
		return false
	var models := path.path_join("BZ_ASSETS").path_join("common").path_join("models")
	return _has_exe(path) and DirAccess.dir_exists_absolute(models)


static func discover(override: String = "") -> Dictionary:
	## Return `{"installs": [...], "warnings": [...], "libraries": [...]}`.
	##
	## `override` is an explicit game-root the caller already chose; it is
	## validated and listed first when it passes. Invalid override returns
	## `BzErrors.err("install_invalid", ...)` instead of raising.
	var warnings: Array = []
	var installs: Array = []
	var seen_installs := {}

	if not override.is_empty():
		var override_path := _expanduser(override)
		if is_game_install(override_path):
			_add_install(installs, seen_installs, override_path)
		else:
			return BzErrors.err(
				"install_invalid",
				"not a BZ98R install: %s" % override_path,
				"need battlezone98redux.exe and BZ_ASSETS/common/models/",
				override_path
			)

	var libraries: Array = []
	var seen_libs := {}
	for root in _steam_roots():
		if not DirAccess.dir_exists_absolute(root) and not _is_symlink(root):
			# Python: Path.exists() is true for a symlink to a missing target
			# as well as a real dir. A dangling symlink is skipped below.
			if not _path_exists(root):
				continue
		if not _path_exists(root):
			continue
		for lib in _libraries_from_root(root):
			var key := _resolve_key(lib)
			if seen_libs.has(key):
				continue
			seen_libs[key] = true
			libraries.append(lib)

	for lib in libraries:
		var candidate := String(lib).path_join("steamapps").path_join("common").path_join(INSTALL_DIR_NAME)
		var version := _read_acf_field(_appmanifest(lib), "buildid")
		_add_install(installs, seen_installs, candidate, "game", "", version)

	for gog in _gog_installs():
		_add_install(installs, seen_installs, gog, "game", "gog", "")

	# Workshop layers, union by ID.
	var workshop_items := {}  # id -> {workshop, packaged, name}

	for lib in libraries:
		var workshop := String(lib).path_join("steamapps").path_join("workshop").path_join("content").path_join(STEAM_APP_ID)
		if not DirAccess.dir_exists_absolute(workshop):
			continue
		for child in _list_dirs(workshop):
			_note_item(workshop_items, child.get_file(), child, "workshop")

	for inst in installs:
		var packaged := str(inst.get("path", "")).path_join("packaged_mods")
		if not DirAccess.dir_exists_absolute(packaged):
			continue
		for child in _list_dirs(packaged):
			_note_item(workshop_items, child.get_file(), child, "packaged")

	var item_ids: Array = workshop_items.keys()
	item_ids.sort()
	for item_id in item_ids:
		var rec: Dictionary = workshop_items[item_id]
		var packaged_path: String = str(rec.get("packaged", ""))
		var workshop_path: String = str(rec.get("workshop", ""))
		var source := ""
		var path := ""
		if not packaged_path.is_empty() and not workshop_path.is_empty():
			source = "both"
			path = packaged_path  # the copy the game actually loads
		elif not packaged_path.is_empty():
			source = "packaged"
			path = packaged_path
		else:
			source = "workshop"
			path = workshop_path
		if path.is_empty() or not _item_has_assets(path):
			continue
		var stats := _item_stats(path)
		var resolved := _resolve(path)
		installs.append({
			"kind": "workshop_item",
			"path": resolved,
			"name": str(rec.get("name", item_id)),
			"id": str(item_id),
			"source": source,
			"file_count": int(stats[0]),
			"size_bytes": int(stats[1]),
		})

	if not _any_game(installs):
		warnings.append("no game install found at any default path")
		var sandbox_hint := _flatpak_snap_hint()
		if not sandbox_hint.is_empty():
			warnings.append(sandbox_hint)

	var lib_strs: Array = []
	for p in libraries:
		lib_strs.append(str(p))
	return {
		"installs": installs,
		"warnings": warnings,
		"libraries": lib_strs,
	}


static func first_game_root(discovery: Variant = null) -> String:
	## Return the first discovered game install path, or "" (Python: None).
	var found: Dictionary
	if discovery == null:
		found = discover()
	elif typeof(discovery) == TYPE_DICTIONARY:
		found = discovery
	else:
		return ""
	if BzErrors.is_err(found):
		return ""
	for item in found.get("installs", []):
		if typeof(item) == TYPE_DICTIONARY and item.get("kind") == "game":
			return str(item.get("path", ""))
	return ""


static func probe(override: String = "") -> Dictionary:
	## Verb payload for `probe` (docs/02 §3). Wraps `discover()`.
	var found := discover(override)
	if BzErrors.is_err(found):
		return found
	return {
		"ok": true,
		"bzmap_version": BZMAP_VERSION,
		"contract_version": CONTRACT_VERSION,
		# docs/02 freezes the key name "python"; the port has no interpreter.
		"python": _runtime_version(),
		"installs": found.get("installs", []),
		"warnings": found.get("warnings", []),
	}


static func _add_install(
	installs: Array,
	seen_installs: Dictionary,
	path: String,
	kind: String = "game",
	platform_hint: String = "",
	version: String = ""
) -> void:
	var resolved := _resolve(path)
	var key := resolved.to_lower() if _is_windows() else resolved
	if seen_installs.has(key):
		return
	if not is_game_install(resolved):
		return
	seen_installs[key] = true
	if platform_hint.is_empty():
		if _is_windows():
			platform_hint = "windows"
		else:
			platform_hint = "proton"
	installs.append({
		"kind": kind,
		"path": resolved,
		"version": version,
		"platform_hint": platform_hint,
	})


static func _note_item(workshop_items: Dictionary, item_id: String, path: String, source: String) -> void:
	if not workshop_items.has(item_id):
		workshop_items[item_id] = {
			"workshop": "",
			"packaged": "",
			"name": item_id,
		}
	var rec: Dictionary = workshop_items[item_id]
	rec[source] = path
	workshop_items[item_id] = rec


static func _any_game(installs: Array) -> bool:
	for item in installs:
		if typeof(item) == TYPE_DICTIONARY and item.get("kind") == "game":
			return true
	return false


## Flatpak-sandboxed Godot may be unable to read a snap-packaged Steam
## library even though it exists. When we found nothing, we run inside
## Flatpak, and the system shows snap use, say how to open the sandbox.
static func _flatpak_snap_hint() -> String:
	if OS.get_name() != "Linux":
		return ""
	var in_flatpak := (
		not OS.get_environment("FLATPAK_ID").is_empty()
		or FileAccess.file_exists("/.flatpak-info")
	)
	if not in_flatpak:
		return ""
	if not DirAccess.dir_exists_absolute(_home_dir().path_join("snap")):
		return ""
	var app_id := OS.get_environment("FLATPAK_ID")
	if app_id.is_empty():
		app_id = "org.godotengine.Godot"
	return (
		"running inside Flatpak with snap packages present — if Steam is "
		+ "the snap version, grant this app file access and re-probe:  "
		+ "flatpak override --user --filesystem=home %s" % app_id
	)


static func _linux_steam_roots() -> PackedStringArray:
	var home := _home_dir()
	var roots := PackedStringArray()
	roots.append(home.path_join(".steam").path_join("steam"))
	roots.append(home.path_join(".local").path_join("share").path_join("Steam"))
	roots.append(
		home.path_join(".var").path_join("app").path_join("com.valvesoftware.Steam")
			.path_join(".local").path_join("share").path_join("Steam")
	)
	roots.append(home.path_join(".steam").path_join("root"))
	roots.append(home.path_join(".steam").path_join("debian-installation"))
	# Snap-packaged Steam (Ubuntu default install channel).
	roots.append(
		home.path_join("snap").path_join("steam").path_join("common")
			.path_join(".local").path_join("share").path_join("Steam")
	)
	roots.append(
		home.path_join("snap").path_join("steam").path_join("current")
			.path_join(".local").path_join("share").path_join("Steam")
	)
	return roots


static func _windows_steam_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	# Python also reads HKCU\Software\Valve\Steam\SteamPath and
	# HKLM\SOFTWARE\WOW6432Node\Valve\Steam\InstallPath. No registry API here.
	for env in ["ProgramFiles(x86)", "ProgramFiles"]:
		var base := OS.get_environment(env)
		if not base.is_empty():
			roots.append(base.path_join("Steam"))
	return roots


static func _steam_roots() -> PackedStringArray:
	if test_steam_roots != null:
		return _as_string_array(test_steam_roots)
	if _is_windows():
		return _windows_steam_roots()
	return _linux_steam_roots()


static func _libraries_from_root(steam_root: String) -> Array:
	var resolved := _resolve(steam_root)
	if resolved.is_empty():
		resolved = _expanduser(steam_root)
	var libraries: Array = [resolved]
	var vdf := resolved.path_join("steamapps").path_join("libraryfolders.vdf")
	if FileAccess.file_exists(vdf):
		var text := _read_text(vdf)
		for lib in parse_libraryfolders_vdf(text):
			libraries.append(str(lib))
	var seen := {}
	var out: Array = []
	for lib in libraries:
		var key := _resolve_key(str(lib))
		if seen.has(key):
			continue
		seen[key] = true
		out.append(str(lib))
	return out


static func _has_exe(install: String) -> bool:
	## Case-insensitive look for the game executable.
	if not DirAccess.dir_exists_absolute(install):
		return false
	var da := DirAccess.open(install)
	if da == null:
		return false
	da.include_hidden = false
	da.include_navigational = false
	var target := EXE_NAME.to_lower()
	for child in da.get_files():
		if String(child).to_lower() == target:
			return true
	return false


static func _appmanifest(library: String) -> String:
	return String(library).path_join("steamapps").path_join("appmanifest_%s.acf" % STEAM_APP_ID)


static func _read_acf_field(path: String, field: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var text := _read_text(path)
	if text.is_empty():
		return ""
	var re := RegEx.new()
	var pattern := "(?i)\"%s\"\\s*\"([^\"]*)\"" % _re_escape(field)
	if re.compile(pattern) != OK:
		return ""
	var m := re.search(text)
	if m == null:
		return ""
	return m.get_string(1)


static func _gog_installs() -> PackedStringArray:
	if test_gog_installs != null:
		return _as_string_array(test_gog_installs)
	var found := PackedStringArray()
	if _is_windows():
		# Python enumerates GOG.com\Games registry keys. Env-based fallbacks:
		for env in ["ProgramFiles(x86)", "ProgramFiles"]:
			var base := OS.get_environment(env)
			if base.is_empty():
				continue
			var cand := base.path_join("GOG Galaxy").path_join("Games").path_join(INSTALL_DIR_NAME)
			if DirAccess.dir_exists_absolute(cand):
				found.append(cand)
		var home := _home_dir()
		var user_gog := home.path_join("GOG Games").path_join(INSTALL_DIR_NAME)
		if DirAccess.dir_exists_absolute(user_gog):
			found.append(user_gog)
	else:
		var home := _home_dir()
		for cand in [
			home.path_join("GOG Games").path_join("Battlezone 98 Redux"),
			home.path_join("GOG Games").path_join(INSTALL_DIR_NAME),
		]:
			if DirAccess.dir_exists_absolute(cand):
				found.append(cand)
	return found


static func _item_has_assets(directory: String) -> bool:
	var da := DirAccess.open(directory)
	if da == null:
		return false
	da.include_hidden = false
	da.include_navigational = false
	for child in da.get_files():
		if _ASSET_SUFFIXES.has(_suffix_lower(String(child))):
			return true
	return false


static func _item_stats(directory: String) -> Array:
	var count := 0
	var size := 0
	var da := DirAccess.open(directory)
	if da == null:
		return [0, 0]
	da.include_hidden = false
	da.include_navigational = false
	for child in da.get_files():
		count += 1
		var f := FileAccess.open(directory.path_join(String(child)), FileAccess.READ)
		if f != null:
			size += int(f.get_length())
	return [count, size]


static func _list_dirs(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(path)
	if da == null:
		return out
	da.include_hidden = false
	da.include_navigational = false
	for dname in da.get_directories():
		out.append(path.path_join(String(dname)))
	return out


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


static func _suffix_lower(path: String) -> String:
	var ext := path.get_extension()
	if ext.is_empty():
		return ""
	return "." + ext.to_lower()


static func _home_dir() -> String:
	if _is_windows():
		var up := OS.get_environment("USERPROFILE")
		if not up.is_empty():
			return up
		var hd := OS.get_environment("HOMEDRIVE")
		var hp := OS.get_environment("HOMEPATH")
		if not hd.is_empty() and not hp.is_empty():
			return hd.path_join(hp.lstrip("\\").lstrip("/"))
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		return home
	return OS.get_environment("USERPROFILE")


static func _cwd() -> String:
	var pwd := OS.get_environment("PWD")
	if not pwd.is_empty():
		return pwd
	var cd := OS.get_environment("CD")
	if not cd.is_empty():
		return cd
	return ProjectSettings.globalize_path("res://").rstrip("/").rstrip("\\")


static func _expanduser(path: String) -> String:
	if path == "~":
		return _home_dir()
	if path.begins_with("~/") or path.begins_with("~\\"):
		return _home_dir().path_join(path.substr(2))
	return path


static func _resolve(path: String) -> String:
	var p := _expanduser(path)
	if p.is_empty():
		return p
	if not _is_abs(p):
		p = _cwd().path_join(p)
	p = p.replace("\\", "/")
	p = p.simplify_path()
	return _realpath(p)


static func _resolve_key(path: String) -> String:
	var resolved := _resolve(path)
	if resolved.is_empty():
		resolved = path
	return resolved


static func _is_abs(path: String) -> bool:
	if path.begins_with("/") or path.begins_with("\\"):
		return true
	# Windows drive path: C:/ or C:\
	if path.length() >= 3 and path[1] == ":" and (path[2] == "/" or path[2] == "\\"):
		return true
	if path.length() == 2 and path[1] == ":":
		return true
	return path.is_absolute_path()


static func _realpath(path: String) -> String:
	## Resolve existing symlink components. Missing tails stay as written
	## (Python 3 `Path.resolve(strict=False)`).
	var p := _rstrip_slash(path.replace("\\", "/"))
	var drive := ""
	var rest := p
	if p.length() >= 2 and p[1] == ":":
		drive = p.substr(0, 2)
		rest = p.substr(2)
		if rest.begins_with("/"):
			rest = rest.substr(1)
	var is_abs := p.begins_with("/") or not drive.is_empty()
	var parts := rest.split("/", false)
	var built := drive
	if drive.is_empty() and is_abs:
		built = ""
	for part in parts:
		if part.is_empty() or part == ".":
			continue
		if part == "..":
			if built.is_empty() or built == drive:
				continue
			built = built.get_base_dir()
			if built.is_empty() and is_abs and drive.is_empty():
				built = ""
			continue
		var next: String
		if built.is_empty():
			next = ("/" + part) if (is_abs and drive.is_empty()) else part
		elif built == "/":
			next = "/" + part
		else:
			next = built.path_join(part)
		built = _follow_links(next)
	if built.is_empty() and is_abs and drive.is_empty():
		return "/"
	if built.is_empty() and not drive.is_empty():
		return drive + "/"
	return built


static func _follow_links(path: String) -> String:
	var current := path
	var seen := {}
	for _hop in 32:
		if seen.has(current):
			return current
		seen[current] = true
		if not _is_symlink(current):
			return current
		var target := _read_symlink(current)
		if target.is_empty():
			return current
		if not _is_abs(target):
			target = current.get_base_dir().path_join(target)
		current = target.replace("\\", "/").simplify_path()
	return current


static func _is_symlink(path: String) -> bool:
	var cleaned := _rstrip_slash(path)
	var parent := cleaned.get_base_dir()
	var name := cleaned.get_file()
	if parent.is_empty() or name.is_empty():
		return false
	var da := DirAccess.open(parent)
	if da == null:
		return false
	return da.is_link(name)


static func _read_symlink(path: String) -> String:
	var cleaned := _rstrip_slash(path)
	var parent := cleaned.get_base_dir()
	var name := cleaned.get_file()
	if parent.is_empty() or name.is_empty():
		return ""
	var da := DirAccess.open(parent)
	if da == null:
		return ""
	return da.read_link(name)


static func _path_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path) or _is_symlink(path)


static func _rstrip_slash(path: String) -> String:
	var p := path
	while p.length() > 1 and (p.ends_with("/") or p.ends_with("\\")):
		p = p.substr(0, p.length() - 1)
	return p


static func _is_windows() -> bool:
	return OS.get_name() == "Windows"


static func _as_string_array(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v == null:
		return out
	if v is PackedStringArray:
		return v
	if v is Array:
		for item in v:
			out.append(str(item))
	elif typeof(v) == TYPE_STRING:
		out.append(str(v))
	return out


static func _re_escape(text: String) -> String:
	var special := "\\.^$|*+?()[]{}-"
	var out := ""
	for i in text.length():
		var ch := text[i]
		if special.contains(ch):
			out += "\\"
		out += ch
	return out


static func _runtime_version() -> String:
	var vi := Engine.get_version_info()
	return "godot-%s" % str(vi.get("string", "4.7"))
