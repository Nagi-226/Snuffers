## Native production range: persistent inventory, real GLB and cyan pulse pixels.
extends SceneTree

const OUTPUT_DIR := "res://tmp_shots/ec60e_hud"
var _assertions := 0
var _failures := 0
var _world: Node3D
var _player: CharacterBody3D
var _inventory: Control
var _state: Node
var _events: Node
var _config: Node
var _fx: Node3D
var _legacy_explosions := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _run() -> void:
	_assert(DisplayServer.get_name() != "headless", "EC-60E evidence uses native rendering")
	if _failures:
		quit(1)
		return
	create_timer(50.0, true).timeout.connect(_timeout)
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state.reset()
	_world = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	current_scene = _world
	for frame in 12:
		await process_frame
	_player = _world.get_node("Player") as CharacterBody3D
	for node: Node in _world.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_unhandled_input(false)
		if node is AnimationPlayer:
			(node as AnimationPlayer).pause()
	var driver := _world.get_node("GreyboxArena/DayNightController")
	driver.set_mode(driver.Mode.DAY)
	_player.global_position = Vector3(0, 0.1, 4)
	_player.rotation = Vector3.ZERO
	_player._pitch = 0.0
	(_player.get_node("Camera3D") as Camera3D).rotation = Vector3.ZERO
	_player._set_aiming(false)
	_player._switch_weapon(&"rifle")
	_fx = _player.get_node("PlasmaFx") as Node3D
	_inventory = _world.get_node("HUD").find_child("EC60EInventory", true, false) as Control
	_assert(_inventory != null, "production weapons_range HUD includes the independent EC60E inventory")
	if _inventory == null:
		await _finish()
		return
	_events.rpg_exploded.connect(_record_legacy)
	await _inventory_checks()
	await _model_and_pulse_checks()
	await _finish()


func _capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert(not image.is_empty() and image.get_size() == Vector2i(1920, 1080), name + " is captured from the actual 1920x1080 viewport")
	var error := image.save_png(OUTPUT_DIR.path_join(name + ".png"))
	_assert(error == OK, name + " saves original render evidence")
	return image


func _changed_pixels(first: Image, second: Image, rect: Rect2i) -> int:
	var changed := 0
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.05:
				changed += 1
	return changed


func _cyan_changes(first: Image, second: Image, rect: Rect2i) -> int:
	var changed := 0
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if b.g - a.g > 0.025 and b.b - a.b > 0.025 and b.b > b.r * 1.05 and b.g > b.r:
				changed += 1
	return changed


func _inventory_checks() -> void:
	_assert(_inventory.is_visible_in_tree() and _inventory.get("stock") == 100, "real HUD starts visible with 100 grenades")
	var bounds := _inventory.get_global_rect()
	_assert(bounds.size.x >= 250.0 and bounds.size.y >= 90.0 and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(bounds), "inventory is a fixed visible viewport region")
	_assert(is_equal_approx(bounds.position.x, 16.0) and is_equal_approx(bounds.end.y, root.size.y - 16.0), "grenade HUD occupies the bottom-left corner with 16px screen margins")
	var before := await _capture("hud_100")
	_state.ec60e_grenades = 0
	_events.emit_signal("ec60e_stock_changed", 0)
	var depleted := await _capture("hud_zero")
	_assert(_inventory.get("stock") == 0 and _inventory.is_visible_in_tree(), "depleted stock remains visibly present at zero")
	var count_rect := Rect2i(Vector2i(bounds.position + Vector2(10, 30)), Vector2i(120, 40))
	_assert(_changed_pixels(before, depleted, count_rect) > 100, "100 to zero visibly redraws the real count glyphs")
	var icon_bounds: Rect2 = _config.EC60E_HUD_ICON_RECT
	var icon_rect := Rect2i(Vector2i(bounds.position + icon_bounds.position), Vector2i(icon_bounds.size))
	_assert(_changed_pixels(before, depleted, icon_rect) == 0, "the model outline remains unchanged beside the zero count")
	_inventory.visible = false
	var hidden := await _capture("hud_zero_reference_hidden")
	var left_edge := Rect2i(Vector2i(bounds.position), Vector2i(4, int(bounds.size.y)))
	var top_blank := Rect2i(Vector2i(bounds.position + Vector2(4, 1)), Vector2i(int(bounds.size.x) - 8, 4))
	_assert(_changed_pixels(hidden, depleted, left_edge) == 0, "grenade HUD left edge draws no outer border or panel background")
	_assert(_changed_pixels(hidden, depleted, top_blank) == 0, "grenade HUD blank area is transparent against the actual range scene")
	var icon_pixels := _cyan_changes(hidden, depleted, icon_rect)
	print("EC60E_HUD_ICON cyan_pixels=", icon_pixels)
	_assert(icon_pixels > 150, "the native HUD really renders a detailed cyan model outline")
	_inventory.visible = true
	_state.ec60e_grenades = 100
	_events.emit_signal("ec60e_stock_changed", 100)
	for weapon: StringName in [&"pistol", &"smg", &"rifle", &"spas12", &"lmg", &"em120r"]:
		_player._switch_weapon(weapon)
		_assert(_inventory.is_visible_in_tree() and _inventory.get("stock") == 100 and _inventory.get_global_rect() == bounds, "%s gun switch preserves grenade count and fixed HUD placement" % weapon)
	_player._switch_weapon(&"rifle")
	var hud := _world.get_node("HUD")
	hud.range_mode = false
	hud.district_mode = true
	_assert(_inventory.is_visible_in_tree() and _inventory.get("stock") == 100, "district HUD mode retains the same always-present grenade inventory")
	hud.range_mode = true
	hud.district_mode = false
	root.size = Vector2i(1280, 720)
	await process_frame
	var resized_bounds := _inventory.get_global_rect()
	_assert(is_equal_approx(resized_bounds.position.x, 16.0) and is_equal_approx(resized_bounds.end.y, 704.0) and resized_bounds.size == bounds.size, "1280x720 preserves the bottom-left grenade HUD margins and readable size")
	root.size = Vector2i(1920, 1080)
	await process_frame


