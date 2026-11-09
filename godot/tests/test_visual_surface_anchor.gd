extends SceneTree

var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var container := Node3D.new()
	world.add_child(container)
	var receiver := StaticBody3D.new()
	container.add_child(receiver)
	var source := MeshInstance3D.new()
	source.mesh = _triangle_mesh()
	container.add_child(source)
	source.position.z = -0.25
	source.scale = Vector3.ONE * 0.001
	await process_frame
	# Runtime load follows the existing test harness's autoload ordering.
	var solver = load("res://scripts/weapons/hit_solver.gd")
	var surface: Dictionary = solver.resolve_visual_surface(Vector3.ZERO, Vector3.BACK, receiver)
	_assert(not surface.is_empty(), "visual anchor resolves a real millimetre-scale imported-style mesh")
	if not surface.is_empty():
		_assert(surface.position.distance_to(Vector3(0, 0, -0.25)) < 0.001,
			"visual anchor reaches the skin beyond a 0.2m half-depth proxy gap")
		_assert(surface.normal.dot(Vector3.BACK) > 0.999, "visual anchor returns the actual outward skin normal")
	container.position = Vector3(4, 2, 3)
	container.rotation.y = 0.4
	surface = solver.resolve_visual_surface(container.global_position,
		container.global_basis.z, receiver)
	_assert(not surface.is_empty(), "cached BVH remains usable after the receiver's container moves and rotates")
	if not surface.is_empty():
		_assert(surface.position.distance_to(container.global_transform * Vector3(0, 0, -0.25)) < 0.001,
			"moving and rotating a proxy container transforms its visual anchor correctly")
		_assert(surface.normal.dot(container.global_basis.z) > 0.999,
			"moving and rotating a proxy container transforms its normal correctly")
	var unrelated := MeshInstance3D.new()
	unrelated.mesh = _triangle_mesh()
	unrelated.position.z = -0.5
	unrelated.scale = Vector3.ONE * 0.001
	world.add_child(unrelated)
	var ordinary_wall := StaticBody3D.new()
	world.add_child(ordinary_wall)
	surface = solver.resolve_visual_surface(Vector3.ZERO, Vector3.BACK, ordinary_wall)
	_assert(surface.is_empty(),
		"ordinary scene-root collision must not borrow an unrelated sibling mesh as its skin")
	var room := StaticBody3D.new()
	world.add_child(room)
	room.position.x = 10.0
	var room_skin := MeshInstance3D.new()
	room_skin.mesh = _open_room_mesh()
	room.add_child(room_skin)
	surface = solver.resolve_visual_surface(room.global_position, Vector3.BACK, room)
	_assert(not surface.is_empty(), "an open imported room resolves a visual face owned by its receiver")
	if not surface.is_empty():
		_assert(surface.position.distance_to(room.global_position + Vector3(0, 0, -0.25)) < 0.001,
			"an open room chooses the face nearest the physical impact rather than the opposite wall")
	var shared_mesh := source.mesh
	container.queue_free()
	await process_frame
	var replacement := StaticBody3D.new()
	world.add_child(replacement)
	replacement.position.x = 20.0
	var replacement_skin := MeshInstance3D.new()
	replacement_skin.mesh = shared_mesh
	replacement_skin.position.z = -0.25
	replacement_skin.scale = Vector3.ONE * 0.001
	replacement.add_child(replacement_skin)
	surface = solver.resolve_visual_surface(replacement.global_position, Vector3.BACK, replacement)
	_assert(not surface.is_empty(), "cached mesh BVH remains usable after its original receiver has been deleted")
	if not surface.is_empty():
		_assert(surface.position.distance_to(Vector3(20, 0, -0.25)) < 0.001,
			"cached geometry binds a new receiver without retaining the deleted node's transform")
	print("test_visual_surface_anchor: %d assertions, %d failures; COMPLETED" % [_assertions, _failures])
	world.queue_free()
	await process_frame
	quit(1 if _failures else 0)


func _triangle_mesh() -> ArrayMesh:
	# Official ArrayMesh surface API; authored units deliberately model imported mm data.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1000, -1000, 0), Vector3(1000, -1000, 0), Vector3(0, 1000, 0),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _open_room_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, -1, -0.25), Vector3(1, -1, -0.25), Vector3(0, 1, -0.25),
		Vector3(-1, -1, 4), Vector3(1, -1, 4), Vector3(0, 1, 4),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
