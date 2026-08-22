extends Node
class_name ThumbnailService
## Batched offscreen 3D thumbnails for the class palette.
##
## The palette is what a mapper stares at while placing units, and BZ has a
## large, visually distinctive roster; a flat colour swatch throws that away.
## This renders the user's OWN converted assets: N×N per SubViewport, one
## readback, sliced into per-class icons and cached under the cache dir.
##
## The viewport owns its World3D so the editor's scene lighting cannot leak
## into an icon, and carries a fixed rig so two machines produce the same
## picture.
##
## Never a hard dependency:
##   * no game install, no converted mesh → the class keeps the flat proxy
##     icon BzAssets wrote, and `icon_for` still returns it (C15);
##   * no renderer (headless, dummy driver) → `is_supported()` is false and
##     nothing is queued at all;
##   * generation is incremental — one batch per frame, cancellable — so a
##     full install never blocks the editor (C17).

## Emitted per class as its picture lands. `tex` is already usable.
signal thumbnail_ready(prjid: String, tex: Texture2D)
## Emitted after each batch. `done` counts classes resolved this run.
signal progress(done: int, total: int)
## Emitted when the queue drains or a run is cancelled.
signal finished()

const DEFAULT_CELL_PX := 96
const DEFAULT_COLS := 4
## Camera stand-off. Orthogonal, so this only has to clear the near plane.
const _CAM_Z := 8.0

## Cell edge in pixels. Changing it invalidates the whole cache by design —
## one PNG per class holds exactly one size.
var cell_px: int = DEFAULT_CELL_PX
## Grid edge. Fewer columns is a smaller GPU spike per frame.
var cols: int = DEFAULT_COLS

var _cache_dir: String = ""
var _index: Dictionary = {}
var _tex: Dictionary = {}
var _proxy: Dictionary = {}
var _queue: Array[Dictionary] = []
var _queued: Dictionary = {}
var _running: bool = false
var _cancel: bool = false
var _done: int = 0
var _total: int = 0
var _dirty_index: bool = false


static func is_supported() -> bool:
	## A dummy display server renders nothing; its readback is blank or null.
	## Refusing up front keeps blanks out of the cache and out of the UI.
	return DisplayServer.get_name() != "headless"


func configure(cache_dir: String, px: int = DEFAULT_CELL_PX) -> void:
	var next_px := maxi(ThumbnailGrid.MIN_CELL_PX, px)
	if cache_dir == _cache_dir and next_px == cell_px and not _index.is_empty():
		return
	cancel()
	_cache_dir = cache_dir
	cell_px = next_px
	_tex.clear()
	_proxy.clear()
	_index = ThumbnailCache.load_index(_cache_dir, cell_px)


func cache_dir() -> String:
	return _cache_dir


func is_busy() -> bool:
	return _running


func pending() -> int:
	return _queue.size()


## Rendered picture for a class, or null. Never falls back — callers that
## want "best available" want `icon_for`.
func texture_for(prjid: String) -> Texture2D:
	if prjid.is_empty():
		return null
	var key := prjid.to_lower()
	if _tex.has(key):
		return _tex[key]
	if _cache_dir.is_empty():
		return null
	var entries: Dictionary = _index.get("entries", {})
	if not entries.has(key):
		return null
	var tex := ThumbnailCache.read_texture(ThumbnailCache.png_path(_cache_dir, key))
	if tex != null:
		_tex[key] = tex
	return tex


## Best available picture for a class record: the rendered thumbnail if one
## is cached, else the flat proxy icon from the asset index. The proxy rung
## is the fallback for everything conversion has not reached, so it stays.
func icon_for(rec: Dictionary) -> Texture2D:
	var prjid := str(rec.get("prjid", ""))
	if prjid.is_empty():
		return null
	var tex := texture_for(prjid)
	if tex != null:
		return tex
	return _proxy_icon(prjid, str(rec.get("icon", "")))


## Does this class still need a picture? False when it has no converted mesh
## — the flat proxy icon stands in and nothing is rendered — and false when
## the cached PNG was already made from exactly that mesh.
static func needs_render(index: Dictionary, cache_dir: String, rec: Dictionary) -> bool:
	if cache_dir.is_empty():
		return false
	var prjid := str(rec.get("prjid", ""))
	if prjid.is_empty():
		return false
	var key := ThumbnailCache.source_key(str(rec.get("mesh", "")))
	if key.is_empty():
		return false
	if not ThumbnailCache.is_current(index, prjid, key):
		return true
	return not FileAccess.file_exists(ThumbnailCache.png_path(cache_dir, prjid))


## Queue classes whose thumbnail is missing or stale. Accepts asset-index
## class records or `BzAssets.thumbnail_candidates` items — both carry
## `prjid` and `mesh`. Returns how many were newly queued.
func request(records: Array) -> int:
	if not is_supported() or _cache_dir.is_empty():
		return 0
	var added := 0
	for rec in records:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var prjid := str((rec as Dictionary).get("prjid", "")).to_lower()
		if prjid.is_empty() or _queued.has(prjid):
			continue
		if not needs_render(_index, _cache_dir, rec):
			continue
		_queued[prjid] = true
		_queue.append({
			"prjid": prjid,
			"mesh": str((rec as Dictionary).get("mesh", "")),
			"key": ThumbnailCache.source_key(str((rec as Dictionary).get("mesh", ""))),
		})
		added += 1
	_total += added
	if added > 0 and not _running:
		_pump()
	return added


