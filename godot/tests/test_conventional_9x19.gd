## G17 / MPX playable integration: real inputs, damage, shared ammunition and reloads.
extends SceneTree

const WEAPONS := [
	[&"g17", "G17", "res://scenes/weapons/g17.tscn", 17],
	[&"mpx", "MPX", "res://scenes/weapons/mpx.tscn", 30],
]

var _assertions := 0
var _failures := 0
var _player
var _hud
var _state
var _events
var _scene: Node3D
var _shot_times: Dictionary = {}
var _shot_frames: Dictionary = {}
var _reload_counts: Dictionary = {&"g17": 0, &"mpx": 0}


class DamageTarget extends StaticBody3D:
	var amounts: Array[float] = []
	var headshots: Array[bool] = []

	func take_damage(amount: float, head: bool) -> void:
		amounts.append(amount)
		headshots.append(head)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	create_timer(75.0).timeout.connect(func() -> void:
		push_error("conventional 9x19 integration timed out")
		quit(1))
	_state.reset()
	for item: Array in WEAPONS:
		_assert(ResourceLoader.exists(item[2]), "%s has a playable weapon scene" % item[0])
		_assert(ResourceLoader.exists("res://scenes/weapons/%s.tres" % item[0]), "%s has its own WeaponData resource" % item[0])
		_assert(_has_property(_state, String(item[0]) + "_mag"), "%s has its own magazine state" % item[0])
		_assert(_state.weapon_unlocked.has(item[0]), "%s participates in explicit weapon unlocking" % item[0])
		_assert(_state.fire_modes.has(item[0]), "%s has an explicit default firing mode" % item[0])
	_assert(_has_property(_state, "ammo_9x19_reserve"), "conventional weapons have a separate shared 9x19 reserve")
	if _failures > 0:
		_finish()
		return
	_assert(_state.g17_mag == 17 and _state.mpx_mag == 30, "restart initializes the standard 17/30-round magazines")
	_assert(_state.ammo_9x19_reserve == 150, "restart initializes one shared 150-round 9x19 reserve")
	_assert(not _state.weapon_unlocked[&"g17"] and not _state.weapon_unlocked[&"mpx"], "campaign restart keeps the additional weapons locked")
	_assert(_state.fire_modes[&"g17"] == &"semi" and _state.fire_modes[&"mpx"] == &"auto", "restart selects the approved firing modes")
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	await physics_frame
	_player = _scene.get_node("Player")
	_hud = _scene.get_node("HUD")
	# Keep the fixture at the authored range position; weapon physics and visuals remain live.
	_player.set_physics_process(false)
	_events.weapon_fired.connect(_on_weapon_fired)
	_events.weapon_reloaded.connect(_on_weapon_reloaded)
	_assert(_state.weapon_unlocked[&"g17"] and _state.weapon_unlocked[&"mpx"], "the actual range unlocks both conventional weapons")
	for item: Array in WEAPONS:
		var path := "Camera3D/WeaponMount/" + String(item[1])
		_assert(_player.has_node(path), "%s is mounted in the real Player scene" % item[0])
	if _failures > 0:
		await _cleanup()
		_finish()
		return
	if "--auto-reload-only" in OS.get_cmdline_user_args():
		await _check_mpx_auto_reload()
		await _cleanup()
		_finish()
		return
	await _check_selection()
	await _check_g17_trigger()
	await _check_mpx_trigger()
	await _check_mpx_auto_reload()
	await _check_damage()
	await _check_reload()
	await _check_scene_persistence()
	await _cleanup()
	_finish()


func _weapon(id: StringName):
	return _player.get_node("Camera3D/WeaponMount/" + ("G17" if id == &"g17" else "MPX"))


func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	_player._unhandled_input(event)


func _trigger(weapon, pressed: bool) -> void:
	if DisplayServer.get_name() == "headless":
		weapon._trigger_held = pressed
		if pressed:
			weapon._on_trigger_pressed()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	weapon._unhandled_input(event)


func _reload(weapon) -> void:
	if DisplayServer.get_name() == "headless":
		weapon._start_reload()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.physical_keycode = KEY_R
	event.pressed = true
	weapon._unhandled_input(event)


func _reset_shots(id: StringName) -> void:
	_shot_times[id] = []
	_shot_frames[id] = []


