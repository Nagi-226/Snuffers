extends SceneTree

var _failures := 0
var _assertions := 0
var _scene: Node3D
var _player: CharacterBody3D
var _state: Node
var _ammo


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(45.0).timeout.connect(_timeout)
	_state = root.get_node("GameState")
	_state.reset()
	_scene = (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	for enemy in get_nodes_in_group(&"enemy"):
		enemy.set_physics_process(false)
	_ammo = _scene.get_node("HUD")._weapon_ammo
	for frame in 5:
		await physics_frame
	var available := {}
	for pickup in get_nodes_in_group(&"pickup"):
		var kind: Variant = pickup.get("kind")
		if kind in [&"battery", &"pistol_ammo", &"grenade"]:
			pickup.set_process(false)
			if not available.has(kind):
				available[kind] = []
			available[kind].append(pickup)
	_assert(available.has(&"battery") and available[&"battery"].size() == 2, "first street has both existing EC-68 pickups")
	_assert(available.has(&"pistol_ammo") and available[&"pistol_ammo"].size() == 2, "first street has both existing EC-57 pickups")
	_assert(available.has(&"grenade") and available[&"grenade"].size() == 1, "first street has its existing EC-40 pickup")
	for kind in [&"battery", &"pistol_ammo", &"grenade"]:
		if not available.has(kind):
			continue
		var amount := 20 if kind == &"grenade" else 300
		var field := _reserve_field(kind)
		var weapon := &"pistol" if kind == &"pistol_ammo" else &"rifle"
		_player.call("_switch_weapon", weapon)
		_state.set(field, 100)
		var pickup: Area3D = available[kind][0]
		var entries := [0]
		pickup.body_entered.connect(func(body: Node3D) -> void:
			entries[0] += 1
			pickup.call("_on_body_entered", body))
		await _enter(pickup)
		_assert(entries[0] == 1, "%s is collected by a real physics body_entered event" % kind)
		_assert(_state.get(field) == 100 + amount, "%s adds the requested %d rounds in the actual street" % [kind, amount])
		_assert(_ammo.grenade_stock == 120 if kind == &"grenade" else _ammo.reserve == 400, "%s updates the equipped weapon HUD immediately" % kind)
		await _move_player(Vector3(0, 1, 120))
		_assert(_state.get(field) == 100 + amount, "%s rejects duplicate callbacks before deletion and settles once" % kind)

	for kind in [&"battery", &"pistol_ammo"]:
		var field := _reserve_field(kind)
		var maximum: int = root.get_node("GameConfig").RIFLE_RESERVE_MAX if kind == &"battery" else root.get_node("GameConfig").PISTOL_RESERVE_MAX
		_state.set(field, maximum - 10)
		var capped := _new_pickup(kind)
		await _enter(capped)
		_assert(_state.get(field) == maximum, "%s clamps the partial package to the carrying limit" % kind)
		await _move_player(Vector3(0, 1, 120))
		var full := _new_pickup(kind)
		await _enter(full)
		_assert(is_instance_valid(full) and not full.get("_collected") and _state.get(field) == maximum, "%s remains collectible while its shared pool is full" % kind)
		_state.set(field, maximum - 300)
		await _move_player(Vector3(0, 1, 120))
		await _enter(full)
		_assert(_state.get(field) == maximum, "%s can be collected later after reserve is spent" % kind)
		await _move_player(Vector3(0, 1, 120))

	_state.rifle_grenades = 2000
	var extra := _new_pickup(&"grenade")
	await _enter(extra)
	_assert(_state.rifle_grenades == 2020, "EC-40 retains the existing uncapped shared pool")
	await _move_player(Vector3(0, 1, 120))
	for weapon in [&"rifle", &"dmr", &"lmg", &"pistol", &"smg", &"em57s2"]:
		_state.weapon_unlocked[weapon] = true
		_player.call("_switch_weapon", weapon)
		var field := "pistol_reserve" if weapon in [&"pistol", &"smg", &"em57s2"] else "rifle_reserve"
		_assert(_ammo.reserve == _state.get(field), "%s displays its current shared reserve after switching" % weapon)
	if OS.get_cmdline_user_args().has("--equipped-hud"):
		await _check_equipped_pools()
	await _finish()


func _check_equipped_pools() -> void:
	for weapon in [&"rifle", &"dmr", &"lmg", &"pistol", &"smg", &"em57s2"]:
		var kind := &"pistol_ammo" if weapon in [&"pistol", &"smg", &"em57s2"] else &"battery"
		var field := _reserve_field(kind)
		_state.set(field, 100)
		_state.weapon_unlocked[weapon] = true
		_player.call("_switch_weapon", weapon)
		_assert(_ammo.reserve == 100, "%s HUD starts with the controlled reserve" % weapon)
		await _enter(_new_pickup(kind))
		_assert(_state.get(field) == 400 and _ammo.reserve == 400, "%s currently equipped HUD updates on its shared ammo pickup" % weapon)
		await _move_player(Vector3(0, 1, 120))
	for weapon in [&"rifle", &"smg", &"em86b", &"em40t1"]:
		_state.rifle_grenades = 100
		_state.weapon_unlocked[weapon] = true
		_player.call("_switch_weapon", weapon)
		_assert(_ammo.reserve == 100 if weapon == &"em40t1" else _ammo.grenade_stock == 100, "%s HUD starts with the controlled EC-40 pool" % weapon)
		await _enter(_new_pickup(&"grenade"))
		_assert(_state.rifle_grenades == 120, "%s EC-40 pickup updates the shared state" % weapon)
		_assert(_ammo.reserve == 120 if weapon == &"em40t1" else _ammo.grenade_stock == 120, "%s currently equipped HUD updates on an EC-40 pickup" % weapon)
		await _move_player(Vector3(0, 1, 120))


func _reserve_field(kind: StringName) -> String:
	if kind == &"grenade":
		return "rifle_grenades"
	return "pistol_reserve" if kind == &"pistol_ammo" else "rifle_reserve"


func _new_pickup(kind: StringName) -> Area3D:
	var pickup := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate() as Area3D
	pickup.set("kind", kind)
	pickup.position = Vector3(0, 1, 130)
	_scene.add_child(pickup)
	pickup.set_process(false)
	return pickup


func _enter(pickup: Area3D) -> void:
	await _move_player(pickup.global_position - Vector3(0, 0.9, 0))


func _move_player(destination: Vector3) -> void:
	_player.global_position = destination
	_state.player_position = destination
	for frame in 4:
		await physics_frame
	await process_frame


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _timeout() -> void:
	push_error("street ammo test timed out")
	quit(1)


func _finish() -> void:
	_scene.queue_free()
	await process_frame
	print("STREET_AMMO assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
