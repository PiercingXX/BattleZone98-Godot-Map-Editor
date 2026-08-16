extends Node3D
class_name ObjectMarkers
## Proxy boxes at object positions so a smoke-test open is visually checkable.

var _box: BoxMesh


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3(8, 6, 8)


func rebuild(objects: Dictionary, field: HeightField) -> void:
	for child in get_children():
		child.queue_free()
	for variant in objects.keys():
		var records: Variant = objects[variant]
		if typeof(records) != TYPE_ARRAY:
			continue
		var ghost := str(variant) != ""
		for rec in records:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			_place(rec, field, ghost)


func _place(rec: Dictionary, field: HeightField, ghost: bool) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = _box
	var x := float(rec.get("x", 0.0))
	var z := float(rec.get("z", 0.0))
	var y := float(rec.get("y", 0.0))
	if field and field.grid_x > 0:
		y = field.height_at(x, z) + 3.0
	inst.position = Vector3(x, y, z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var prjid := str(rec.get("prjid", "")).to_lower()
	if prjid == "player":
		mat.albedo_color = Color(0.2, 0.85, 0.35)
	elif prjid == "pspwn_1":
		mat.albedo_color = Color(0.95, 0.8, 0.2)
	elif "geyser" in prjid or prjid == "eggeizr1":
		mat.albedo_color = Color(0.95, 0.45, 0.15)
	else:
		mat.albedo_color = Color(0.75, 0.75, 0.8)
	if ghost:
		mat.albedo_color.a = 0.25
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat
	add_child(inst)