func _on_weapon_fired(id: StringName) -> void:
	if id not in [&"g17", &"mpx"]:
		return
	if not _shot_times.has(id):
		_reset_shots(id)
	_shot_times[id].append(Time.get_ticks_usec())
	_shot_frames[id].append(Engine.get_physics_frames())


func _on_weapon_reloaded(id: StringName) -> void:
	if _reload_counts.has(id):
		_reload_counts[id] += 1


func _check_selection() -> void:
	_player._switch_weapon(&"g17")
	_assert(_state.current_weapon == &"g17" and _weapon(&"g17").visible and not _weapon(&"mpx").visible, "G17 switching shows only the selected conventional weapon")
	_assert(_hud._weapon_ammo.weapon_id == &"g17" and _hud._weapon_ammo.mag == 17 and _hud._weapon_ammo.reserve == 150, "G17 HUD uses its own magazine and the shared reserve")
	_assert("9" in _hud._weapon_ammo.ammo_type and "19" in _hud._weapon_ammo.ammo_type and not _hud._weapon_ammo.show_grenades, "G17 HUD identifies 9x19 ammunition without grenade stock")
	_press_key(KEY_X)
	_assert(_state.fire_modes[&"g17"] == &"semi", "G17 remains semi automatic when X is pressed")
	_player._switch_weapon(&"mpx")
	var modes: Array[StringName] = []
	for press in 3:
		_press_key(KEY_X)
		modes.append(_state.fire_modes[&"mpx"])
	_assert(modes.has(&"auto") and modes.has(&"burst") and modes.has(&"semi") and not modes.has(&"grenade"), "MPX X cycles precisely auto, burst and semi")
	_assert(_hud._weapon_ammo.weapon_id == &"mpx" and _hud._weapon_ammo.mag == 30 and _hud._weapon_ammo.reserve == 150, "MPX HUD uses its own magazine and the same 9x19 reserve")
	_assert("9" in _hud._weapon_ammo.ammo_type and "19" in _hud._weapon_ammo.ammo_type and not _hud._weapon_ammo.show_grenades, "MPX HUD identifies conventional ammunition without grenade stock")
	_player._cycle_unlocked_weapon(1)
	var visited: Array[StringName] = [_state.current_weapon]
	for step in 25:
		_player._cycle_unlocked_weapon(1)
		visited.append(_state.current_weapon)
	_assert(visited.has(&"g17") and visited.has(&"mpx"), "the real Player scroll cycle includes both additional weapons")


func _check_g17_trigger() -> void:
	_player._switch_weapon(&"g17")
	var weapon = _weapon(&"g17")
	_state.g17_mag = 17
	_state.ammo_9x19_reserve = 150
	var ec57_before: int = _state.pistol_reserve
	var mpx_before: int = _state.mpx_mag
	weapon._fire_cooldown = 0.0
	_reset_shots(&"g17")
	_trigger(weapon, true)
	await create_timer(0.45).timeout
	_trigger(weapon, false)
	_assert(_shot_times[&"g17"].size() == 1 and _state.g17_mag == 16, "holding the G17 trigger produces exactly one round")
	_assert(_state.mpx_mag == mpx_before and _state.pistol_reserve == ec57_before and _state.ammo_9x19_reserve == 150, "G17 firing consumes its magazine without touching MPX, EC57 or reserve")
	weapon._fire_cooldown = 0.0
	_trigger(weapon, true)
	_trigger(weapon, false)
	_trigger(weapon, true)
	_trigger(weapon, false)
	_assert(_shot_times[&"g17"].size() == 2, "G17 blocks a second immediate press during its semi automatic cooldown")
	await create_timer(0.18).timeout
	_trigger(weapon, true)
	_trigger(weapon, false)
	_assert(_shot_times[&"g17"].size() == 3, "G17 allows another deliberate press after the 400 RPM input cooldown")
	_assert(is_equal_approx(weapon.weapon_data.semi_fire_interval, 0.15), "G17 declares the approved 400 RPM input ceiling")
	_assert(_hud._weapon_ammo.mag == _state.g17_mag and _hud._weapon_ammo.reserve == 150, "G17 HUD follows actual trigger ammunition changes")


