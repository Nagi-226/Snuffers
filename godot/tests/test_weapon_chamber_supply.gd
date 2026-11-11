## Real 18-gun firing/reload supply; magazine fields keep container-only semantics.
## A copied reload_time shortens ordinary timer waits; production pump timing is retained.
extends SceneTree

const IDS := [&"rifle", &"pistol", &"g17", &"dmr", &"shotgun", &"spas12", &"smg", &"mpx", &"em57s2", &"lmg", &"magnum", &"em86s", &"em86b", &"em86d", &"em86m", &"em127g", &"em127m", &"em12g2"]
const RESERVES := {
	&"rifle": &"rifle_reserve", &"dmr": &"rifle_reserve", &"lmg": &"rifle_reserve",
	&"pistol": &"pistol_reserve", &"smg": &"pistol_reserve", &"em57s2": &"pistol_reserve",
	&"g17": &"ammo_9x19_reserve", &"mpx": &"ammo_9x19_reserve",
	&"shotgun": &"shotgun_reserve", &"em12g2": &"shotgun_reserve",
	&"spas12": &"spas12_reserve", &"magnum": &"magnum_reserve",
	&"em127g": &"magnum_reserve", &"em127m": &"magnum_reserve",
	&"em86s": &"em86_reserve", &"em86b": &"em86_reserve", &"em86d": &"em86_reserve", &"em86m": &"em86_reserve",
}
const ORIGIN := Vector3(0, 100, 0)
const OUTPUT := "res://tmp_shots/weapon_chamber_supply"

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player
var _target
var _state
var _events
var _config
var _weapons: Dictionary = {}
var _fired: Array[StringName] = []
var _reload_started: Array[StringName] = []
var _reload_done: Array[StringName] = []
var _ammo: Array[Dictionary] = []
var _evidence: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("weapon chamber supply timed out")
		quit(1))
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state.reset()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_create_player()
	_create_target()
	_events.weapon_fired.connect(_on_fired)
	_events.weapon_reload_started.connect(_on_reload_started)
	_events.weapon_reloaded.connect(_on_reload_done)
	_events.ammo_changed.connect(_on_ammo)
	await physics_frame
	await physics_frame
	await process_frame
	_assert(_config.CHAMBER_WEAPON_IDS == IDS and _state.weapon_chambered.size() == 18, "frozen chamber contract covers all 18 guns exactly")
	for id: StringName in IDS:
		await _check_gun(id)
	await _check_shared_pools()
	await _check_trigger_sequences()
	await _check_spas_pump_reload_edges()
	await _check_scene_and_reset()
	_events.weapon_fired.disconnect(_on_fired)
	_events.weapon_reload_started.disconnect(_on_reload_started)
	_events.weapon_reloaded.disconnect(_on_reload_done)
	_events.ammo_changed.disconnect(_on_ammo)
	_assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "chamber evidence directory opens")
	var file := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(file != null, "chamber report opens")
	if file != null:
		file.store_string(JSON.stringify({"assertions": _assertions, "failures": _failures, "evidence": _evidence}, "\t"))
		file.close()
	_world.queue_free()
	current_scene = null
	await process_frame
	print("WEAPON_CHAMBER_SUPPLY COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _create_player() -> void:
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)
	_player.global_position = ORIGIN
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_weapons.clear()
	for weapon in _player.get_node("Camera3D/WeaponMount").get_children():
		weapon.set_process(false)
		weapon.set_physics_process(false)
		weapon.set_process_unhandled_input(false)
		_weapons[weapon.weapon_data.weapon_id] = weapon
		weapon.weapon_data = weapon.weapon_data.duplicate()
		weapon.weapon_data.spread_hip = 0.0
		weapon.weapon_data.spread_aim = 0.0
		weapon.weapon_data.spread_prone = 0.0
		if weapon.weapon_data.weapon_id != &"spas12":
			weapon.weapon_data.reload_time = 0.05
	for id: StringName in IDS:
		_state.weapon_unlocked[id] = true


