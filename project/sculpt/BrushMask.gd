extends RefCounted
class_name BrushMask
## A square greyscale brush tip: one byte of coverage per texel.
##
## The analytic circle/square in SculptTool.brush_weight is a closed-form
## falloff and stays the default. A mask is the other half of the idea a
## painting app needs — an arbitrary shape sampled per dab, which is what
## makes ring, chisel and grain tips possible at all.
##
## Generated, never loaded: the editor ships no brush art (C10, C14). The
## generators below are pure functions of (id, size, seed), so two runs build
## byte-identical tips (C6).

const SIZE := 64
## Every generated tip. Order is the order a picker should show them in.
const IDS: PackedStringArray = [
	"disc", "soft", "ring", "square", "chisel", "grain",
]

var size: int = 0
## Row-major coverage, size*size bytes, 0..255.
var data: PackedByteArray = PackedByteArray()


static func generate(id: String, p_size: int = SIZE, p_seed: int = 0) -> BrushMask:
	var m := BrushMask.new()
	m.size = maxi(p_size, 2)
	m.data.resize(m.size * m.size)
	var noise: FastNoiseLite = null
	if id == "grain":
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.seed = p_seed
		noise.frequency = 8.0 / float(m.size)
	var half := float(m.size - 1) * 0.5
	for y in m.size:
		for x in m.size:
			# Normalised to the inscribed circle: 1.0 at the tip's edge.
			var nx := (float(x) - half) / maxf(half, 1.0)
			var ny := (float(y) - half) / maxf(half, 1.0)
			m.data[y * m.size + x] = int(round(
				clampf(_coverage(id, nx, ny, noise), 0.0, 1.0) * 255.0
			))
	return m


static func _coverage(id: String, nx: float, ny: float, noise: FastNoiseLite) -> float:
	var r := sqrt(nx * nx + ny * ny)
	match id:
		"square":
			return 1.0 if maxf(absf(nx), absf(ny)) <= 1.0 else 0.0
		"soft":
			if r >= 1.0:
				return 0.0
			return 0.5 - 0.5 * cos(PI * (1.0 - r))
		"ring":
			if r >= 1.0:
				return 0.0
			# Peak on the rim, zero at the centre and at the edge.
			return maxf(0.0, sin(PI * clampf(r, 0.0, 1.0)))
		"chisel":
			# A 2:1 ellipse: the flat tip that cuts clean ridge lines.
			var e := sqrt(nx * nx + (ny * 2.0) * (ny * 2.0))
			if e >= 1.0:
				return 0.0
			return 0.5 - 0.5 * cos(PI * (1.0 - e))
		"grain":
			if r >= 1.0 or noise == null:
				return 0.0
			var n := noise.get_noise_2d(nx * 100.0, ny * 100.0) * 0.5 + 0.5
			return (0.5 - 0.5 * cos(PI * (1.0 - r))) * clampf(n, 0.0, 1.0)
		_:
			return 1.0 if r <= 1.0 else 0.0


## Bilinear coverage at normalised (u, v) in 0..1. Outside the square reads 0
## so a rotated tip cannot smear its edge row across the stamp rect.
func sample(u: float, v: float) -> float:
	if size < 2 or u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return 0.0
	var fx := u * float(size - 1)
	var fy := v * float(size - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, size - 1)
	var y1 := mini(y0 + 1, size - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var a := float(data[y0 * size + x0])
	var b := float(data[y0 * size + x1])
	var c := float(data[y1 * size + x0])
	var d := float(data[y1 * size + x1])
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty) / 255.0
