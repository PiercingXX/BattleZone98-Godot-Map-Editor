extends RefCounted
class_name ThumbnailCache
## On-disk store for rendered asset thumbnails.
##
## Thumbnails are derived from the user's own game install, so they live in
## the cache dir beside BzAssets' proxy icons and never in the repo (C14).
## One PNG per class, named deterministically, plus a single `index.json`
## recording which source mesh each PNG came from — overwriting is the whole
## invalidation story, so there are no stale files to prune.
##
## Filenames are restricted to `[a-z0-9_-]` plus a hash of the raw prjid:
## ODF stems are user data and both Linux and Windows have to accept them
## (C12), and two prjids must never collapse onto one file.

## Bump when the lighting rig or framing changes: every cached PNG is then
## keyed differently and regenerates.
const REV := 1


static func dir_for(cache_dir: String) -> String:
	if cache_dir.is_empty():
		return ""
	return cache_dir.path_join("thumbs")


static func index_path(cache_dir: String) -> String:
	var dir := dir_for(cache_dir)
	return "" if dir.is_empty() else dir.path_join("index.json")


static func source_key(glb_path: String) -> String:
	## Identity of the mesh a thumbnail was rendered from. Empty when the
	## mesh is gone — the caller then keeps the proxy icon.
	##
	## Size is hashed alongside mtime because a filesystem with one-second
	## mtime granularity would otherwise hide a same-second reconvert.
	if glb_path.is_empty() or not FileAccess.file_exists(glb_path):
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(glb_path.to_utf8_buffer())
	ctx.update(str(int(FileAccess.get_modified_time(glb_path))).to_utf8_buffer())
	ctx.update(str(_file_size(glb_path)).to_utf8_buffer())
	ctx.update(str(REV).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


static func file_stem(prjid: String) -> String:
	var low := prjid.to_lower()
	var safe := ""
	for i in low.length():
		var ch := low[i]
		var keep := (ch >= "a" and ch <= "z") \
			or (ch >= "0" and ch <= "9") \
			or ch == "_" or ch == "-"
		safe += ch if keep else "_"
	if safe.is_empty():
		safe = "class"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(low.to_utf8_buffer())
	return "%s-%s" % [safe, ctx.finish().hex_encode().substr(0, 8)]


static func png_path(cache_dir: String, prjid: String) -> String:
	var dir := dir_for(cache_dir)
	if dir.is_empty() or prjid.is_empty():
		return ""
	return dir.path_join("%s.png" % file_stem(prjid))


static func new_index(px: int) -> Dictionary:
	return {"rev": REV, "px": px, "entries": {}}


static func load_index(cache_dir: String, px: int) -> Dictionary:
	## A rev or size change invalidates the whole set at once: one PNG per
	## class holds exactly one size, so there is nothing to salvage.
	var path := index_path(cache_dir)
	if path.is_empty() or not FileAccess.file_exists(path):
		return new_index(px)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return new_index(px)
	var data: Dictionary = parsed
	if int(data.get("rev", -1)) != REV or int(data.get("px", -1)) != px:
		return new_index(px)
	if typeof(data.get("entries", null)) != TYPE_DICTIONARY:
		return new_index(px)
	return data


static func save_index(cache_dir: String, index: Dictionary) -> bool:
	var path := index_path(cache_dir)
	if path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(index, "  ") + "\n")
	return true


static func is_current(index: Dictionary, prjid: String, key: String) -> bool:
	if key.is_empty() or prjid.is_empty():
		return false
	var entries: Dictionary = index.get("entries", {})
	return str(entries.get(prjid.to_lower(), "")) == key


static func set_entry(index: Dictionary, prjid: String, key: String) -> void:
	if prjid.is_empty() or key.is_empty():
		return
	if typeof(index.get("entries", null)) != TYPE_DICTIONARY:
		index["entries"] = {}
	(index["entries"] as Dictionary)[prjid.to_lower()] = key


static func drop_entry(index: Dictionary, prjid: String) -> void:
	var entries: Variant = index.get("entries", null)
	if typeof(entries) == TYPE_DICTIONARY:
		(entries as Dictionary).erase(prjid.to_lower())


static func write_png(path: String, img: Image) -> bool:
	if path.is_empty() or img == null:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_png(path) == OK


static func read_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


static func is_blank(img: Image) -> bool:
	## Guards the classic batched-render failure: reading the target back
	## before the frame exists yields an empty or flat image, and caching one
	## is worse than never rendering it — the miss would look permanent.
	if img == null or img.get_width() < 2 or img.get_height() < 2:
		return true
	if img.get_used_rect().size == Vector2i.ZERO:
		return true
	return _is_uniform(img)


static func _is_uniform(img: Image) -> bool:
	var first := img.get_pixel(0, 0)
	var steps := 8
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	for iy in steps:
		var y := int(round(float(iy) * float(h) / float(steps - 1)))
		for ix in steps:
			var x := int(round(float(ix) * float(w) / float(steps - 1)))
			if not img.get_pixel(x, y).is_equal_approx(first):
				return false
	return true


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return 0 if f == null else int(f.get_length())
