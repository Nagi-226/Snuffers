extends SceneTree

var _failures: int = 0
var _player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	_player._unhandled_input(event)


func _wheel(button: MouseButton) -> void:
	if DisplayServer.get_name() == "headless":
		_player._cycle_unlocked_weapon(-1 if button == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	_player._unhandled_input(event)


func _run() -> void:
	var state = root.get_node("GameState")
	state.reset()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(_player)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame
	state.weapon_unlocked[&"dmr"] = true
	state.weapon_unlocked[&"shotgun"] = true
	_press(KEY_1)
	_assert(state.current_weapon == &"pistol", "number 1 selects pistol")
	_assert(hud.get_node("WeaponSelector").visible, "number selection shows the weapon HUD")
	_press(KEY_2)
	_assert(state.current_weapon == &"pistol", "reserved SMG cannot replace the current weapon")
	_assert(hud.get_node("WeaponSelector").get_meta("category") == 2, "number 2 highlights the SMG category")
	_press(KEY_3)
	_assert(state.current_weapon == &"rifle", "number 3 enters EM-68A first")
	_press(KEY_3)
	_assert(state.current_weapon == &"dmr", "number 3 repeats into unlocked EM-68D")
	_press(KEY_3)
	_assert(state.current_weapon == &"rifle", "number 3 cycles back to EM-68A")
	_press(KEY_4)
	_assert(state.current_weapon == &"shotgun", "number 4 selects shotgun")
	_press(KEY_4)
	_assert(state.current_weapon == &"shotgun", "reserved sniper does not create a phantom switch")
	_press(KEY_5)
	_press(KEY_6)
	_assert(state.current_weapon == &"shotgun", "reserved machine gun and heavy weapons stay locked")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_assert(state.current_weapon == &"pistol", "wheel down wraps to the first unlocked weapon")
	_assert(hud.get_node("WeaponSelector").get_meta("category") == 1, "wheel selection highlights the correct category")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_assert(state.current_weapon == &"shotgun", "wheel up returns to the previous unlocked weapon")
	_assert(hud._heli_timer_label.offset_top >= 132.0, "helicopter timer moves below the visible weapon selector")
	hud._selector_time_left = 0.01
	await create_timer(0.1).timeout
	_assert(not hud.get_node("WeaponSelector").visible, "weapon HUD hides after its hold time")
	_assert(is_equal_approx(hud._heli_timer_label.offset_top, 48.0), "helicopter timer returns after the weapon selector hides")
	state.reset()
	_press(KEY_3)
	_press(KEY_3)
	_assert(state.current_weapon == &"rifle", "locked DMR cannot enter the number 3 cycle")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_assert(state.current_weapon == &"pistol", "wheel skips locked DMR and shotgun")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_assert(state.current_weapon == &"rifle", "wheel wraps over unlocked weapons only")
	_player.queue_free()
	hud.queue_free()
	await process_frame
	print("test_weapon_selection: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
