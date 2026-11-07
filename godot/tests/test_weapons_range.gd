extends SceneTree

var _failures := 0
var _enemy_shots := 0
var _deaths := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _has_ancestor(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _run() -> void:
	var state = root.get_node("GameState")
	var config = root.get_node("GameConfig")
	var events = root.get_node("Events")
	state.reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	events.enemy_fired.connect(func(_kind, _pos): _enemy_shots += 1)
	events.enemy_died.connect(func(_enemy): _deaths += 1)
	_assert(get_nodes_in_group(&"enemy").is_empty(), "range contains no enemy AI")
	var targets := get_nodes_in_group(&"range_target")
	_assert(targets.size() == 10, "range contains ten passive NPC targets")
	_assert(state.weapon_unlocked.values().all(func(unlocked): return unlocked), "all available weapons are unlocked")
	_assert(not scene.has_node("Garrison") and not scene.has_node("MissionDirector") and not scene.has_node("CombatFX"), "legacy garrison and combat systems are absent")
	_assert(scene.has_node("RangeFacilities/IndoorMaze/Roof") and scene.has_node("RangeFacilities/IndoorMaze/TurnThree"), "covered multi-turn indoor maze exists")
	_assert(scene.has_node("RangeFacilities/NearOverwatch/Platform"), "near overwatch platform exists")
	_assert(scene.get_node("RangeFacilities/SniperAccessStairs").get_child_count() == 49, "twelve meter sniper tower has forty-eight steps and a landing")
	_assert(scene.get_node("RangeFacilities/Targets/CloseTarget").get_script().resource_path == "res://scripts/levels/range_target.gd", "targets use the passive target script")
	var player := scene.get_node("Player") as CharacterBody3D
	var target := scene.get_node("RangeFacilities/Targets/CloseTarget") as CharacterBody3D
	player.global_position = Vector3(44, 0.1, 20)
	var camera := player.get_node("Camera3D") as Camera3D
	var day_switch := scene.get_node_or_null("RangeFacilities/DayNightSwitch")
	_assert(day_switch != null, "range has a physical day/night switch")
	if day_switch != null:
		player.global_position = day_switch.global_position + Vector3(0, 0.1, -2.0)
		camera.look_at(day_switch.global_position + Vector3(0, 0.75, 0))
		await physics_frame
		player._update_interact_target()
		_assert(player._interact_target == day_switch, "aiming at the switch acquires it through the shared F interaction ray")
		state.night_vision = true
		player._try_interact()
		var day_night = scene.get_node("GreyboxArena/DayNightController")
		var environment: Environment = day_night.get_node("WorldEnvironment").environment
		_assert(day_night.current_mode == day_night.Mode.DAY and not state.is_night and not state.night_vision, "F switches to day and disables active night vision")
		_assert(environment.background_mode == Environment.BG_SKY and environment.sky != null and environment.sky.sky_material is PanoramaSkyMaterial, "day mode uses a panoramic sky")
		if environment.sky != null and environment.sky.sky_material is PanoramaSkyMaterial:
			_assert(environment.sky.sky_material.panorama.resource_path == "res://assets/textures/skies/kloofendal_48d_partly_cloudy_puresky_2k.hdr", "day sky uses the registered Poly Haven CC0 HDR")
		_assert(day_switch.interact_prompt() == "F  切换黑夜", "switch prompt offers the return to night")
		player._try_interact()
		_assert(day_night.current_mode == day_night.Mode.NIGHT and state.is_night and environment.background_mode == Environment.BG_COLOR, "second F restores the original night environment")
	player.global_position = Vector3(44, 0.1, 20)
	camera.look_at(target.global_position + Vector3(0, 1.0, 0))
	state.current_weapon = &"rifle"
	var rifle := player.get_node("Camera3D/WeaponMount/Rifle")
	var old_health: float = target.health
	var fired: bool = rifle._fire()
	_assert(fired and target.health < old_health, "real rifle ray damages the close NPC target")
	for frame in 60:
		await physics_frame
	_assert(_enemy_shots == 0 and is_equal_approx(state.hp, config.HEALTH_MAX), "passive NPCs never attack the player")
	for target_name in ["FarSniperTarget", "FarMachineTarget", "FarBunkerTarget"]:
		var far := scene.get_node("RangeFacilities/Targets/" + target_name) as CharacterBody3D
		_assert(far.global_position.distance_to(Vector3(80, 12.25, 0)) > 160.0, target_name + " is beyond 160 meters")
		var eye := far.get_node("Eye") as Marker3D
		var query := PhysicsRayQueryParameters3D.create(Vector3(80, 13.65, 0), eye.global_position)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		_assert(not hit.is_empty() and _has_ancestor(hit.collider, far), target_name + " has a clear sniper line of sight")
	var near_query := PhysicsRayQueryParameters3D.create(Vector3(30, 5.65, -25), Vector3(30, 1.0, -40))
	var near_hit := scene.get_world_3d().direct_space_state.intersect_ray(near_query)
	_assert(not near_hit.is_empty() and _has_ancestor(near_hit.collider, scene.get_node("RangeFacilities/Targets/NearRangeTarget")), "near overwatch has a clear close-range line of sight")
	target.take_damage(999.0)
	_assert(_deaths == 1, "passive target retains its death event")
	await create_timer(3.0).timeout
	_assert(not is_instance_valid(target), "target is removed after its death animation")
	scene.queue_free()
	await process_frame
	print("test_weapons_range: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
