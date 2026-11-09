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
	for frame in 12:
		await process_frame
	var street := scene.get_node("StreetTest")
	var sample := street.get_node_or_null("StreetQualitySample") as Node3D
	_assert(sample != null, "first playable street contains its material sample")
	_assert(sample != null and sample.has_node("StreetLamps"), "main-road lamps are integrated into the first playable street")
	_assert(sample != null and sample.has_node("SampleRoad"), "quality sample provides a local road surface")
	if sample == null:
		_finish(scene)
		return
	_preserve_original_metal_fixtures(street)
	var lamps := sample.get_node_or_null("StreetLamps")
	var light_nodes: Array[SpotLight3D] = []
	if lamps != null:
		_assert(lamps.get_child_count() == 12, "road contains six lamps on each side after full-street extension")
		for side in ["W", "E"]:
			var side_positions: Array[float] = []
			for index in 6:
				var lamp := lamps.get_node_or_null("Lamp_%s_%d" % [side, index]) as Node3D
				_assert(lamp != null, "lamp exists: %s%d" % [side, index])
				if lamp == null:
					continue
				var expected := Vector3(-5.5 if side == "W" else 5.5, lamp.position.y, 46.0 - index * 24.0)
				side_positions.append(lamp.position.z)
				_assert(lamp.position.distance_to(expected) < 0.001, "lamp %s%d follows 24m spacing outside the asphalt" % [side, index])
				_assert(not lamp.find_children("*", "CollisionShape3D", true, false).is_empty(), "lamp %s%d has a physical pole" % [side, index])
				var lights := lamp.find_children("*", "SpotLight3D", true, false)
				_assert(lights.size() == 1, "lamp %s%d has one downward street light" % [side, index])
				if lights.size() == 1:
					light_nodes.append(lights[0] as SpotLight3D)
			for previous_z in [22.0, -2.0, -26.0, -50.0, -74.0]:
				_assert(side_positions.has(previous_z), "%s retains the previously accepted lamp at Z=%s" % [side, previous_z])
	for path in ["SampleRoad", "SampleSidewalk_W", "SampleSidewalk_E"]:
		var surface := sample.get_node_or_null(path)
		_assert(surface != null, "sample surface exists: " + path)
		if surface != null:
			_assert(surface.find_children("*", "CollisionShape3D", true, false).is_empty() and not surface is CollisionObject3D, path + " retains the original collision geometry")
	var materials_found := {"wall": 0, "road": 0, "metal": 0}
	for node in street.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var kind: String = String(mesh.get_meta("quality_sample_surface", ""))
		if not materials_found.has(kind) or mesh.mesh == null:
			continue
		var found_pbr := false
		for index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index) as StandardMaterial3D
			if material != null and material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null:
				found_pbr = found_pbr or (material.normal_enabled and material.uv1_triplanar and material.uv1_world_triplanar)
		_assert(found_pbr, "tagged %s surface %s has complete world-space PBR textures" % [kind, mesh.name])
		materials_found[kind] += 1
	for kind in materials_found:
		_assert(materials_found[kind] > 0, "sample contains real %s surfaces" % kind)
	_assert(sample.has_node("SampleReflection"), "sample has a local reflection probe")
	var driver = street.get_node("StreetDayNightDriver")
	var environment: Environment = street.get_node("WorldEnvironment").environment
	driver.set_mode(driver.Mode.NIGHT)
	for frame in 4:
		await process_frame
	var night_cards := _visible_cards(street)
	_assert(not light_nodes.is_empty() and _all_lights_on(light_nodes), "street lamps illuminate the night sample")
	_assert(is_equal_approx(environment.fog_density, GameConfig.NIGHT_FOG_DENSITY), "sample preserves the frozen night fog density")
	_assert(is_equal_approx(environment.fog_sky_affect, GameConfig.NIGHT_FOG_SKY_AFFECT), "sample preserves the distant skyline fog guard")
	driver.set_mode(driver.Mode.DAY)
	for frame in 4:
		await process_frame
	_assert(_all_lights_off(light_nodes), "street lamps switch off by day")
	driver.set_mode(driver.Mode.NIGHT)
	for frame in 4:
		await process_frame
	_assert(_all_lights_on(light_nodes), "street lamps restore after a complete day/night cycle")
	_assert(_visible_cards(street) == night_cards, "day/night cycle restores the skyline backdrop visibility")
	_assert(is_equal_approx(environment.fog_density, GameConfig.NIGHT_FOG_DENSITY), "day/night cycle restores original night fog")
	var gate = street.get_node("SceneGate/Link_BGate_E")
	_assert(gate.requires_key and gate.target_scene == "res://scenes/levels/district_b.tscn", "sample preserves the locked gate and destination")
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(20, 1.2, 5), Vector3(24, 1.2, 5))
	_assert(not street.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "metal-gate material upgrade retains its blocking collision")
	_finish(scene)


func _all_lights_on(lights: Array[SpotLight3D]) -> bool:
	for light in lights:
		if not light.is_visible_in_tree() or light.light_energy <= 0.0:
			return false
	return not lights.is_empty()


func _preserve_original_metal_fixtures(street: Node) -> void:
	# Existing builder explicitly assigns metal_dark to these door frames and
	# stair handrails. A wall-material pass must not turn them into plaster.
	var original: Material = street._get_material("metal_dark")
	var checked := 0
	for node in street.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.get_parent().name)
		if not (part.begins_with("Bldg_E1_") or part.begins_with("Bldg_E2_")):
			continue
		if not (part.contains("_JAMB_") or part.contains("_LINTEL") or part.contains("_HR")):
			continue
		checked += 1
		_assert(mesh.get_active_material(0) == original, part + " retains its original dark-metal material")
		_assert(String(mesh.get_meta("quality_sample_surface", "")) != "wall", part + " is not classified as a plaster wall")
	_assert(checked >= 6, "metal preservation checks cover both existing E1/E2 door frames and stair rails")


func _all_lights_off(lights: Array[SpotLight3D]) -> bool:
	for light in lights:
		if light.is_visible_in_tree() and light.light_energy > 0.0:
			return false
	return not lights.is_empty()


func _visible_cards(street: Node) -> int:
	var count := 0
	for card in street.find_children("PanoCard_*", "GeometryInstance3D", true, false):
		if card.is_visible_in_tree():
			count += 1
	return count


func _finish(scene: Node) -> void:
	scene.queue_free()
	print("test_street_quality_sample: %d assertions, %d failures; COMPLETED" % [_assertions, _failures])
	quit(1 if _failures else 0)


func _timeout() -> void:
	push_error("test_street_quality_sample timed out before completing all cases")
	quit(1)
