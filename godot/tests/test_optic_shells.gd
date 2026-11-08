extends SceneTree
## Native surface samples from the deleted frame and housing regions.
## A short normal ray must hit an opaque surface at the original position.

var _failures := 0

const SAMPLES := {
	"em57s2_viewmodel_ads": [
		[Vector3(-0.00188738, 0.14612030, -0.30597010), Vector3(0.37229378, 0.40090439, -0.83706213), "lower frame"],
		[Vector3(-0.01713429, 0.15886206, -0.31365470), Vector3(0.00100100, 0.03221408, -0.99948049), "left frame"],
		[Vector3(0.01799514, 0.16672778, -0.31304479), Vector3(-0.61297615, 0.03361821, 0.78938587), "right frame"],
	],
	"em86m_viewmodel_ads": [
		[Vector3(0.00997802, 0.15349780, 0.01796501), Vector3(-0.01588647, -0.51403277, -0.85762342), "lower frame"],
		[Vector3(-0.02508005, 0.17205324, -0.18791537), Vector3(0.17887339, 0.63179688, -0.75421284), "left frame"],
		[Vector3(0.02626051, 0.18734598, -0.17772042), Vector3(0.00257334, 0.53391458, -0.84553451), "right frame"],
	],
	"em40t1_viewmodel": [
		[Vector3(-0.00123576, 0.23369047, -0.10473012), Vector3(-0.01666886, 0.99971886, 0.01686240), "top housing"],
		[Vector3(-0.05156550, 0.10761125, -0.12215721), Vector3(-0.62222015, -0.78283193, 0.00403236), "left housing"],
		[Vector3(0.04776973, 0.10474670, -0.11096917), Vector3(0.79450640, -0.54927848, 0.25894541), "right housing"],
	],
}


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _opaque_hit(model: Node3D, from: Vector3, direction: Vector3) -> Variant:
	# Geometry3D treats tiny determinants as parallel. Scale this local ray
	# to millimetres so the original small frame triangles remain detectable.
	var nearest: Variant = null
	var to_model := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var xform := to_model * instance.global_transform
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a <= 0.35:
				continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var a := (xform * vertices[indices[index]] - from) * 1000.0
				var b := (xform * vertices[indices[index + 1]] - from) * 1000.0
				var c := (xform * vertices[indices[index + 2]] - from) * 1000.0
				var hit = Geometry3D.ray_intersects_triangle(Vector3.ZERO, direction, a, b, c)
				if hit == null:
					hit = Geometry3D.ray_intersects_triangle(Vector3.ZERO, direction, a, c, b)
				if hit != null and (nearest == null or (hit as Vector3).length_squared() < (nearest as Vector3).length_squared()):
					nearest = hit
	return null if nearest == null else from + (nearest as Vector3) / 1000.0


func _opaque_surface_at(model: Node3D, point: Vector3, normal: Vector3) -> bool:
	var hit = _opaque_hit(model, point + normal * 0.0001, -normal)
	return hit != null and (hit as Vector3).distance_to(point) < 0.00002


func _run() -> void:
	var before_dir := ""
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--before":
		before_dir = args[1]
	for asset: String in SAMPLES:
		var model: Node3D
		if before_dir.is_empty():
			model = (load("res://assets/models/weapons/%s.glb" % asset) as PackedScene).instantiate() as Node3D
		else:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var error := document.append_from_file(before_dir.path_join("codex_before_%s.glb" % asset), state)
			_assert(error == OK, asset + " reproduction asset loads")
			if error != OK:
				continue
			model = document.generate_scene(state) as Node3D
		root.add_child(model)
		for sample: Array in SAMPLES[asset]:
			_assert(_opaque_surface_at(model, sample[0], sample[1]), "%s %s retains its original opaque surface" % [asset, sample[2]])
		if asset == "em40t1_viewmodel":
			for offset in [Vector2.ZERO, Vector2(0.006, 0), Vector2(-0.006, 0), Vector2(0, 0.006), Vector2(0, -0.006)]:
				var hit = _opaque_hit(model, Vector3(offset.x, 0.19 + offset.y, 0.02), Vector3.FORWARD)
				_assert(hit != null and (hit as Vector3).z > -0.08 and (hit as Vector3).z < -0.04, "EM40T1 original center surface covers the rear opening at %s" % offset)
				_assert(hit != null and (hit as Vector3).z < -0.068, "EM40T1 lens remains recessed behind the original aperture rim at %s" % offset)
			for sample in [Vector2(0, -0.079), Vector2(0, -0.077), Vector2(0, -0.074), Vector2(0, -0.070)]:
				var hit = _opaque_hit(model, Vector3(sample.x, 0.30, sample.y), Vector3.DOWN)
				_assert(hit != null and (hit as Vector3).y > 0.225 and (hit as Vector3).y < 0.26, "EM40T1 top seam has opaque housing across z=%s" % sample.y)
		model.free()
	print("OPTIC_SHELLS failures=", _failures)
	quit(1 if _failures else 0)
