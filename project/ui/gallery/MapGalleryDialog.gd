extends Window
## Thumbnail grid of maps in addon/, workshop items, and templates/.

signal map_open_requested(path: String)

const TILE_PX := 112
const BATCH_DIRS := 24
const MAX_DEPTH := 10
const MAX_SCAN_DIRS := 4000
const THUMB_BATCH := 8

## Tests set this to an Array (possibly empty) to skip BzDiscover.
var test_workshop_items: Variant = null

var _entries: Array = []
var _queue: Array = []
var _seen: Dictionary = {}
var _tex_cache: Dictionary = {}
var _pending_thumbs: Array = []
var _placeholder: Texture2D
var _phase: int = 0
var _scanning: bool = false
var _truncated: bool = false
var _scan_timer: Timer

@onready var _search: LineEdit = %Search
@onready var _status: Label = %Status
@onready var _grid: ItemList = %Tiles
@onready var _open: Button = %Open
@onready var _cancel: Button = %Cancel


func _ready() -> void:
	close_requested.connect(_on_cancel)
	visibility_changed.connect(_on_visibility)
	_search.text_changed.connect(_on_search)
	_search.text_submitted.connect(func(_t): _open_selected())
	_grid.item_selected.connect(func(_i): _refresh_open_button())
	_grid.item_activated.connect(func(_i): _open_selected())
	_open.pressed.connect(_open_selected)
	_cancel.pressed.connect(_on_cancel)
	_placeholder = _make_placeholder()
	_scan_timer = Timer.new()
	_scan_timer.name = "ScanTimer"
	_scan_timer.wait_time = 0.016
	_scan_timer.one_shot = false
	_scan_timer.timeout.connect(_on_scan_tick)
	add_child(_scan_timer)
	_grid.icon_mode = ItemList.ICON_MODE_TOP
	_grid.fixed_icon_size = Vector2i(TILE_PX, TILE_PX)
	_grid.same_column_width = true
	_grid.fixed_column_width = TILE_PX + 28
	_grid.max_text_lines = 2
	_grid.resized.connect(_update_columns)
	_update_columns()
	_refresh_open_button()


func show_gallery() -> void:
	_search.text = ""
	_entries.clear()
	_queue.clear()
	_seen.clear()
	_tex_cache.clear()
	_pending_thumbs.clear()
	_phase = 0
	_scanning = true
	_truncated = false
	_grid.clear()
	_status.text = "Scanning…"
	_refresh_open_button()
	exclusive = true
	popup_centered()
	EditorFeedback.log("gallery: scanning")
	if _scan_timer != null:
		_scan_timer.start()


func _on_visibility() -> void:
	if not visible and _scan_timer != null:
		_scan_timer.stop()
		_scanning = false


func _on_cancel() -> void:
	if _scan_timer != null:
		_scan_timer.stop()
	_scanning = false
	exclusive = false
	hide()


func _on_search(_text: String) -> void:
	_rebuild_grid()


func _update_columns() -> void:
	if _grid == null:
		return
	var col_w := float(maxi(TILE_PX + 28, 1))
	var cols := maxi(1, int(_grid.size.x / col_w))
	_grid.max_columns = cols


func _on_scan_tick() -> void:
	if _phase == 0:
		_enqueue_sources(MapGalleryEnum.collect_sources(
			Settings.game_root, SessionIO.templates_dir(), []
		))
		_phase = 1
		_refresh_status()
		return
	if _phase == 1:
		_enqueue_sources(MapGalleryEnum.collect_sources("", "", _workshop_items()))
		_phase = 2
		_refresh_status()
		return
	if not _queue.is_empty():
		_scan_batch()
		_rebuild_grid()
		return
	if not _pending_thumbs.is_empty():
		_load_thumb_batch()
		return
	_scan_timer.stop()
	if _scanning:
		_scanning = false
		EditorFeedback.log("gallery: %d maps" % _entries.size())
		if _truncated:
			EditorFeedback.log("gallery: scan truncated")
	_rebuild_grid()


func _workshop_items() -> Array:
	if test_workshop_items != null:
		if test_workshop_items is Array:
			return test_workshop_items
		return []
	var found: Dictionary
	if Settings.game_root.is_empty():
		found = BzDiscover.discover()
	else:
		found = BzDiscover.discover(Settings.game_root)
		if BzErrors.is_err(found):
			found = BzDiscover.discover()
	if BzErrors.is_err(found):
		return []
	return MapGalleryEnum.workshop_items_from_discover(found)


func _enqueue_sources(sources: Array) -> void:
	for src in sources:
		if typeof(src) != TYPE_DICTIONARY:
			continue
		var p := str(src.get("path", "")).strip_edges()
		if p.is_empty():
			continue
		var key := MapGalleryEnum.dir_key(p)
		if _seen.has(key):
			continue
		if _seen.size() >= MAX_SCAN_DIRS:
			_truncated = true
			return
		_seen[key] = true
		_queue.append({
			"path": p,
			"source": str(src.get("source", "")),
			"kind": str(src.get("kind", "")),
			"depth": 0,
		})


