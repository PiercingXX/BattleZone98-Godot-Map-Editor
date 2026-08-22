extends RefCounted
class_name MinimapRaster
## CPU rasteriser for the minimap. Row 0 of every image it produces is the
## NORTHERNMOST cell row (C8).
##
## CPU on purpose. Headless Godot runs the dummy rendering driver, so a GPU
## shading pass could not be pixel-asserted anywhere this project is tested —
## and a mirrored render is precisely the defect docs/02 §north-up records as
## having shipped once already. A pass nobody can assert on is how that
## recurs. Cost is bounded instead: at most MAX_TEXELS per side, repainted
## from a dirty cell rect, so an edit repaints a few hundred texels and an
## idle frame repaints none (C17).
##
## Shading is a normal-map hillshade, which needs no game assets. Materials
## only modulate the base colour, and only when a grid is present (C15).

enum Mode {
	RELIEF,
	SLOPE,
	MATERIAL,
	SCATTER,
}

const MODE_NAMES := {
	Mode.RELIEF: "Relief",
	Mode.SLOPE: "Slope",
	Mode.MATERIAL: "Material",
	Mode.SCATTER: "Scatter",
}

## Longest side of the rendered image. A dock minimap is ~260 px wide, so
## anything past this is resampled away by the blit and only costs time.
const MAX_TEXELS := 192

## Light from the north-west and well above the horizon: the convention every
## relief map uses, and the one that keeps a north-up image reading as raised
## rather than sunken. Pre-normalised — it is dotted once per texel.
const LIGHT := Vector3(-0.55293, 0.62333, 0.55293)
## Rise over run at which the slope ramp saturates (45°).
const SLOPE_FULL := 1.0

## PackedColorArray is not a constant expression in GDScript, so the ramps
## are static vars built once at class load rather than const.
static var RELIEF_STOPS := PackedColorArray([
	Color(0.13, 0.17, 0.24),
	Color(0.24, 0.31, 0.28),
	Color(0.41, 0.44, 0.31),
	Color(0.61, 0.55, 0.37),
	Color(0.78, 0.71, 0.55),
	Color(0.95, 0.94, 0.90),
])

static var SLOPE_STOPS := PackedColorArray([
	Color(0.18, 0.34, 0.24),
	Color(0.55, 0.65, 0.25),
	Color(0.88, 0.74, 0.22),
	Color(0.86, 0.33, 0.18),
])

const SCATTER_HOT := Color(0.98, 0.62, 0.20)

var mode: int = Mode.RELIEF
var data: MinimapData = MinimapData.new()
var step: int = 1
var tex_w: int = 0
var tex_h: int = 0
var image: Image
var texture: ImageTexture
## Height range the relief ramp spans, in metres.
var lo_m: float = 0.0
var hi_m: float = 1.0
## Optional HeightRangeMap (anything with map_range() -> Vector2). It already
## keeps min/max over 16-cell blocks, so the ramp costs a mip lookup instead
## of a rescan.
var range_source: Object = null

var _rgba: PackedByteArray = PackedByteArray()
var _mat_colors: PackedColorArray = PackedColorArray()
## Next image row a progressive repaint owes. tex_h means "nothing pending".
var _cursor: int = 0


## Point the raster at a new snapshot. Returns false when there is nothing to
## draw — no map open, or a field too small to shade.
func configure(d: MinimapData) -> bool:
	data = d if d != null else MinimapData.new()
	_mat_colors = MaterialPalette.colors()
	if not data.valid():
		step = 1
		tex_w = 0
		tex_h = 0
		image = null
		texture = null
		_rgba = PackedByteArray()
		return false
	step = maxi(1, int(ceil(float(maxi(data.grid_x, data.grid_z)) / float(MAX_TEXELS))))
	tex_w = maxi(1, int(ceil(float(data.grid_x) / float(step))))
	tex_h = maxi(1, int(ceil(float(data.grid_z) / float(step))))
	var need := tex_w * tex_h * 4
	if _rgba.size() != need:
		_rgba.resize(need)
	image = null
	texture = null
	_cursor = tex_h
	return true