## Drop everything not yet rendered. Safe mid-run: the in-flight batch
## finishes, then the loop exits.
func cancel() -> void:
	_queue.clear()
	_queued.clear()
	_done = 0
	_total = 0
	if _running:
		_cancel = true


func _pump() -> void:
	if _running or get_tree() == null:
		return
	_running = true
	_cancel = false
	var batch_max := maxi(1, cols * cols)
	while not _queue.is_empty() and not _cancel:
		var batch: Array = []
		while batch.size() < batch_max and not _queue.is_empty():
			batch.append(_queue.pop_front())
		await _render_batch(batch)
		if _dirty_index:
			ThumbnailCache.save_index(_cache_dir, _index)
			_dirty_index = false
		progress.emit(_done, _total)
		# Hand the frame back. A full install is thousands of classes and the
		# editor has to stay usable while they render (C17).
		if get_tree() == null:
			break
		await get_tree().process_frame
	_running = false
	_cancel = false
	if _queue.is_empty():
		_queued.clear()
		_done = 0
		_total = 0
	finished.emit()


func _render_batch(batch: Array) -> void:
	var count := batch.size()
	if count <= 0:
		return
	var grid_cols := ThumbnailGrid.columns_for(count, cols)
	var grid_rows := ThumbnailGrid.rows_for(count, grid_cols)
	var vp := build_viewport(grid_cols, grid_rows, cell_px)
	add_child(vp)
	var view := ThumbnailFraming.view_basis()
	var placed: Array[bool] = []
	placed.resize(count)
	for i in count:
		var item: Dictionary = batch[i]
		placed[i] = false
		var node := load_mesh_scene(str(item.get("mesh", "")))
		if node == null:
			continue
		var box := ThumbnailFraming.visual_aabb(node)
		if box.size == Vector3.ZERO:
			node.free()
			continue
		node.transform = ThumbnailFraming.fit_transform(
			box, view, ThumbnailGrid.cell_center(i, grid_cols, grid_rows)
		)
		vp.add_child(node)
		placed[i] = true
	var img := await _grab(vp)
	vp.queue_free()
	if img == null:
		_done += count
		return
	var cells := ThumbnailGrid.slice(img, count, grid_cols, cell_px)
	for i in count:
		_done += 1
		if not placed[i]:
			continue
		var cell: Variant = cells[i] if i < cells.size() else null
		if cell == null or ThumbnailCache.is_blank(cell):
			continue
		_store(str((batch[i] as Dictionary).get("prjid", "")),
			str((batch[i] as Dictionary).get("key", "")), cell)


func _store(prjid: String, key: String, img: Image) -> void:
	if prjid.is_empty():
		return
	if ThumbnailCache.write_png(ThumbnailCache.png_path(_cache_dir, prjid), img):
		ThumbnailCache.set_entry(_index, prjid, key)
		_dirty_index = true
	var tex := ImageTexture.create_from_image(img)
	_tex[prjid] = tex
	thumbnail_ready.emit(prjid, tex)


func _grab(vp: SubViewport) -> Image:
	## Readback order is the classic failure in batched thumbnailing: ask for
	## the image too early and every icon is blank or half-drawn. Let the
	## nodes enter the tree, request exactly one render, then wait for the
	## draw itself to finish before touching the texture.
	if get_tree() == null:
		return null
	await get_tree().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## The offscreen rig: one SubViewport, its own World3D, a fixed orthogonal
## camera and a fixed two-light setup. Public and static because the rig is
## the reproducibility contract — same picture on every machine — and has to
## be inspectable without a GPU to render with.
static func build_viewport(grid_cols: int, grid_rows: int, px: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = ThumbnailGrid.viewport_size(grid_cols, grid_rows, px)
	vp.transparent_bg = true
	# Own World3D: the editor's sun, environment and terrain are not allowed
	# anywhere near an icon, and the rig has to be identical every run.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	vp.add_child(_make_camera(grid_rows))
	vp.add_child(_make_environment())
	for light in _make_lights():
		vp.add_child(light)
	return vp


static func _make_camera(grid_rows: int) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	# One world unit per cell: height `rows` gives width `cols` at the grid
	# aspect, so every cell is exactly the unit square ThumbnailGrid places.
	cam.size = ThumbnailGrid.camera_size(grid_rows)
	cam.near = 0.05
	cam.far = _CAM_Z * 2.0
	cam.transform = Transform3D(Basis(), Vector3(0.0, 0.0, _CAM_Z))
	cam.current = true
	return cam


static func _make_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.74)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	return we


static func _make_lights() -> Array[DirectionalLight3D]:
	# Key from over the camera's left shoulder, cool fill from the far side
	# so unlit faces keep their silhouette instead of going black.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -34.0, 0.0)
	key.light_energy = 1.5
	key.shadow_enabled = false
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 140.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.shadow_enabled = false
	return [key, fill]


## Load a converted `.glb` as a detached scene. Static: the mesh path is the
## only input, and framing has to be provable against a real glTF tree.
static func load_mesh_scene(path: String) -> Node3D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _proxy_icon(prjid: String, icon_rel: String) -> Texture2D:
	var key := prjid.to_lower()
	if _proxy.has(key):
		return _proxy[key]
	if icon_rel.is_empty() or _cache_dir.is_empty():
		return null
	var path := icon_rel if icon_rel.is_absolute_path() else _cache_dir.path_join(icon_rel)
	var tex := ThumbnailCache.read_texture(path)
	if tex != null:
		_proxy[key] = tex
	return tex
