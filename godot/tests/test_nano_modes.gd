extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var state = root.get_node("GameState")
	state.reset()
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(100, 0.2, 100)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	ground.position.y = -0.1
	root.add_child(ground)
	var enemy := (load("res://scripts/enemies/enemy_base.gd") as GDScript).new() as CharacterBody3D
	var eye := Marker3D.new()
	eye.name = "Eye"
	enemy.add_child(eye)
	root.add_child(enemy)
	await process_frame
	_assert(state.nano_mode == &"armor" and hud._awareness_state == &"green", "default armor mode and green awareness")
	enemy.alerted = true
	hud._process(0.1)
	_assert(hud._awareness_state == &"yellow", "alerted enemy without sight turns awareness yellow")
	enemy._cached_can_see = true
	hud._process(0.1)
	_assert(hud._awareness_state == &"red", "enemy sight turns awareness red")
	player._cycle_nano_mode()
	_assert(state.nano_mode == &"power", "Q enters power mode")
	var forward := InputEventKey.new()
	forward.physical_keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	var sprint := InputEventKey.new()
	sprint.physical_keycode = KEY_SHIFT
	sprint.pressed = true
	Input.parse_input_event(sprint)
	_assert(root.get_node("GameConfig").NANO_POWER_SPEED * 3.6 > 60.0, "power sprint exceeds 60km/h")
	player._try_jump()
	var max_height := 0.0
	for frame in 90:
		await physics_frame
		max_height = maxf(max_height, player.global_position.y)
	_assert(max_height > 6.0, "power jump exceeds six meters")
	player._cycle_nano_mode()
	_assert(state.nano_mode == &"stealth", "Q enters stealth mode")
	player._process(0.0)
	_assert(not player.get_node("Camera3D/WeaponMount").visible, "stealth hides first-person arms and weapons")
	_assert(not enemy._update_sight(0.1, player.global_position), "stealth blocks enemy sight")
	for step in 40:
		hud._process(0.1)
	_assert(hud._awareness_state == &"green" and hud._awareness < 0.35, "stealth decays awareness back to green")
	state.nano_mode = &"armor"
	state.armor = 0.0
	state.hp = 100.0
	player._apply_damage(&"body", 100.0)
	_assert(is_equal_approx(state.hp, 65.0), "armor mode reduces incoming damage")
	player.queue_free()
	hud.queue_free()
	enemy.queue_free()
	ground.queue_free()
	await process_frame
	print("test_nano_modes: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