func _check_mpx_trigger() -> void:
	_player._switch_weapon(&"mpx")
	var weapon = _weapon(&"mpx")
	_state.mpx_mag = 30
	_state.ammo_9x19_reserve = 0
	_state.fire_modes[&"mpx"] = &"auto"
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	_trigger(weapon, true)
	await create_timer(2.8).timeout
	_trigger(weapon, false)
	var frames: Array = _shot_frames[&"mpx"]
	_assert(frames.size() == 30 and _state.mpx_mag == 0, "MPX held automatic trigger fires exactly its real 30-round magazine")
	if frames.size() == 30:
		var seconds := float(frames[-1] - frames[0]) / float(Engine.physics_ticks_per_second)
		var rpm := 60.0 * 29.0 / seconds
		var wall_seconds := float(_shot_times[&"mpx"][-1] - _shot_times[&"mpx"][0]) / 1000000.0
		print("MPX_ACTUAL_CADENCE rounds=30 physics_seconds=", seconds, " rpm=", rpm, " wall_seconds=", wall_seconds)
		_assert(absf(rpm - 850.0) <= 850.0 * 0.025, "MPX measures 850 RPM within one-frame sampling tolerance instead of 720 RPM")
	_assert(not weapon._is_reloading, "empty MPX with no reserve cannot invent a reload")
	await _check_burst(weapon)
	_state.fire_modes[&"mpx"] = &"semi"
	_state.mpx_mag = 30
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	_trigger(weapon, true)
	await create_timer(0.4).timeout
	_trigger(weapon, false)
	_assert(_shot_times[&"mpx"].size() == 1 and _state.mpx_mag == 29, "MPX semi automatic mode produces one round per trigger press")
	_state.fire_modes[&"mpx"] = &"burst"
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	_trigger(weapon, true)
	_trigger(weapon, false)
	await physics_frame
	_player._switch_weapon(&"g17")
	var count_after_switch: int = _shot_times[&"mpx"].size()
	await create_timer(0.2).timeout
	_player._switch_weapon(&"mpx")
	await create_timer(0.4).timeout
	_assert(_shot_times[&"mpx"].size() == count_after_switch, "switching away cancels an incomplete burst without ghost continuation on return")


func _check_burst(weapon) -> void:
	_state.fire_modes[&"mpx"] = &"burst"
	_state.mpx_mag = 30
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	_trigger(weapon, true)
	await create_timer(0.4).timeout
	_trigger(weapon, false)
	_assert(_shot_times[&"mpx"].size() == 3 and _state.mpx_mag == 27, "holding MPX burst trigger stops after exactly three rounds")
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	_trigger(weapon, true)
	_trigger(weapon, false)
	await physics_frame
	_trigger(weapon, true)
	_trigger(weapon, false)
	await create_timer(0.4).timeout
	_assert(_shot_times[&"mpx"].size() == 3 and _state.mpx_mag == 24, "repressing during the active burst cannot reset or extend its three-round budget")
	_state.mpx_mag = 2
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	_trigger(weapon, true)
	_trigger(weapon, false)
	await create_timer(0.35).timeout
	_assert(_shot_times[&"mpx"].size() == 2 and _state.mpx_mag == 0, "a two-round MPX magazine ends the burst without negative ammunition")


