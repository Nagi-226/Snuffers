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
	create_timer(35.0).timeout.connect(_timeout)
	root.get_node("GameState").reset()
	var scene := (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 15:
		await process_frame
	var street := scene.get_node("StreetTest")
	var sample := street.get_node("StreetQualitySample")
	var roads := 0
	for body in street.get_node("Ground").get_children():
		var part := String(body.name)
		if not (part.contains("Asphalt") or part.contains("Sidewalk") or part.begins_with("Alley_")):
			continue
		roads += 1
		var source := body.get_child(0) as MeshInstance3D
		var box := source.mesh as BoxMesh
		var expected: Vector3 = body.global_position + Vector3(0, box.size.y * 0.5 + 0.003, 0)
		var found := false
		for mesh_node in sample.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_node as MeshInstance3D
			if not mesh.mesh is PlaneMesh:
				continue
			var plane := mesh.mesh as PlaneMesh
			if mesh.global_position.distance_to(expected) < 0.001 \
					and plane.size.distance_to(Vector2(box.size.x, box.size.z)) < 0.001:
				found = true
				_assert(String(mesh.get_meta("quality_sample_surface", "")) == "road",
					part + " overlay is tagged as a road surface")
				_assert(mesh.find_children("*", "CollisionShape3D", true, false).is_empty(),
					part + " keeps the original collision and adds only a 3mm visual overlay")
				_assert(_pbr(mesh.get_active_material(0)), part + " gets complete world-space scanned PBR")
		_assert(found, "full extent of " + part + " is covered without a sample-boundary seam")
	_assert(roads >= 21, "coverage checks include main/cross/southern roads plus all ten paved alleys and yards")
	var far_north := 0
	var south_cross := 0
	for node in street.get_node("Buildings").find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.get_parent().name)
		if String(mesh.get_meta("quality_sample_surface", "")) != "wall":
			continue
		_assert(_pbr(mesh.get_active_material(0)), part + " wall keeps all scanned PBR maps")
		if mesh.global_position.z < -30.0:
			far_north += 1
		if mesh.global_position.z > 30.0:
			south_cross += 1
	_assert(far_north >= 5, "northern buildings beyond the old sample receive the wall upgrade")
	_assert(south_cross >= 5, "cross-street and southern buildings beyond the old sample receive the wall upgrade")
	_check_second_garage(street)
	_check_vehicle_materials(street)
	var lamps := sample.get_node("StreetLamps")
	_assert(lamps.get_child_count() == 12, "six lamps per side cover the full reachable main street")
	for side in ["W", "E"]:
		var positions: Array[float] = []
		for lamp in lamps.get_children():
			if String(lamp.name).begins_with("Lamp_" + side + "_"):
				positions.append(lamp.position.z)
		positions.sort()
		_assert(positions.size() == 6 and positions.has(46.0), side + " includes the added southern lamp")
		for index in range(1, positions.size()):
			_assert(is_equal_approx(positions[index] - positions[index - 1], 24.0), side + " retains fixed 24m lamp spacing")
	var reflections := sample.find_children("*", "ReflectionProbe", true, false)
	_assert(reflections.size() == 1, "full material coverage keeps the existing single local reflection probe")
	print("test_street_full_quality: %d assertions, %d failures; COMPLETED" % [_assertions, _failures])
	scene.queue_free()
	quit(1 if _failures else 0)


func _pbr(material: Material) -> bool:
	var pbr := material as StandardMaterial3D
	return pbr != null and pbr.albedo_texture != null and pbr.normal_texture != null \
		and pbr.roughness_texture != null and pbr.normal_enabled and pbr.uv1_world_triplanar


func _check_second_garage(street: Node) -> void:
	var walls := 0
	var shutters := 0
	var rear_metal := 0
	var metal: Material = street._get_material("metal_dark")
	for node in street.get_node("Buildings").find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.get_parent().name)
		if not part.begins_with("Gar_E5_"):
			continue
		if part.begins_with("Gar_E5_RearJamb_"):
			rear_metal += 1
			_assert(mesh.get_active_material(0) == metal,
				part + " retains its original dark metal frame material")
		elif part == "Gar_E5_Shutter":
			shutters += 1
			_assert(String(mesh.get_meta("quality_sample_surface", "")) == "metal" \
				and _pbr(mesh.get_active_material(0)), "second garage shutter receives scanned metal PBR")
		elif part.contains("Wall") or part.contains("Upper") or part.contains("Lintel") \
				or part.ends_with("JambN") or part.ends_with("JambS"):
			walls += 1
			_assert(String(mesh.get_meta("quality_sample_surface", "")) == "wall" \
				and _pbr(mesh.get_active_material(0)), part + " receives the complete wall PBR upgrade")
	_assert(walls >= 5 and shutters == 3 and rear_metal == 2,
		"second garage checks cover shell walls, three shutter slats, and two rear metal frames")


func _check_vehicle_materials(street: Node) -> void:
	var checked := 0
	for node in street.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var parent := mesh.get_parent()
		var vehicle := false
		while parent != null and parent != street:
			if String(parent.name).to_lower().contains("car_"):
				vehicle = true
				break
			parent = parent.get_parent()
		if vehicle:
			checked += 1
			_assert(String(mesh.get_meta("quality_sample_surface", "")) != "wall",
				"vehicle mesh " + String(mesh.name) + " keeps its original vehicle material")
	_assert(checked > 0, "material protection checks include actual imported vehicle meshes")


func _timeout() -> void:
	push_error("test_street_full_quality timed out")
	quit(1)