func _create_target() -> void:
	_target = load("res://scripts/levels/range_target.gd").new()
	_target.target_health = 1.0e9
	var eye := Marker3D.new()
	eye.name = "Eye"
	_target.add_child(eye)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 6, 0.4)
	collision.shape = shape
	_target.add_child(collision)
	_world.add_child(_target)
	_target.global_position = ORIGIN + Vector3(0, 0, -8)
	_target.set_process(false)
	_target.set_physics_process(false)


func _select(id: StringName):
	_player._switch_weapon(&"pistol" if id != &"pistol" else &"rifle")
	_player._switch_weapon(id)
	var weapon = _weapons[id]
	weapon.global_transform = Transform3D(Basis.IDENTITY, ORIGIN)
	weapon._trigger_held = false
	weapon._burst_left = 0
	weapon._fire_cooldown = 0.0
	_state.fire_modes[id] = &"semi"
	_fired.clear()
	_reload_started.clear()
	_reload_done.clear()
	_ammo.clear()
	return weapon


func _set_supply(id: StringName, mag: int, chamber: bool, reserve: int) -> void:
	_state.set(String(id) + "_mag", mag)
	_state.weapon_chambered[id] = chamber
	_state.set(RESERVES[id], reserve)


func _mag(id: StringName) -> int:
	return int(_state.get(String(id) + "_mag"))


func _chamber(id: StringName) -> int:
	return 1 if _state.weapon_chambered.get(id, false) else 0


func _total(id: StringName) -> int:
	return _mag(id) + _chamber(id)


func _reserve(id: StringName) -> int:
	return int(_state.get(RESERVES[id]))


func _pool(key: StringName) -> int:
	var count := int(_state.get(key))
	for id: StringName in IDS:
		if RESERVES[id] == key:
			count += _total(id)
	return count


func _shoot(weapon, label: String) -> bool:
	var id: StringName = weapon.weapon_data.weapon_id
	var before := _pool(RESERVES[id])
	var shots := _fired.size()
	var health: float = _target.health
	var fired: bool = weapon._fire()
	_assert(fired and _fired.size() == shots + 1 and _fired[-1] == id, label + " emits one real shot")
	_assert(is_equal_approx(health - float(_target.health), weapon.weapon_data.damage_body * weapon.weapon_data.pellet_count), label + " damages the real physical target for its actual pellet budget")
	_assert(_pool(RESERVES[id]) == before - 1, label + " consumes exactly one round from its complete shared pool")
	_assert(not _ammo.is_empty() and _ammo[-1].weapon == id and _ammo[-1].mag == _mag(id) and _ammo[-1].reserve == _reserve(id), label + " broadcasts container-only magazine and reserve values")
	return fired


func _pump(weapon, label: String) -> void:
	var before := _pool(&"spas12_reserve")
	var tube := _mag(&"spas12")
	var shots := _fired.size()
	_assert(weapon._pump_left > 0.0 and _chamber(&"spas12") == 0, label + " keeps the chamber empty before pump completion")
	weapon._process(_config.SPAS12_PUMP_TIME * 0.49)
	_assert(_chamber(&"spas12") == 0 and not weapon._fire() and _fired.size() == shots, label + " cannot fire or feed early during the real pump cycle")
	weapon._process(_config.SPAS12_PUMP_TIME * 0.52)
	_assert(weapon._pump_left <= 0.0 and _chamber(&"spas12") == (1 if tube > 0 else 0) and _mag(&"spas12") == maxi(0, tube - 1), label + " completes its production pump timing and transfers exactly one available tube shell")
	_assert(_pool(&"spas12_reserve") == before, label + " pumping transfers a shell without creating or consuming ammunition")


func _finish_reload(weapon, label: String) -> void:
	if weapon.weapon_data.weapon_id == &"spas12":
		for step in weapon.weapon_data.mag_size + 2:
			if not weapon._is_reloading:
				break
			weapon._process(weapon.weapon_data.reload_time + 0.001)
		if _chamber(&"spas12") == 0 and _mag(&"spas12") > 0:
			_pump(weapon, label + " empty reload")
	else:
		await create_timer(weapon.weapon_data.reload_time + 0.03).timeout
	_assert(not weapon._is_reloading, label + " exits the real reload state")


