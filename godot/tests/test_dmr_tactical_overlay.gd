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
	root.size = Vector2i(1920, 1080)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = Vector3(0, 1.6, 0)
	camera.current = true
	var overlay = load("res://scripts/player/dmr_tactical_overlay.gd").new()
	overlay.camera = camera
	overlay.size = Vector2(1920, 1080)
	root.add_child(overlay)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.5, 4, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = Vector3(0, 1.6, -25)
	var enemy := CharacterBody3D.new()
	enemy.add_to_group(&"enemy")
	var enemy_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	enemy_shape.shape = capsule
	enemy_shape.position.y = 0.9
	enemy.add_child(enemy_shape)
	world.add_child(enemy)
	enemy.global_position = Vector3(2, 0, -40)
	await physics_frame
	await physics_frame
	overlay._refresh_range()
	_assert(absf(overlay._range_distance - 24.9) < 0.05, "range reads arbitrary wall surface at 24.9m")
	_assert(overlay._range_text == "RNG 24.9 M", "range text updates from the center ray")
	wall.global_position = Vector3(0, 1.6, -50)
	await physics_frame
	overlay._refresh_range()
	_assert(absf(overlay._range_distance - 49.9) < 0.05, "range changes to 49.9m without any lock")
	wall.global_position = Vector3(0, 1.6, -10)
	await physics_frame
	overlay._refresh_targets()
	overlay._refresh_range()
	_assert(overlay._targets.size() == 1 and overlay._primary_target == enemy, "visible off-center enemy receives a tracking frame")
	_assert(absf(overlay._range_distance - 9.9) < 0.05, "range remains independent from tracked enemy")
	_assert(overlay._targets[0].rect.size.x > 0.0 and overlay._targets[0].rect.size.y > 0.0, "enemy collision bounds project to a screen rectangle")
	wall.global_position = Vector3(2, 1.0, -35)
	await physics_frame
	overlay._refresh_targets()
	_assert(overlay._targets.is_empty(), "occluded enemy receives no frame")
	wall.global_position = Vector3(0, 1.6, -200)
	await physics_frame
	overlay._refresh_targets()
	_assert(overlay._targets.size() == 1, "target reacquires after occlusion clears")
	enemy.global_position = Vector3(100, 0, -40)
	await physics_frame
	overlay._refresh_targets()
	_assert(overlay._targets.is_empty(), "off-screen enemy receives no frame")
	overlay._refresh_range()
	_assert(is_inf(overlay._range_distance) and overlay._range_text == "RNG >180 M", "out-of-range center ray has an explicit display")
	_assert(is_equal_approx(overlay._mil_to_pixels(2.0), overlay._mil_to_pixels(1.0) * 2.0), "MIL marks scale by angular interval")
	_assert(overlay._mil_to_pixels(100.0) > overlay._scope_radius() * 0.15 and overlay._mil_to_pixels(200.0) < overlay._scope_radius(), "MIL ticks spread across the large scope instead of the center ring")
	_assert(GameConfig.DMR_SCOPE_MIL_STEPS.max() >= 100, "configured MIL labels use outer-scope intervals")
	enemy.queue_free()
	await process_frame
	overlay._refresh_targets()
	_assert(overlay._targets.is_empty(), "freed target is removed without stale references")
	world.queue_free()
	overlay.queue_free()
	await process_frame
	_free_autoloads()
	print("test_dmr_tactical_overlay: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


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