func _check_mpx_auto_reload() -> void:
	_player._switch_weapon(&"mpx")
	var weapon = _weapon(&"mpx")
	_state.fire_modes[&"mpx"] = &"auto"
	_state.mpx_mag = 30
	_state.ammo_9x19_reserve = 30
	var ec57_before: int = _state.pistol_reserve
	var reload_before: int = _reload_counts[&"mpx"]
	weapon._fire_cooldown = 0.0
	_reset_shots(&"mpx")
	# One press remains held through the entire real automatic reload; never synthesize another press.
	_trigger(weapon, true)
	await create_timer(2.35).timeout
	_assert(_shot_times[&"mpx"].size() == 30 and _state.mpx_mag == 0 and weapon._is_reloading, "a held MPX trigger empties thirty rounds and enters automatic reload")
	_assert(_state.ammo_9x19_reserve == 30, "MPX automatic reload defers shared reserve settlement until the real timer completes")
	await create_timer(float(weapon.weapon_data.reload_time) + 0.2).timeout
	var count: int = _shot_times[&"mpx"].size()
	_assert(_reload_counts[&"mpx"] == reload_before + 1 and _state.ammo_9x19_reserve == 0, "the actual MPX automatic reload completes exactly once using the shared thirty spare rounds")
	_assert(count > 30 and _state.mpx_mag < 30, "the continuously held MPX trigger resumes with round thirty-one after automatic reload")
	_assert(count + _state.mpx_mag + _state.ammo_9x19_reserve == 60 and _state.pistol_reserve == ec57_before, "MPX cross-reload automatic fire conserves all sixty 9x19 rounds and preserves EC57")
	if count > 30:
		var pause := float(_shot_times[&"mpx"][30] - _shot_times[&"mpx"][29]) / 1000000.0
		print("MPX_AUTO_RELOAD first_mag=30 total_shots=", count, " reload_gap_seconds=", pause, " magazine=", _state.mpx_mag)
		_assert(pause >= float(weapon.weapon_data.reload_time) and pause <= float(weapon.weapon_data.reload_time) + 0.25, "MPX resumes immediately after the real reload duration without firing through the reload")
	_trigger(weapon, false)
	await create_timer(0.2).timeout
	_assert(_shot_times[&"mpx"].size() == count, "releasing the MPX trigger after automatic reload stops further shots")


func _check_damage() -> void:
	var target := DamageTarget.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	shape.shape = box
	target.add_child(shape)
	root.add_child(target)
	for item: Array in WEAPONS:
		var id: StringName = item[0]
		_player._switch_weapon(id)
		var weapon = _weapon(id)
		_state.fire_modes[id] = &"semi"
		_state.set(String(id) + "_mag", 10)
		target.global_position = weapon.global_position - weapon.global_basis.z * 1.5
		await physics_frame
		await physics_frame
		for sample: Array in [[false, false, 30.0], [true, false, 30.0], [false, true, 60.0]]:
			if bool(sample[0]):
				target.add_to_group(&"sniper")
			else:
				target.remove_from_group(&"sniper")
			target.set_meta(&"hit_part", &"head" if bool(sample[1]) else &"body")
			var before := target.amounts.size()
			weapon._fire_cooldown = 0.0
			_trigger(weapon, true)
			_trigger(weapon, false)
			_assert(target.amounts.size() == before + 1, "%s actual ray reaches the physical %s target" % [id, "sniper" if bool(sample[0]) else "body"])
			if target.amounts.size() == before + 1:
				_assert(is_equal_approx(target.amounts[-1], float(sample[2])) and target.headshots[-1] == bool(sample[1]), "%s actual %s hit deals %s damage" % [id, "head" if bool(sample[1]) else "body", sample[2]])
		_assert(is_equal_approx(weapon.weapon_data.damage_body, 30.0) and is_equal_approx(weapon.weapon_data.headshot_factor, 2.0), "%s synchronizes the approved per-round damage and head multiplier" % id)
	target.queue_free()
	await process_frame