func _check_gun(id: StringName) -> void:
	var weapon = _select(id)
	var capacity: int = weapon.weapon_data.mag_size
	_assert(_mag(id) == capacity - 1 and _chamber(id) == 1 and _total(id) == capacity, "%s reset preserves total M with a real loaded chamber" % id)
	_shoot(weapon, "%s initial supply" % id)
	if id == &"spas12":
		_pump(weapon, "SPAS initial shot")
	_assert(_total(id) == capacity - 1, "%s initial firing reduces total ammunition by one" % id)

	weapon = _select(id)
	_set_supply(id, 0, true, 0)
	_shoot(weapon, "%s last chamber round" % id)
	_assert(_mag(id) == 0 and _chamber(id) == 0, "%s final shot empties magazine and chamber" % id)
	if id == &"spas12":
		_pump(weapon, "SPAS final shot")
	var shots := _fired.size()
	_assert(not weapon._fire() and _fired.size() == shots and _total(id) == 0, "%s cannot produce another shot from truly empty supply" % id)

	weapon = _select(id)
	_set_supply(id, 2, true, capacity + 10)
	var pool := _pool(RESERVES[id])
	weapon._start_reload()
	weapon._start_reload()
	_assert(weapon._is_reloading and _reload_started == [id], "%s duplicate tactical reload starts exactly once" % id)
	_assert(not weapon._fire() and _fired.is_empty() and _pool(RESERVES[id]) == pool, "%s cannot fire its retained chamber during reload" % id)
	await _finish_reload(weapon, "%s tactical reload" % id)
	_assert(_reload_done == [id] and _mag(id) == capacity and _chamber(id) == 1 and _total(id) == capacity + 1, "%s tactical reload genuinely supplies M+1" % id)
	_assert(_reserve(id) == 12 and _pool(RESERVES[id]) == pool, "%s tactical reload fills only its container from reserve" % id)
	_shoot(weapon, "%s tactical M+1 first shot" % id)
	if id == &"spas12":
		_pump(weapon, "SPAS tactical shot")
	_assert(_total(id) == capacity, "%s firing M+1 returns to total M" % id)

	weapon = _select(id)
	_set_supply(id, 0, false, capacity + 10)
	pool = _pool(RESERVES[id])
	weapon._start_reload()
	await _finish_reload(weapon, "%s empty reload" % id)
	_assert(_reload_done == [id] and _mag(id) == capacity - 1 and _chamber(id) == 1 and _total(id) == capacity and _reserve(id) == 10, "%s empty reload loads M then transfers one round to the chamber" % id)
	_assert(_pool(RESERVES[id]) == pool, "%s empty reload preserves the full shared pool" % id)
	weapon._start_reload()
	await _finish_reload(weapon, "%s repeated top-up" % id)
	_assert(_mag(id) == capacity and _chamber(id) == 1 and _total(id) == capacity + 1 and _reserve(id) == 9 and _pool(RESERVES[id]) == pool, "%s repeated top-up pays exactly one reserve round for M+1" % id)
	var started := _reload_started.size()
	weapon._start_reload()
	_assert(not weapon._is_reloading and _reload_started.size() == started and _total(id) == capacity + 1 and _pool(RESERVES[id]) == pool, "%s full M+1 cannot repeatedly manufacture ammunition" % id)

	weapon = _select(id)
	_set_supply(id, 0, false, 1)
	pool = _pool(RESERVES[id])
	weapon._start_reload()
	await _finish_reload(weapon, "%s one-round reserve reload" % id)
	_assert(_mag(id) == 0 and _chamber(id) == 1 and _reserve(id) == 0 and _pool(RESERVES[id]) == pool, "%s one reserve round becomes one usable chamber round" % id)
	_shoot(weapon, "%s one-round reserve final shot" % id)
	if id == &"spas12":
		_pump(weapon, "SPAS low-reserve shot")
	_assert(_total(id) == 0 and _reserve(id) == 0, "%s low-reserve shot leaves no duplicated ammunition" % id)

	weapon = _select(id)
	_set_supply(id, 2, true, 10)
	pool = _pool(RESERVES[id])
	weapon._start_reload()
	_player._switch_weapon(&"pistol" if id != &"pistol" else &"rifle")
	await create_timer(weapon.weapon_data.reload_time + 0.03).timeout
	if id == &"spas12":
		weapon._process(weapon.weapon_data.reload_time + 0.001)
	_assert(not weapon._is_reloading and _reload_done.is_empty() and _mag(id) == 2 and _chamber(id) == 1 and _reserve(id) == 10 and _pool(RESERVES[id]) == pool, "%s real switch cancels pending reload without a delayed supply write" % id)
	_evidence.append({"weapon": id, "capacity": capacity, "tactical_total": capacity + 1, "reload_fixture_seconds": weapon.weapon_data.reload_time})


