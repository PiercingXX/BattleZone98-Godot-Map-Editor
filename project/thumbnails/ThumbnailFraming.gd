extends RefCounted
class_name ThumbnailFraming
## Framing maths for batched 3D asset thumbnails.
##
## Deliberately free of nodes, viewports and the rendering server: where a
## mesh lands inside its cell is the part most likely to be subtly wrong, and
## a machine with no GPU still has to be able to prove it right.
##
## The batch camera is ORTHOGONAL and axis-aligned, one world unit per cell.
## Assets are normalised into their cell instead of the camera moving, so
## every cell of an N-up render gets an identical projection — a perspective
## camera would skew the outer cells and make each icon a different lens.

## Fraction of the cell the framed asset is allowed to occupy.
const DEFAULT_FILL := 0.8
## Fixed three-quarter view. Model-space, applied to every asset alike.
const DEFAULT_YAW := -35.0
const DEFAULT_PITCH := 22.0


static func view_basis(
	yaw_deg: float = DEFAULT_YAW,
	pitch_deg: float = DEFAULT_PITCH
) -> Basis:
	## Spin about the model's own up axis first, then tip its top toward the
	## camera. Order matters: the reverse tilts the spin axis and hulls at
	## different yaws would read as different elevations.
	return Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) \
		* Basis(Vector3.UP, deg_to_rad(yaw_deg))


static func visual_aabb(root: Node) -> AABB:
	## Union of every visible MeshInstance3D under `root`, in `root`'s LOCAL
	## space — the root's own transform is excluded because framing sets it.
	##
	## Returns a zero-size AABB when nothing draws. Merging into a default
	## AABB would drag the origin into the box, so the first hit is tracked
	## explicitly; an asset modelled far from its origin must still frame.
	var acc: Array = [false, AABB()]
	_merge(root, Transform3D.IDENTITY, acc)
	return acc[1] if acc[0] else AABB()


static func has_visual(root: Node) -> bool:
	return visual_aabb(root).size != Vector3.ZERO


static func fit_scale(
	box: AABB,
	view: Basis,
	cell: Vector2 = Vector2.ONE,
	fill: float = DEFAULT_FILL
) -> float:
	## Uniform scale that fits `box`, seen through `view`, inside `cell`.
	## 0.0 when there is nothing to fit — callers skip those assets rather
	## than cache a blank.
	var rotated: AABB = Transform3D(view, Vector3.ZERO) * box
	var ex := absf(rotated.size.x)
	var ey := absf(rotated.size.y)
	if ex <= 0.0 and ey <= 0.0:
		return 0.0
	var sx := (cell.x * fill) / ex if ex > 0.0 else INF
	var sy := (cell.y * fill) / ey if ey > 0.0 else INF
	return minf(sx, sy)


static func fit_transform(
	box: AABB,
	view: Basis,
	cell_center: Vector3,
	cell: Vector2 = Vector2.ONE,
	fill: float = DEFAULT_FILL
) -> Transform3D:
	## Transform placing `box` centred in its cell at the largest scale that
	## still fits. Uniform scale, so rotate-then-scale and scale-then-rotate
	## are the same basis.
	var s := fit_scale(box, view, cell, fill)
	if s <= 0.0 or not is_finite(s):
		return Transform3D(Basis(), cell_center)
	var basis := view.scaled(Vector3(s, s, s))
	return Transform3D(basis, cell_center - basis * box.get_center())


static func _merge(node: Node, xform: Transform3D, acc: Array) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var box: AABB = xform * mi.mesh.get_aabb()
		acc[1] = box if not acc[0] else (acc[1] as AABB).merge(box)
		acc[0] = true
	for child in node.get_children():
		var next := xform
		var sp := child as Node3D
		if sp != null:
			# Hidden nodes are LOD shells and collision proxies in converted
			# assets; framing to them pads every icon with empty space.
			if not sp.visible:
				continue
			next = xform * sp.transform
		_merge(child, next, acc)
