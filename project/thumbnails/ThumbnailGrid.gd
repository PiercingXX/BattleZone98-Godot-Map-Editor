extends RefCounted
class_name ThumbnailGrid
## N-up batch layout: many assets, one SubViewport render, one readback.
##
## One viewport per asset costs a render target allocation and a full
## frame-sync per icon; an install has thousands of classes. Laying them on a
## grid amortises both. The cost is that cell order has to be exactly right
## in two places — where the asset is put (`cell_center`, world units) and
## where the pixels are read back (`cell_rect`). An off-by-one between them
## silently shuffles every icon in the palette, so both derive from the same
## row-major rule: index 0 is the TOP-LEFT cell, +x right, +y up.

const MIN_CELL_PX := 8


static func columns_for(count: int, max_cols: int) -> int:
	if count <= 0:
		return 0
	return maxi(1, mini(count, max_cols))


static func rows_for(count: int, cols: int) -> int:
	if count <= 0 or cols <= 0:
		return 0
	return int(ceil(float(count) / float(cols)))


static func viewport_size(cols: int, rows: int, cell_px: int) -> Vector2i:
	var px := maxi(MIN_CELL_PX, cell_px)
	return Vector2i(maxi(0, cols) * px, maxi(0, rows) * px)


static func camera_size(rows: int) -> float:
	## Orthogonal height of the whole grid: one world unit per cell, so a
	## KEEP_HEIGHT camera of `rows` covers exactly `cols` across.
	return float(maxi(1, rows))


static func cell_center(index: int, cols: int, rows: int) -> Vector3:
	## Cell centre in camera space, grid centred on the origin.
	if cols <= 0 or rows <= 0 or index < 0:
		return Vector3.ZERO
	var col := index % cols
	var row := index / cols
	return Vector3(
		float(col) + 0.5 - float(cols) * 0.5,
		float(rows) * 0.5 - (float(row) + 0.5),
		0.0
	)


static func cell_rect(index: int, cols: int, cell_px: int) -> Rect2i:
	## Pixel rect of the same cell in the rendered image. +y is DOWN here and
	## up in `cell_center`; that flip is the whole reason both live together.
	if cols <= 0 or index < 0:
		return Rect2i()
	var px := maxi(MIN_CELL_PX, cell_px)
	var col := index % cols
	var row := index / cols
	return Rect2i(col * px, row * px, px, px)


static func slice(img: Image, count: int, cols: int, cell_px: int) -> Array:
	## Cut a rendered grid into `count` cell images, index order. Cells that
	## fall outside the image come back null rather than blank, so a short
	## readback is a visible miss and not a cached empty icon.
	var out: Array = []
	out.resize(maxi(0, count))
	if img == null or count <= 0 or cols <= 0:
		return out
	var px := maxi(MIN_CELL_PX, cell_px)
	var fmt := img.get_format()
	for i in count:
		var rect := cell_rect(i, cols, px)
		if rect.position.x + rect.size.x > img.get_width():
			continue
		if rect.position.y + rect.size.y > img.get_height():
			continue
		var cell := Image.create_empty(px, px, false, fmt)
		cell.blit_rect(img, rect, Vector2i.ZERO)
		out[i] = cell
	return out