func _check_shared_pools() -> void:
	for key: StringName in [&"ammo_9x19_reserve", &"rifle_reserve", &"pistol_reserve", &"em86_reserve", &"magnum_reserve", &"shotgun_reserve"]:
		var members: Array[StringName] = []
		for id: StringName in IDS:
			if RESERVES[id] == key:
				members.append(id)
		_state.set(key, 1000)
		for id: StringName in members:
			_state.set(String(id) + "_mag", 2)
			_state.weapon_chambered[id] = true
		var before := _pool(key)
		for id: StringName in members:
			var weapon = _select(id)
			_shoot(weapon, "%s common-pool live shot" % id)
			weapon._start_reload()
			await _finish_reload(weapon, "%s common-pool top-up" % id)
		_assert(_pool(key) == before - members.size(), "%s shared pool loses only the actual fired rounds across all member guns" % key)


func _check_trigger_sequences() -> void:
	var weapon = _select(&"mpx")
	_set_supply(&"mpx", 1, true, 0)
	_state.fire_modes[&"mpx"] = &"burst"
	weapon._on_trigger_pressed()
	for tick in 10:
		weapon._tick_weapon(weapon.weapon_data.burst_fire_interval + 0.001)
	_assert(_fired.size() == 2 and _total(&"mpx") == 0 and weapon._burst_left == 0, "MPX burst consumes exactly magazine plus final chamber, then clears its unfinished budget")
	_set_supply(&"mpx", 1, true, 0)
	weapon._fire_cooldown = 0.0
	_state.fire_modes[&"mpx"] = &"auto"
	weapon._trigger_held = true
	for tick in 10:
		weapon._tick_weapon(weapon.weapon_data.fire_interval + 0.001)
	_assert(_fired.size() == 4 and _total(&"mpx") == 0, "MPX held automatic fire also consumes its final chamber exactly once")
	weapon._trigger_held = false


