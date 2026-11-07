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


func _press(player: CharacterBody3D, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	player._unhandled_input(event)


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
	_assert(player.KEY_INTERACT == KEY_F and player.KEY_MEDKIT == KEY_G, "interaction uses F and medkit uses G")
	_assert(state.nano_mode == &"armor" and hud._awareness_state == &"green", "default armor mode and green awareness")
	hud._process(0.0)
	_assert(hud._nano_armor_overlay.visible, "armor mode shows surrounding hexagons")
	enemy.alerted = true
	hud._process(0.1)
	_assert(hud._awareness_state == &"yellow", "alerted enemy without sight turns awareness yellow")
	enemy._cached_can_see = true
	hud._process(0.1)
	_assert(hud._awareness_state == &"red", "enemy sight turns awareness red")
	_assert(root.get_node("GameConfig").NANO_POWER_SPEED * 3.6 > 60.0, "passive power sprint exceeds 60km/h")
	player._try_jump()
	player._release_jump()
	await physics_frame
	await physics_frame
	_assert(is_equal_approx(player.velocity.y, 4.5), "short Space performs a normal jump")
	for frame in 100:
		await physics_frame
	player._try_jump()
	player._jump_charge_time = 1.0
	player._release_jump()
	var max_height := 0.0
	for frame in 100:
		await physics_frame
		max_height = maxf(max_height, player.global_position.y)
	_assert(max_height > 6.0, "holding Space performs a power jump over six meters")
	_press(player, KEY_E)
	_assert(state.nano_mode == &"stealth", "E toggles stealth mode")
	player._process(0.0)
	_assert(player.get_node("Camera3D/WeaponMount").visible, "stealth keeps a visible weapon outline")
	var meshes := player.get_node("Camera3D/WeaponMount").find_children("*", "MeshInstance3D", true, false)
	_assert(not meshes.is_empty() and (meshes[0] as MeshInstance3D).transparency > 0.8, "stealth outline is transparent rather than hidden")
	hud._process(0.0)
	_assert(not hud._nano_armor_overlay.visible, "stealth hides armor hexagons")
	_assert(not enemy._update_sight(0.1, player.global_position), "stealth blocks enemy sight")
	state.armor = 100.0
	player._update_nano_energy(1.0, false)
	_assert(is_equal_approx(state.armor, 100.0), "stationary stealth drains no energy")
	player._update_nano_energy(1.0, true)
	_assert(state.armor < 100.0, "moving stealth drains energy")
	state.armor = 1.0
	player._update_nano_energy(1.0, true)
	_assert(state.nano_mode == &"armor", "empty energy forces armor mode")
	state.armor = 100.0
	_press(player, KEY_E)
	_assert(state.nano_mode == &"stealth", "E can re-enable stealth after recharging")
	_press(player, KEY_Q)
	_assert(state.nano_mode == &"armor", "Q explicitly selects armor mode")
	for step in 40:
		hud._process(0.1)
	_assert(hud._awareness_state == &"green" and hud._awareness < 0.35, "stealth decays awareness back to green")
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
