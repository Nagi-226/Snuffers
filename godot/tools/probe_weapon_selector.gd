extends SceneTree

var _scene: Node3D
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		_failures += 1


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	_scene.get_node("Player")._unhandled_input(event)
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	_scene.get_node("Player")._unhandled_input(release)


func _wheel() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	_scene.get_node("Player")._unhandled_input(event)


func _run() -> void:
	var out_dir := "tmp_shots/weapon_selector"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_scene = (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	for frame in 30:
		await process_frame
	var state = root.get_node("GameState")
	state.weapon_unlocked[&"dmr"] = true
	state.weapon_unlocked[&"shotgun"] = true
	_key(KEY_1)
	_key(KEY_3)
	await create_timer(0.05).timeout
	_check(state.current_weapon == &"rifle", "real number 3 enters rifle")
	_key(KEY_3)
	await create_timer(0.05).timeout
	_check(state.current_weapon == &"dmr", "real number 3 repeats into DMR")
	await _shot(out_dir + "/weapon_selector_dmr.png")
	_wheel()
	await create_timer(0.05).timeout
	_check(state.current_weapon == &"shotgun", "real wheel selects shotgun")
	await _shot(out_dir + "/weapon_selector_shotgun.png")
	_wheel()
	await create_timer(0.05).timeout
	_check(state.current_weapon == &"pistol", "real wheel wraps to pistol")
	_key(KEY_2)
	await create_timer(0.05).timeout
	_check(state.current_weapon == &"pistol" and _scene.get_node("HUD/WeaponSelector").get_meta("category") == 2, "real reserved category does not switch weapon")
	await _shot(out_dir + "/weapon_selector_reserved.png")
	print("WEAPON_SELECTOR_PROBE failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _shot(path: String) -> void:
	for frame in 8:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("WEAPON_SELECTOR_SHOT ", path)