func _check_spas_pump_reload_edges() -> void:
	var weapon = _select(&"spas12")
	_set_supply(&"spas12", 0, true, 20)
	_shoot(weapon, "SPAS last chamber before immediate R")
	weapon._start_reload()
	_assert(weapon._is_reloading and _chamber(&"spas12") == 0 and _total(&"spas12") == 0 and _reserve(&"spas12") == 20, "SPAS immediate R begins from genuinely empty supply after one actual final shot")
	weapon._process(_config.SPAS12_RELOAD_SHELL_TIME)
	_assert(_mag(&"spas12") == 1 and _chamber(&"spas12") == 0 and _reserve(&"spas12") == 19, "SPAS first real shell interval inserts one shell without an early chamber transfer")
	weapon._process(_config.SPAS12_PUMP_TIME - _config.SPAS12_RELOAD_SHELL_TIME + 0.01)
	_assert(_mag(&"spas12") == 1 and _chamber(&"spas12") == 0 and _reserve(&"spas12") == 19 and _fired.size() == 1, "SPAS old shot-pump endpoint cannot feed a newly inserted shell during empty reload")
	await _finish_reload(weapon, "SPAS interleaved empty reload")
	_assert(_mag(&"spas12") == 7 and _chamber(&"spas12") == 1 and _total(&"spas12") == 8 and _reserve(&"spas12") == 12 and _fired.size() == 1, "SPAS shot-pump plus immediate R still loads exactly M=8 from eight reserve shells")
	_shoot(weapon, "SPAS post-interleaving first shot")
	_assert(_total(&"spas12") == 7 and _reserve(&"spas12") == 12 and _fired.size() == 2, "SPAS interleaved empty reload permits one real next shot and preserves its exact eight-shell budget")

	weapon = _select(&"spas12")
	_set_supply(&"spas12", 2, true, 0)
	_shoot(weapon, "SPAS switch during actual shot pump")
	weapon._process(_config.SPAS12_PUMP_TIME * 0.3)
	_assert(_chamber(&"spas12") == 0 and weapon._pump_left > 0.0, "SPAS switching fixture has a real incomplete pump and two remaining tube shells")
	_player._switch_weapon(&"pistol")
	weapon._process(_config.SPAS12_PUMP_TIME + 0.1)
	_assert(_mag(&"spas12") == 2 and _chamber(&"spas12") == 0 and _fired.size() == 1, "SPAS inactive gun cannot silently finish its cancelled pump or fire")
	_player._switch_weapon(&"spas12")
	_assert(not weapon._fire() and _mag(&"spas12") == 2 and _chamber(&"spas12") == 0 and weapon._pump_left > 0.0 and _fired.size() == 1, "SPAS returning with an empty chamber starts a fresh full pump instead of bypassing chambering")
	_pump(weapon, "SPAS fresh pump after switch back")
	_shoot(weapon, "SPAS actual shot after fresh pump")
	_assert(_total(&"spas12") == 1 and _reserve(&"spas12") == 0 and _fired.size() == 2, "SPAS switch-back pump and next shot conserve the remaining physical shells")


func _check_scene_and_reset() -> void:
	_state.set(&"ammo_9x19_reserve", 510)
	for id: StringName in IDS:
		_state.set(String(id) + "_mag", 0)
		_state.weapon_chambered[id] = true
	var saved: Dictionary = _state.weapon_chambered.duplicate()
	_player.queue_free()
	await process_frame
	_create_player()
	await physics_frame
	_assert(_state.weapon_chambered == saved and _state.ammo_9x19_reserve == 510, "actual Player scene replacement preserves all chamber states and shared reserve")
	for id: StringName in IDS:
		var weapon = _select(id)
		_shoot(weapon, "%s retained chamber after Player replacement" % id)
	# In a RED build, rejected last-chamber shots may start real reload timers.
	# Cancel their generations and let every owner-holding coroutine return.
	_player._switch_weapon(&"rifle")
	await create_timer(0.08).timeout
	_state.reset()
	for id: StringName in IDS:
		var capacity: int = _weapons[id].weapon_data.mag_size
		_assert(_mag(id) == capacity - 1 and _chamber(id) == 1 and _total(id) == capacity, "%s explicit reset restores M-1 container plus one chamber" % id)
	_assert(_state.em120r_mag == _config.EM120R_MAG and _state.em40t1_mag == _config.EM40T1_MAG and _state.rifle_grenades == _config.GRENADE_AMMO and not _state.weapon_chambered.has(&"em120r") and not _state.weapon_chambered.has(&"em40t1"), "reset preserves missile/grenade capacities and excludes them from chamber state")


func _on_fired(id: StringName) -> void:
	_fired.append(id)


func _on_reload_started(id: StringName) -> void:
	_reload_started.append(id)


func _on_reload_done(id: StringName) -> void:
	_reload_done.append(id)


func _on_ammo(id: StringName, mag: int, reserve: int) -> void:
	_ammo.append({"weapon": id, "mag": mag, "reserve": reserve})


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
