extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

var _failures := 0
var _hits := 0
var _smash_sounds := 0
var _autoload_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_recreate_autoloads()
	var world := Node3D.new()
	root.add_child(world)
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	world.add_child(player)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(100, 0.2, 100)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	ground.position.y = -0.1
	world.add_child(ground)
	var spore := (load("res://scenes/enemies/spore_husk.tscn") as PackedScene).instantiate()
	spore.position = Vector3(0, 0, 5)
	world.add_child(spore)
	var hulking := (load("res://scenes/enemies/hulking_host.tscn") as PackedScene).instantiate()
	hulking.position = Vector3(0, 0, -2.5)
	world.add_child(hulking)
	root.get_node("Events").player_damaged.connect(_on_player_damaged)
	root.get_node("Events").enemy_fired.connect(_on_enemy_fired)
	await physics_frame
	await physics_frame
	_assert(spore._animation_player != null and spore._animation_player.has_animation(&"crawl") and spore._animation_player.has_animation(&"leap"), "spore rig exposes crawl and leap clips")
	_assert(hulking._animation_player != null and hulking._animation_player.has_animation(&"attack") and hulking._animation_player.has_animation(&"walk"), "hulking rig exposes walk and right-arm attack clips")
	_assert(is_equal_approx((hulking.get_node("BodyMesh") as Node3D).rotation.y, root.get_node("GameConfig").HULKING_HOST_MODEL_YAW_OFFSET), "hulking model forward is aligned with movement")
	spore._begin_leap(player.global_position)
	_assert(spore.current_state == spore.State.LEAP, "spore enters physical leap state")
	_assert(spore.velocity.y > 0.0 and Vector2(spore.velocity.x, spore.velocity.z).length() > 1.0, "spore leap has ballistic vertical and horizontal velocity")
	_assert(not spore._leap_hit, "spore leap starts with a single available hit")
	spore.set_physics_process(false)
	var skeletons := hulking.get_node("BodyMesh").find_children("*", "Skeleton3D", true, false)
	var skeleton := skeletons[0] as Skeleton3D
	var thigh_bone := skeleton.find_bone("thigh_r")
	var hips_bone := skeleton.find_bone("hips")
	hulking.position.z = -20.0
	var thigh_start := skeleton.get_bone_global_pose(thigh_bone)
	var hips_start_y := skeleton.get_bone_global_pose(hips_bone).origin.y
	hulking._play(&"walk", true)
	await create_timer(0.25).timeout
	_assert(not thigh_start.is_equal_approx(skeleton.get_bone_global_pose(thigh_bone)), "Mixamo walk rotates the thighs during forward locomotion")
	_assert(not is_equal_approx(hips_start_y, skeleton.get_bone_global_pose(hips_bone).origin.y), "Mixamo walk has real hip vertical motion")
	hulking.position.z = -2.5
	var arm_bone := skeleton.find_bone("upper_arm_r")
	var pose_start := skeleton.get_bone_global_pose(arm_bone)
	hulking.current_state = hulking.State.WINDUP
	hulking._state_timer = 0.4
	hulking._play(&"attack", true)
	await create_timer(0.2).timeout
	var pose_windup := skeleton.get_bone_global_pose(arm_bone)
	_assert(not pose_start.is_equal_approx(pose_windup), "hulking right arm actually rotates during attack anticipation")
	_assert(_hits == 0 and _smash_sounds == 0, "hulking smash does not deal damage or play sound during right-arm anticipation")
	await create_timer(0.5).timeout
	_assert(not pose_windup.is_equal_approx(skeleton.get_bone_global_pose(arm_bone)), "hulking right arm actually swings through the impact window")
	_assert(_hits == 1, "hulking smash deals damage only after the impact window")
	_assert(_smash_sounds == 1, "hulking smash plays one impact sound")
	_assert(hulking.current_state == hulking.State.RECOVER, "hulking enters recovery after smash")
	world.queue_free()
	await process_frame
	root.get_node("Events").player_damaged.disconnect(_on_player_damaged)
	root.get_node("Events").enemy_fired.disconnect(_on_enemy_fired)
	_free_autoloads()
	print("test_new_enemies: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _on_player_damaged(_part: StringName, _amount: float) -> void:
	_hits += 1


func _on_enemy_fired(kind: StringName, _position: Vector3) -> void:
	if kind == &"hulking_smash":
		_smash_sounds += 1


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