func _scan_batch() -> void:
	var n := 0
	while n < BATCH_DIRS and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var result := MapGalleryEnum.scan_dir(
			str(job.get("path", "")),
			str(job.get("source", "")),
			str(job.get("kind", "")),
		)
		for e in result.get("entries", []):
			_entries.append(e)
		var depth := int(job.get("depth", 0))
		if depth < MAX_DEPTH:
			for sub in result.get("subdirs", []):
				var sub_path := str(sub)
				var key := MapGalleryEnum.dir_key(sub_path)
				if _seen.has(key):
					continue
				if _seen.size() >= MAX_SCAN_DIRS:
					_truncated = true
					break
				_seen[key] = true
				_queue.append({
					"path": sub_path,
					"source": str(job.get("source", "")),
					"kind": str(job.get("kind", "")),
					"depth": depth + 1,
				})
		n += 1


func _rebuild_grid() -> void:
	var keep := _selected_path()
	var shown := MapGalleryEnum.filter_by_stem(_entries, _search.text if _search else "")
	MapGalleryEnum.sort_entries(shown)
	_grid.clear()
	_pending_thumbs.clear()
	for e in shown:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var i := _grid.add_item(_tile_label(e), _placeholder)
		_grid.set_item_metadata(i, e)
		_grid.set_item_tooltip(i, str(e.get("path", "")))
		var thumb := str(e.get("thumb_path", ""))
		if thumb.is_empty():
			continue
		if _tex_cache.has(thumb):
			_grid.set_item_icon(i, _tex_cache[thumb])
		else:
			_pending_thumbs.append(i)
	if not keep.is_empty():
		for i in _grid.item_count:
			var meta = _grid.get_item_metadata(i)
			if typeof(meta) == TYPE_DICTIONARY and str(meta.get("path", "")) == keep:
				_grid.select(i)
				break
	_refresh_open_button()
	_refresh_status(shown.size())


func _load_thumb_batch() -> void:
	var n := 0
	while n < THUMB_BATCH and not _pending_thumbs.is_empty():
		var i: int = int(_pending_thumbs.pop_front())
		if i < 0 or i >= _grid.item_count:
			continue
		var meta = _grid.get_item_metadata(i)
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var thumb := str(meta.get("thumb_path", ""))
		if thumb.is_empty():
			continue
		var tex := _thumb_texture(thumb)
		_grid.set_item_icon(i, tex)
		n += 1


func _thumb_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex := _load_thumb(path)
	_tex_cache[path] = tex
	return tex


func _load_thumb(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _placeholder
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return _placeholder
	var canvas := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.16, 0.16, 0.18, 1))
	var w := img.get_width()
	var h := img.get_height()
	if w > 0 and h > 0:
		var scale := minf(float(TILE_PX) / float(w), float(TILE_PX) / float(h))
		var nw := maxi(1, int(round(float(w) * scale)))
		var nh := maxi(1, int(round(float(h) * scale)))
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		canvas.blit_rect(img, Rect2i(0, 0, nw, nh), Vector2i((TILE_PX - nw) / 2, (TILE_PX - nh) / 2))
	return ImageTexture.create_from_image(canvas)


func _make_placeholder() -> Texture2D:
	var img := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.22, 0.22, 0.24, 1))
	return ImageTexture.create_from_image(img)


func _tile_label(entry: Dictionary) -> String:
	return "%s  ·  %s" % [str(entry.get("stem", "")), str(entry.get("source", ""))]


func _selected_path() -> String:
	if _grid == null:
		return ""
	var sel := _grid.get_selected_items()
	if sel.is_empty():
		return ""
	var meta = _grid.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_DICTIONARY:
		return ""
	return str(meta.get("path", ""))


func _open_selected() -> void:
	var path := _selected_path()
	if path.is_empty():
		if _open != null and _open.disabled:
			EditorFeedback.log(_open.tooltip_text)
		else:
			EditorFeedback.log("select a map")
		return
	if _scan_timer != null:
		_scan_timer.stop()
	_scanning = false
	exclusive = false
	hide()
	map_open_requested.emit(path)


func _refresh_open_button() -> void:
	if _open == null:
		return
	var path := _selected_path()
	if not path.is_empty():
		_open.disabled = false
		_open.tooltip_text = "Open %s" % path.get_file()
		return
	_open.disabled = true
	if _entries.is_empty():
		_open.tooltip_text = "Scanning…" if _scanning else "No maps found"
	elif _grid.item_count == 0:
		_open.tooltip_text = "No maps match"
	else:
		_open.tooltip_text = "Select a map"


func _refresh_status(shown: int = -1) -> void:
	if _status == null:
		return
	var visible_n := shown if shown >= 0 else _grid.item_count
	var total := _entries.size()
	if _scanning:
		if total == 0:
			_status.text = "Scanning…"
		else:
			_status.text = "Scanning… %d maps" % total
		return
	if total == 0:
		_status.text = "No maps found in addon/, workshop items, or templates/"
		return
	if visible_n == total:
		_status.text = "%d maps" % total
	else:
		_status.text = "%d of %d maps" % [visible_n, total]
