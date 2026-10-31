extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

var _failures := 0
var _autoload_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_recreate_autoloads()
	var district := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(district)
	await process_frame
	await physics_frame
	_assert_mesh_size(district, "Ground/Mesh", Vector3(460, 0.3, 320), "expanded legacy yard")
	_assert_mesh_size(district, "WarehouseFloor/Mesh", Vector3(350, 0.1, 200), "350x200 warehouse floor")
	_assert_mesh_size(district, "WarehouseRoof/Mesh", Vector3(351, 0.35, 201), "warehouse roof spans the full footprint")
	for landmark in [&"WaterTower", &"LegacyCabin", &"LegacyBunker"]:
		_assert(district.has_node(NodePath(String(landmark))), "legacy landmark retained: %s" % landmark)
		if district.has_node(NodePath(String(landmark))):
			var node := district.get_node(NodePath(String(landmark))) as Node3D
			var p := node.global_position
			_assert(absf(p.x) > 175.0 or p.z < -120.0 or p.z > 80.0, "%s stays outside warehouse footprint" % landmark)
	for i in 4:
		var x := [-120.0, -40.0, 40.0, 120.0][i] as float
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 1.7, 82), Vector3(x, 1.7, 76))
		var hit := district.get_world_3d().direct_space_state.intersect_ray(query)
		_assert(hit.is_empty(), "cargo door %d is physically open" % i)
	var player := district.get_node("Player") as Node3D
	_assert(is_equal_approx(player.position.z, 117.0), "player spawn follows the relocated APC (z=%f)" % player.position.z)
	_assert(is_equal_approx((district.get_node("JB02APC") as Node3D).position.z, 109.2), "APC moves to the outer yard")
	_assert(is_equal_approx((district.get_node("Equipment_dmr") as Node3D).position.z, 111.65), "DMR pickup follows APC")
	_assert(is_equal_approx((district.get_node("Equipment_shotgun") as Node3D).position.z, 111.65), "shotgun pickup follows APC")
	_assert(is_equal_approx((district.get_node("Link_DistrictBReturn") as Node3D).position.z, 150.0), "return link remains behind the player")
	for lore_name in [&"LanternReconMarker", &"LanternSurveyBeacon", &"WickMemento"]:
		_assert(district.has_node(NodePath(String(lore_name))), "prequel lore exists: %s" % lore_name)
		if district.has_node(NodePath(String(lore_name))):
			var lore := district.get_node(NodePath(String(lore_name)))
			_assert(lore.has_method(&"interact") and lore.has_method(&"interact_prompt"), "%s supports E interaction" % lore_name)
	var wall_mesh := district.get_node("WarehouseFrontPier_0/Mesh") as MeshInstance3D
	var wall_material := wall_mesh.mesh.material as StandardMaterial3D
	_assert(wall_material != null and wall_material.normal_texture != null and wall_material.roughness_texture != null, "warehouse exterior uses full PBR textures")
	_assert(district.has_node("WickSPAS12") and district.has_node("WickAmmoBox"), "SPAS and 12GA ammo are displayed on a hall rack")
	_assert(not district.has_node("WickShelf"), "standalone souvenir shelf is removed")
	_assert((district.get_node("WickSPAS12") as Node3D).position.y > 1.5, "SPAS rests on an existing rack shelf rather than the floor")
	_assert(district.has_node("PartitionWestA") and district.has_node("PartitionEastA"), "warehouse has interior maze partitions")
	_assert(district.has_node("ReceivingOffice") and district.has_node("CargoPallet_0"), "warehouse has an office and freight props")
	_assert(district.has_node("HulkingHost"), "second district contains the secondary-mutated host")
	var hosts := district.find_children("HostParasite_*", "CharacterBody3D", true, false)
	var spores := district.find_children("SporeHusk_*", "CharacterBody3D", true, false)
	var hulks := district.find_children("HulkingHost*", "CharacterBody3D", true, false)
	_assert(hosts.size() == 30 and spores.size() == 24 and hulks.size() == 10, "warehouse roster is 30 human hosts, 24 spores and 10 hulking hosts")
	_assert(district.has_node("WarehouseSign/Panel") and district.has_node("RouteSign/Panel"), "cargo zone text uses mounted electronic screens")
	if not hosts.is_empty():
		_assert(hosts[0]._animation_player != null and hosts[0]._animation_player.has_animation(&"walk"), "human host plays its rigged animation in district")
	if not spores.is_empty():
		_assert(spores[0]._animation_player != null and spores[0]._animation_player.has_animation(&"crawl") and spores[0]._animation_player.has_animation(&"leap"), "spore plays crawl and leap clips in district")
	district.queue_free()
	await process_frame
	_free_autoloads()
	print("test_district_b_layout: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert_mesh_size(root_node: Node3D, path: String, expected: Vector3, label: String) -> void:
	if not root_node.has_node(path):
		_assert(false, "%s node exists" % label)
		return
	var mi := root_node.get_node(path) as MeshInstance3D
	var box := mi.mesh as BoxMesh
	_assert(box != null and box.size.is_equal_approx(expected), label)


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _recreate_autoloads() -> void:
	for entry in AUTOLOADS:
		var node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
		_autoload_nodes.append(node)


func _free_autoloads() -> void:
	for node in _autoload_nodes:
		root.remove_child(node)
		node.free()
	_autoload_nodes.clear()