func ready() -> bool:
	return tex_w > 0 and tex_h > 0 and data.valid()


func set_mode(m: int) -> void:
	mode = clampi(m, 0, Mode.SCATTER)


## Texel column holding cell x.
func texel_x(x: int) -> int:
	return clampi(x / step, 0, maxi(tex_w - 1, 0))


## Texel ROW holding cell z. The one place north-up lives: the highest z lands
## on row 0. BzRender._world_to_px and render_heightmap use the same flip.
func texel_y(z: int) -> int:
	return clampi(tex_h - 1 - z / step, 0, maxi(tex_h - 1, 0))


func cell_x(u: int) -> int:
	return clampi(u * step, 0, maxi(data.grid_x - 1, 0))


func cell_z(v: int) -> int:
	return clampi((tex_h - 1 - v) * step, 0, maxi(data.grid_z - 1, 0))


## Repaint the whole image in one call. Session open and the tests use this;
## the panel prefers begin_full() + pump() so a large map never costs a frame.
func render_all() -> void:
	if not ready():
		return
	begin_full()
	_paint(0, 0, tex_w - 1, tex_h - 1)
	_cursor = tex_h
	_commit()


## Start a whole-image repaint that pump() then finishes over several frames.
func begin_full() -> void:
	if not ready():
		return
	_refresh_range()
	_cursor = 0


func painting() -> bool:
	return _cursor < tex_h


## Paint rows until the microsecond budget is spent, commit what exists so far
## and report whether the image is complete. A full repaint of a 1024² map is
## tens of milliseconds of GDScript; spending it inside one frame is the
## per-frame cost C17 forbids, so it is spread instead and the panel shows the
## partially repainted image meanwhile.
func pump(budget_usec: int) -> bool:
	if not ready():
		return true
	if _cursor >= tex_h:
		return true
	var deadline := Time.get_ticks_usec() + maxi(budget_usec, 1)
	while _cursor < tex_h:
		_paint(0, _cursor, tex_w - 1, _cursor)
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	_commit()
	return _cursor >= tex_h


## Repaint only the texels an inclusive CELL rect touches. The one-texel halo
## covers the neighbours the hillshade central difference reads.
func render_cell_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	if not ready():
		return
	var u0 := texel_x(mini(x0, x1)) - 1
	var u1 := texel_x(maxi(x0, x1)) + 1
	# The flip swaps which z bound is the top row, so order after mapping.
	var va := texel_y(mini(z0, z1))
	var vb := texel_y(maxi(z0, z1))
	_paint(u0, mini(va, vb) - 1, u1, maxi(va, vb) + 1)
	_commit()


func mode_name() -> String:
	return str(MODE_NAMES.get(mode, "Relief"))


## True when the active mode has no data behind it and fell back to relief.
func degraded() -> String:
	match mode:
		Mode.MATERIAL:
			if not data.has_materials():
				return "no material grid — showing relief"
		Mode.SCATTER:
			if not data.has_scatter():
				return "no scatter data — showing relief"
	return ""