func _model_and_pulse_checks() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.pressed = true
	_player._unhandled_input(event)
	var projectiles := _world.find_children("*", "RigidBody3D", true, false)
	var projectile: RigidBody3D
	for node: Node in projectiles:
		if node.get_script() != null and node.get_script().resource_path == "res://scripts/weapons/ec60e_projectile.gd":
			projectile = node as RigidBody3D
	_assert(projectile != null and _state.ec60e_grenades == 99 and _inventory.get("stock") == 99, "actual range Player G creates the rendered grenade and updates its real HUD to 99")
	if projectile == null:
		return
	projectile.freeze = true
	projectile.set_physics_process(false)
	var model := projectile.get_node("Model") as Node3D
	_assert(model.find_children("*", "MeshInstance3D", true, false).size() > 0, "spawned projectile contains the prepared real mesh")
	var camera := _player.get_node("Camera3D") as Camera3D
	var center := camera.unproject_position(projectile.global_position)
	var model_rect := Rect2i(Vector2i(center - Vector2(140, 180)), Vector2i(280, 360))
	var visible := await _capture("grenade_spawn")
	model.visible = false
	var hidden := await _capture("grenade_spawn_reference_hidden")
	var model_pixels := _changed_pixels(hidden, visible, model_rect)
	print("EC60E_MODEL visible_pixels=", model_pixels)
	_assert(model_pixels > 100, "the production spawned GLB really contributes visible viewport pixels")
	model.visible = true
	# Stage the actual armed projectile ahead of the same Player camera to inspect the pulse.
	projectile.global_position = camera.global_position - camera.global_basis.z * 9.0
	projectile.visible = false
	var pulse_before := await _capture("pulse_reference_before")
	var audio := _world.get_node("AudioManager")
	var audio_before := _explosion_players(audio)
	projectile.call("_physics_process", 3.0)
	_assert(_legacy_explosions == 0, "EC-60E native explosion never triggers the legacy orange explosion event")
	_assert(_explosion_players(audio) == audio_before + 1, "EC-60E event plays one existing explosion audio stream")
	_fx.call("_process", 0.12)
	var pulse := await _capture("pulse_cyan")
	var pulse_pixels := _cyan_changes(pulse_before, pulse, Rect2i(100, 100, 1700, 650))
	print("EC60E_PULSE cyan_changed_pixels=", pulse_pixels)
	_assert(pulse_pixels > 500, "actual blue-cyan pulse changes visible world pixels around the exploded grenade")
	_fx.call("_process", 0.28)
	await _capture("pulse_expanded")
	_fx.call("_process", 1.0)
	var cleared := await _capture("pulse_cleared")
	var remaining_pixels := _cyan_changes(pulse_before, cleared, Rect2i(100, 100, 1700, 650))
	_assert(remaining_pixels < 50, "expired pulse removes its blue flash and wave from the native viewport")


func _explosion_players(audio: Node) -> int:
	var count := 0
	for node: Node in audio.get_children():
		if node is AudioStreamPlayer:
			var player := node as AudioStreamPlayer
			if player.stream != null and player.stream.resource_path == "res://assets/audio/explosion.mp3":
				count += 1
	return count


func _record_legacy(_position: Vector3) -> void:
	_legacy_explosions += 1


func _finish() -> void:
	if _events.is_connected("rpg_exploded", _record_legacy):
		_events.rpg_exploded.disconnect(_record_legacy)
	_world.queue_free()
	current_scene = null
	await process_frame
	await RenderingServer.frame_post_draw
	print("EC60E_RENDER COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _timeout() -> void:
	print("FAIL: EC60E_RENDER timed out before completion")
	quit(1)
