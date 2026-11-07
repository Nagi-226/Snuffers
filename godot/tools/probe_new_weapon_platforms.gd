extends SceneTree

var _scene: Node3D
var _failures := 0


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


func _aim(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	_scene.get_node("Player")._unhandled_input(event)


func _run() -> void:
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	for frame in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots/new_weapons")
	for entry in [[KEY_2, &"smg"], [KEY_5, &"lmg"], [KEY_1, &"magnum"]]:
		_key(entry[0])
		if entry[1] == &"magnum":
			_key(entry[0])
		await create_timer(0.2).timeout
		_check(root.get_node("GameState").current_weapon == entry[1], "real selection " + entry[1])
		await _shot(entry[1] + "_hip")
		_aim(true)
		await create_timer(0.45).timeout
		var player := _scene.get_node("Player")
		var camera := player.get_node("Camera3D") as Camera3D
		var target := _scene.get_node("RangeFacilities/Targets/CloseTarget") as Node3D
		camera.look_at(target.global_position + Vector3(0, 1, 0))
		await _shot(entry[1] + "_ads")
		if entry[1] == &"magnum":
			var magnum = player.get_node("Camera3D/WeaponMount/Magnum")
			root.get_node("GameState").magnum_mag = 4
			magnum._start_reload()
			await _shot("magnum_ads_reload_start")
			for phase in [0.5, 1.0, 1.5]:
				await create_timer(0.5).timeout
				await _shot("magnum_ads_reload_%03dms" % int(phase * 1000))
			await create_timer(0.25).timeout
			for weapon_name in ["Pistol", "Magnum"]:
				var weapon = player.get_node("Camera3D/WeaponMount/" + weapon_name) as Node3D
				var arms = weapon.get_node("ViewModel/ArmsEM57P") as Node3D
				print("MAGNUM_ADS_VISIBILITY ", weapon_name, " weapon=", weapon.is_visible_in_tree(), " arms=", arms.is_visible_in_tree())
		_aim(false)
		await create_timer(0.2).timeout
	print("NEW_WEAPON_PROBE failures=", _failures)
	_scene.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _shot(label: String) -> void:
	for frame in 8:
		await process_frame
	root.get_texture().get_image().save_png("tmp_shots/new_weapons/%s.png" % label)
	print("NEW_WEAPON_SHOT ", label)