func _check_reload() -> void:
	var ec57_before: int = _state.pistol_reserve
	_state.g17_mag = 5
	_state.mpx_mag = 8
	_state.ammo_9x19_reserve = 100
	for item: Array in WEAPONS:
		var id: StringName = item[0]
		_player._switch_weapon(id)
		_state.fire_modes[id] = &"semi"
		# Each full-magazine case owns a sufficient reserve; earlier cancellation cases leave only twenty.
		_state.ammo_9x19_reserve = 100
		var weapon = _weapon(id)
		var property := String(id) + "_mag"
		var before: int = _state.get(property)
		var reserve_before: int = _state.ammo_9x19_reserve
		var other_before: int = _state.mpx_mag if id == &"g17" else _state.g17_mag
		var reload_before: int = _reload_counts[id]
		_reload(weapon)
		_reload(weapon)
		_assert(weapon._is_reloading, "%s R enters a real timed reload" % id)
		_assert(_state.get(property) == before and _state.ammo_9x19_reserve == reserve_before, "%s reload defers all ammunition settlement until completion" % id)
		var rounds_before: int = _state.g17_mag + _state.mpx_mag + _state.ammo_9x19_reserve
		weapon._fire_cooldown = 0.0
		_trigger(weapon, true)
		_trigger(weapon, false)
		_assert(_state.get(property) == before, "%s cannot fire while reloading" % id)
		await create_timer(float(weapon.weapon_data.reload_time) + 0.1).timeout
		_assert(_reload_counts[id] == reload_before + 1 and not weapon._is_reloading, "%s repeated R requests settle exactly once" % id)
		_assert(_state.get(property) == int(item[3]) and _state.ammo_9x19_reserve == reserve_before - (int(item[3]) - before), "%s fills its magazine from the one shared 9x19 reserve" % id)
		_assert((_state.mpx_mag if id == &"g17" else _state.g17_mag) == other_before and _state.g17_mag + _state.mpx_mag + _state.ammo_9x19_reserve == rounds_before, "%s reload preserves the other magazine and total round conservation" % id)
		_assert(_hud._weapon_ammo.mag == _state.get(property) and _hud._weapon_ammo.reserve == _state.ammo_9x19_reserve, "%s actual completed reload updates the HUD" % id)
		_assert(weapon._magazine != null and weapon._magazine.visible and weapon._magazine.global_transform.origin.is_finite(), "%s has its real magazine restored after reload" % id)
		_state.set(property, 0)
		_state.ammo_9x19_reserve = 3
		_reload(weapon)
		await create_timer(float(weapon.weapon_data.reload_time) + 0.1).timeout
		_assert(_state.get(property) == 3 and _state.ammo_9x19_reserve == 0, "%s empty reload uses only the three available spare rounds" % id)
		_state.set(property, 2)
		_state.ammo_9x19_reserve = 20
		_reload(weapon)
		await create_timer(0.15).timeout
		_player._switch_weapon(&"mpx" if id == &"g17" else &"g17")
		_assert(not weapon._is_reloading and weapon._magazine != null and weapon._magazine.visible, "%s switching cancels reload and restores its real magazine" % id)
		await create_timer(float(weapon.weapon_data.reload_time) + 0.1).timeout
		_assert(_state.get(property) == 2 and _state.ammo_9x19_reserve == 20, "%s cancelled timer cannot settle ammunition later" % id)
	_assert(_state.pistol_reserve == ec57_before, "all conventional reloads preserve the independent EC57 reserve")


func _check_scene_persistence() -> void:
	_state.g17_mag = 7
	_state.mpx_mag = 11
	_state.ammo_9x19_reserve = 43
	_state.fire_modes[&"mpx"] = &"burst"
	_events.weapon_fired.disconnect(_on_weapon_fired)
	_events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	_scene.queue_free()
	_scene = null
	current_scene = null
	await process_frame
	await create_timer(0.08).timeout
	await process_frame
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	_player = _scene.get_node("Player")
	_hud = _scene.get_node("HUD")
	_assert(_state.g17_mag == 7 and _state.mpx_mag == 11 and _state.ammo_9x19_reserve == 43 and _state.fire_modes[&"mpx"] == &"burst", "replacing a real playable scene preserves autoload magazines, shared reserve and selected mode")
	_player._switch_weapon(&"mpx")
	_assert(_hud._weapon_ammo.mag == 11 and _hud._weapon_ammo.reserve == 43 and "点射" in _hud._weapon_ammo.mode_tag, "the replacement scene HUD restores retained MPX ammunition and firing mode")
	_state.reset()
	_assert(_state.g17_mag == 17 and _state.mpx_mag == 30 and _state.ammo_9x19_reserve == 150, "explicit new-game restart restores the approved conventional loadout")
	_assert(not _state.weapon_unlocked[&"g17"] and not _state.weapon_unlocked[&"mpx"], "explicit new-game restart restores campaign lock state")


func _cleanup() -> void:
	if _events.weapon_fired.is_connected(_on_weapon_fired):
		_events.weapon_fired.disconnect(_on_weapon_fired)
	if _events.weapon_reloaded.is_connected(_on_weapon_reloaded):
		_events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	if is_instance_valid(_scene):
		_scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.08).timeout
	await process_frame


func _has_property(object: Object, property: String) -> bool:
	for field: Dictionary in object.get_property_list():
		if field.name == property:
			return true
	return false


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("CONVENTIONAL_9X19 assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
