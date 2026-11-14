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


func _set_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


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
	var config = root.get_node("GameConfig")
	_assert(player.KEY_INTERACT == KEY_F and player.KEY_MEDKIT == KEY_T, "interaction uses F and medkit uses T")
	_assert(state.nano_mode == &"normal" and hud._awareness_state == &"green", "default normal mode and green awareness")
	hud._process(0.0)
	_assert(not hud._nano_armor_overlay.visible, "normal mode hides armor hexagons")
	_assert(hud._nano_mode_label.text == "模式：常规", "HUD starts in normal mode")
	_assert(hud._awareness_bar.get_child(0).value == 1.0 and hud._awareness_bar.get_child(1).value == 0.0 and hud._awareness_bar.get_child(2).value == 0.0, "green awareness lights only the first segment")
	enemy.alerted = true
	hud._process(0.1)
	_assert(hud._awareness_state == &"yellow", "alerted enemy without sight turns awareness yellow")
	_assert(hud._awareness_bar.get_child(0).value == 1.0 and hud._awareness_bar.get_child(1).value == 1.0 and hud._awareness_bar.get_child(2).value == 0.0, "yellow awareness lights the first two segments")
	enemy._cached_can_see = true
	hud._process(0.1)
	_assert(hud._awareness_state == &"red", "enemy sight turns awareness red")
	_assert(hud._awareness_bar.get_child(0).value == 1.0 and hud._awareness_bar.get_child(1).value == 1.0 and hud._awareness_bar.get_child(2).value == 1.0, "red awareness lights all three segments")
	_assert(config.NANO_POWER_SPEED * 3.6 > 60.0, "passive power sprint exceeds 60km/h")
	state.armor = 100.0
	player._try_jump()
	player._release_jump()
	await physics_frame
	await physics_frame
	_assert(is_equal_approx(player.velocity.y, 4.5) and is_equal_approx(state.armor, 100.0), "short Space performs a normal jump without energy cost")
	for frame in 160:
		await physics_frame
	player._try_jump()
	player._jump_charge_time = 1.0
	player._release_jump()
	var max_height := 0.0
	for frame in 160:
		await physics_frame
		max_height = maxf(max_height, player.global_position.y)
	_assert(max_height > 6.0, "normal mode can power jump over six meters")
	_assert(is_equal_approx(state.armor, 100.0 - config.NANO_POWER_JUMP_COST) and state.nano_mode == &"normal", "normal power jump consumes energy without changing mode")
	_press(player, KEY_Q)
	_assert(state.nano_mode == &"armor" and hud._nano_mode_label.text == "模式：装甲", "Q enables armor from normal")
	hud._process(0.0)
	_assert(hud._nano_armor_overlay.visible, "armor mode shows surrounding hexagons")
	_press(player, KEY_Q)
	_assert(state.nano_mode == &"normal", "Q disables armor back to normal")
	_press(player, KEY_E)
	_assert(state.nano_mode == &"stealth", "E enables stealth from normal")
	_assert(hud._nano_mode_label.text == "模式：隐形" and hud._message_label.text == "模式：隐形", "mode changes use Chinese labels without the nano prefix")
	player._process(0.0)
	_assert(player.get_node("Camera3D/WeaponMount").visible, "stealth keeps a visible weapon outline")
	var meshes := player.get_node("Camera3D/WeaponMount").find_children("*", "MeshInstance3D", true, false)
	_assert(not meshes.is_empty() and (meshes[0] as MeshInstance3D).transparency > 0.8, "stealth outline is transparent rather than hidden")
	hud._process(0.0)
	_assert(not hud._nano_armor_overlay.visible, "stealth hides armor hexagons")
	_assert(not enemy._update_sight(0.1, player.global_position), "stealth blocks enemy sight")
	_press(player, KEY_E)
	_assert(state.nano_mode == &"normal", "E disables stealth back to normal")
	_press(player, KEY_E)
	_press(player, KEY_Q)
	_assert(state.nano_mode == &"armor", "Q switches directly from stealth to armor")
	_press(player, KEY_E)
	_assert(state.nano_mode == &"stealth", "E switches directly from armor to stealth")
	state.armor = 100.0
	player._update_nano_energy(1.0, false)
	_assert(is_equal_approx(state.armor, 100.0), "stationary stealth drains no energy")
	player._update_nano_energy(1.0, true)
	_assert(is_equal_approx(state.armor, 100.0 - config.NANO_STEALTH_WALK_DRAIN_PER_SEC), "stealth walking uses the walk drain rate")
	_set_key(KEY_W, true)
	_set_key(KEY_SHIFT, true)
	_assert(is_equal_approx(player._current_speed(), config.NANO_POWER_SPEED) and state.nano_mode == &"stealth", "power sprint stacks with stealth")
	player._update_nano_energy(1.0, true)
	_assert(is_equal_approx(state.armor, 100.0 - config.NANO_STEALTH_WALK_DRAIN_PER_SEC - config.NANO_STEALTH_SPRINT_DRAIN_PER_SEC), "stealth sprint drains faster than stealth walking")
	_set_key(KEY_SHIFT, false)
	_set_key(KEY_W, false)
	state.armor = 1.0
	player._update_nano_energy(1.0, true)
	_assert(state.nano_mode == &"normal" and is_equal_approx(state.armor, 0.0), "empty energy disables stealth back to normal")
	state.armor = 100.0
	_press(player, KEY_Q)
	_set_key(KEY_W, true)
	_set_key(KEY_SHIFT, true)
	_assert(is_equal_approx(player._current_speed(), config.NANO_POWER_SPEED) and state.nano_mode == &"armor", "power sprint stacks with armor")
	player._update_nano_energy(1.0, true)
	_assert(is_equal_approx(state.armor, 100.0 - config.NANO_POWER_SPRINT_DRAIN_PER_SEC), "armor power sprint uses the power drain rate")
	_set_key(KEY_SHIFT, false)
	_set_key(KEY_W, false)
	player._try_jump()
	player._jump_charge_time = 1.0
	player._release_jump()
	await physics_frame
	await physics_frame
	_assert(player.velocity.y > config.JUMP_VELOCITY and player.velocity.y <= config.NANO_POWER_JUMP_VELOCITY and state.nano_mode == &"armor", "power jump stacks with armor")
	for frame in 160:
		await physics_frame
	_press(player, KEY_E)
	state.armor = 100.0
	player._try_jump()
	player._jump_charge_time = 1.0
	player._release_jump()
	await physics_frame
	await physics_frame
	_assert(player.velocity.y > config.JUMP_VELOCITY and player.velocity.y <= config.NANO_POWER_JUMP_VELOCITY and state.nano_mode == &"stealth", "power jump stacks with stealth")
	for frame in 160:
		await physics_frame
	_press(player, KEY_E)
	state.armor = 100.0
	_set_key(KEY_W, true)
	_set_key(KEY_SHIFT, true)
	_assert(is_equal_approx(player._current_speed(), config.NANO_POWER_SPEED) and state.nano_mode == &"normal", "normal mode can power sprint")
	player._armor_regen_wait = config.ARMOR_REGEN_DELAY
	player._update_nano_energy(1.0, true)
	_assert(is_equal_approx(state.armor, 100.0 - config.NANO_POWER_SPRINT_DRAIN_PER_SEC), "normal power sprint consumes energy")
	_assert(is_equal_approx(player._armor_regen_wait, 0.0), "ability use restarts the regeneration delay")
	_set_key(KEY_SHIFT, false)
	_set_key(KEY_W, false)
	enemy._cached_can_see = false
	enemy.alerted = false
	for step in 40:
		hud._process(0.1)
	_assert(hud._awareness_state == &"green" and hud._awareness < 0.35, "awareness decays back to green")
	_press(player, KEY_Q)
	state.armor = 0.0
	state.hp = 100.0
	player._apply_damage(&"body", 100.0)
	_assert(is_equal_approx(state.hp, 65.0), "armor mode reduces incoming damage")
	var audio = (load("res://scripts/ui/audio_manager.gd") as GDScript).new()
	root.add_child(audio)
	var sound_children: int = audio.get_child_count()
	var events = root.get_node("Events")
	events.nano_mode_changed.emit(&"armor")
	var armor_player := audio.get_child(audio.get_child_count() - 1) as AudioStreamPlayer
	_assert(audio.get_child_count() == sound_children + 1 and armor_player.stream == audio._get_stream(&"nano_armor"), "armor mode plays its activation sound once")
	_assert(armor_player.stream.get_length() > 0.8 and armor_player.stream.get_length() < 1.5, "armor uses the short mech and shield activation asset")
	events.nano_mode_changed.emit(&"stealth")
	var stealth_player := audio.get_child(audio.get_child_count() - 1) as AudioStreamPlayer
	_assert(audio.get_child_count() == sound_children + 2 and stealth_player.stream == audio._get_stream(&"nano_stealth") and stealth_player.stream != audio._get_stream(&"nightvision"), "stealth mode plays its own activation sound once")
	_assert(stealth_player.stream.get_length() > 1.5, "stealth uses the new forcefield activation asset")
	events.nano_mode_changed.emit(&"normal")
	_assert(audio.get_child_count() == sound_children + 2, "normal mode does not add an activation sound")
	await create_timer(3.3).timeout
	audio.queue_free()
	player.queue_free()
	hud.queue_free()
	enemy.queue_free()
	ground.queue_free()
	await process_frame
	print("test_nano_modes: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