func _refresh_range() -> void:
	var lo := INF
	var hi := -INF
	if range_source != null and range_source.has_method("map_range"):
		var r: Variant = range_source.call("map_range")
		if r is Vector2 and (r as Vector2).y > (r as Vector2).x:
			lo = (r as Vector2).x
			hi = (r as Vector2).y
	if not is_finite(lo) or not is_finite(hi):
		# Sample the texel grid, not the cell grid: bounded by MAX_TEXELS².
		for v in tex_h:
			var z := cell_z(v)
			for u in tex_w:
				var h := data.height_m(cell_x(u), z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
	if not is_finite(lo) or not is_finite(hi) or hi - lo < 0.01:
		hi = lo + 1.0
	lo_m = lo
	hi_m = hi


func _paint(u0: int, v0: int, u1: int, v1: int) -> void:
	u0 = maxi(u0, 0)
	v0 = maxi(v0, 0)
	u1 = mini(u1, tex_w - 1)
	v1 = mini(v1, tex_h - 1)
	if u1 < u0 or v1 < v0:
		return
	var inv_span := 1.0 / (float(step) * MinimapData.CELL_M * 2.0)
	var inv_range := 1.0 / (hi_m - lo_m)
	var want_mat := mode == Mode.MATERIAL and data.has_materials()
	var want_scatter := mode == Mode.SCATTER and data.has_scatter()
	# Tile lines only earn their pixels when a 20 m tile is several texels
	# wide; below that they would be the whole image.
	var tile_texels := float(MinimapData.MAT_CELLS) / float(step)
	var grid_lines := want_mat and tile_texels >= 3.0
	# Heights are read five times per texel. Sampling through height_m() cost
	# more than the shading did, so the array and its row offsets are hoisted
	# and indexed directly here.
	var heights := data.heights
	var gx := data.grid_x
	var gz := data.grid_z
	var hs := HeightField.HEIGHT_SCALE
	for v in range(v0, v1 + 1):
		var z := cell_z(v)
		var row := v * tex_w * 4
		var zc := z * gx
		var zn := clampi(z + step, 0, gz - 1) * gx
		var zp := clampi(z - step, 0, gz - 1) * gx
		for u in range(u0, u1 + 1):
			var x := cell_x(u)
			var xn := mini(x + step, gx - 1)
			var xp := maxi(x - step, 0)
			var h := float(heights[zc + x]) * hs
			var dx := (float(heights[zc + xn]) - float(heights[zc + xp])) * hs * inv_span
			var dz := (float(heights[zn + x]) - float(heights[zp + x])) * hs * inv_span
			# Surface normal (-dx, 1, -dz) dotted with the light, normalised
			# inline: Vector3.normalized() plus dot() was two calls per texel.
			var inv_n := 1.0 / sqrt(dx * dx + 1.0 + dz * dz)
			var lam := clampf(
				(-dx * LIGHT.x + LIGHT.y - dz * LIGHT.z) * inv_n, 0.0, 1.0
			)
			var shade := clampf(0.30 + 0.85 * lam, 0.0, 1.35)
			var col: Color
			match mode:
				Mode.SLOPE:
					col = _ramp(SLOPE_STOPS, clampf(
						sqrt(dx * dx + dz * dz) / SLOPE_FULL, 0.0, 1.0
					))
				Mode.MATERIAL:
					if want_mat:
						col = _mat_colors[data.material_base(x, z) & 0xF]
					else:
						col = _ramp(RELIEF_STOPS, clampf((h - lo_m) * inv_range, 0.0, 1.0))
				Mode.SCATTER:
					col = _ramp(RELIEF_STOPS, clampf((h - lo_m) * inv_range, 0.0, 1.0))
					if want_scatter:
						var occ := data.scatter_coverage(x, z, step)
						col = col.lerp(SCATTER_HOT, clampf(occ, 0.0, 1.0) * 0.85)
				_:
					col = _ramp(RELIEF_STOPS, clampf((h - lo_m) * inv_range, 0.0, 1.0))
			col = Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			if grid_lines and (x % MinimapData.MAT_CELLS < step \
					or z % MinimapData.MAT_CELLS < step):
				col = col.darkened(0.35)
			var i := row + u * 4
			_rgba[i] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			_rgba[i + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			_rgba[i + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			_rgba[i + 3] = 255


func _commit() -> void:
	if image == null or image.get_width() != tex_w or image.get_height() != tex_h:
		image = Image.create_from_data(tex_w, tex_h, false, Image.FORMAT_RGBA8, _rgba)
	else:
		image.set_data(tex_w, tex_h, false, Image.FORMAT_RGBA8, _rgba)
	if texture == null or texture.get_width() != tex_w or texture.get_height() != tex_h:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)


static func _ramp(stops: PackedColorArray, t: float) -> Color:
	var n := stops.size()
	if n == 0:
		return Color.MAGENTA
	if n == 1:
		return stops[0]
	var f := clampf(t, 0.0, 1.0) * float(n - 1)
	var i := clampi(int(f), 0, n - 2)
	return stops[i].lerp(stops[i + 1], f - float(i))
