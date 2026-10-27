extends SceneTree

var _failures: int = 0
var _events: Node
var _config: Node
var _state: Node
var _damage_events: Array = []
var _hit_events: int = 0


class DamageTarget extends StaticBody3D:
	var damage_calls: Array[float] = []

	func take_damage(amount: float, _is_headshot: bool) -> void:
		damage_calls.append(amount)


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state = root.get_node("GameState")
	_events.damage_dealt.connect(_on_damage_dealt)
	_events.hit_confirmed.connect(_on_hit_confirmed)
	_state.reset()
	_assert(_state.dmr_mag == 60 and _state.rifle_reserve == 600, "DMR reset ammunition")
	_assert(_state.shotgun_mag == 32 and _state.shotgun_reserve == 160, "shotgun reset ammunition")
	_assert(_state.fire_modes[&"dmr"] == &"semi", "DMR factory mode is semi only")
	_assert(_state.fire_modes[&"shotgun"] == &"semi", "shotgun factory mode is semi")
	_assert(not _state.weapon_unlocked[&"dmr"] and not _state.weapon_unlocked[&"shotgun"], "new weapons start locked until JB-02 pickup")
	_assert(_state.weapon_unlocked[&"rifle"] and _state.weapon_unlocked[&"pistol"], "original weapons remain unlocked")

	var dmr_data := _make_data(&"dmr")
	_assert(dmr_data.damage_body == 90.0 and dmr_data.mag_size == 60, "DMR uses EC-68 and 60-round magazine")
	_assert(dmr_data.pellet_count == 1 and dmr_data.hitscan_range == 180.0, "DMR single projectile and range")
	var shotgun_data := _make_data(&"shotgun")
	_assert(shotgun_data.pellet_count == 12, "shotgun fires twelve pellets")
	_assert(shotgun_data.mag_size == 32 and shotgun_data.damage_body == 30.0, "shotgun magazine and per-pellet damage")
	_assert(shotgun_data.fire_interval == 0.12 and shotgun_data.hitscan_range == 50.0, "shotgun 500 RPM and 50m range")

	await _check_single_shot(dmr_data)
	await _check_trigger_cadence(dmr_data)
	await _check_dmr_shared_reload(dmr_data)
	await _check_shotgun(shotgun_data)
	await _check_pickups()
	await _check_reload(shotgun_data)
	_events.damage_dealt.disconnect(_on_damage_dealt)
	_events.hit_confirmed.disconnect(_on_hit_confirmed)
	print("test_long_guns: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _make_data(weapon_id: StringName) -> WeaponData:
	var data := WeaponData.new()
	data.weapon_id = weapon_id
	data.sync_from_config()
	return data


func _make_weapon(data: WeaponData) -> Node3D:
	var weapon = (load("res://scripts/weapons/long_gun_controller.gd") as GDScript).new()
	weapon.weapon_data = data
	var view_model := Node3D.new()
	view_model.name = "ViewModel"
	weapon.add_child(view_model)
	var model := Node3D.new()
	model.name = "Weapon"
	view_model.add_child(model)
	root.add_child(weapon)
	return weapon


func _make_target(radius: float) -> DamageTarget:
	var target := DamageTarget.new()
	target.position = Vector3(0.0, 0.0, -5.0)
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision.shape = sphere
	target.add_child(collision)
	root.add_child(target)
	return target


func _check_single_shot(data: WeaponData) -> void:
	_state.reset()
	_state.current_weapon = &"dmr"
	var weapon := _make_weapon(data)
	var target := _make_target(0.5)
	await process_frame
	await physics_frame
	_damage_events.clear()
	_hit_events = 0
	_assert(weapon._fire(), "DMR fires")
	_assert(_state.dmr_mag == 59, "DMR consumes one round")
	_assert(target.damage_calls.size() == 1 and target.damage_calls[0] == 90.0, "DMR deals one EC-68 hit")
	_assert(_damage_events == [[90.0, false]], "DMR emits one damage event")
	weapon.queue_free()
	target.queue_free()
	await process_frame


func _check_trigger_cadence(data: WeaponData) -> void:
	_state.reset()
	_state.current_weapon = &"dmr"
	var weapon := _make_weapon(data)
	await process_frame
	weapon._on_trigger_pressed()
	weapon._on_trigger_pressed()
	_assert(_state.dmr_mag == 59, "semi trigger edge respects fire cooldown")
	weapon._tick_weapon(data.semi_fire_interval + 0.01)
	weapon._on_trigger_pressed()
	_assert(_state.dmr_mag == 58, "semi trigger fires again after cooldown")
	weapon.queue_free()
	await process_frame


func _check_dmr_shared_reload(data: WeaponData) -> void:
	_state.reset()
	_state.current_weapon = &"dmr"
	_state.dmr_mag = 10
	_state.rifle_mag = 45
	_state.rifle_reserve = 100
	var weapon := _make_weapon(data)
	weapon.reserve_state_property = &"rifle_reserve"
	weapon._reserve_key = &"rifle_reserve"
	weapon._start_reload()
	await create_timer(data.reload_time + 0.1).timeout
	_assert(_state.dmr_mag == 60, "DMR reload fills its 60-round magazine")
	_assert(_state.rifle_reserve == 50, "DMR reload draws from the shared rifle reserve")
	_assert(_state.rifle_mag == 45, "DMR reload does not alter the rifle magazine")
	weapon.queue_free()
	await process_frame


func _check_shotgun(data: WeaponData) -> void:
	_state.reset()
	_state.current_weapon = &"shotgun"
	var weapon := _make_weapon(data)
	var target := _make_target(3.0)
	await process_frame
	await physics_frame
	_damage_events.clear()
	_hit_events = 0
	_assert(weapon._fire(), "shotgun fires")
	_assert(_state.shotgun_mag == 31, "shotgun consumes one shell not twelve")
	_assert(target.damage_calls.size() == 12, "shotgun resolves twelve pellet hits")
	var total := 0.0
	for amount in target.damage_calls:
		total += amount
	_assert(is_equal_approx(total, 360.0), "shotgun pellet damage sums to 360")
	_assert(_damage_events.size() == 1 and is_equal_approx(_damage_events[0][0], 360.0), "shotgun aggregates damage feedback")
	_assert(_hit_events == 1, "shotgun emits one hit confirmation per trigger")
	_assert(weapon._spread_for_distance(15.0) == 0.0, "shotgun stays clustered through 15m")
	_assert(weapon._spread_for_distance(15.01) > 0.0, "shotgun spreads beyond 15m")
	weapon.queue_free()
	target.queue_free()
	await process_frame


func _check_pickups() -> void:
	_state.reset()
	_state.rifle_reserve = 500
	_state.shotgun_reserve = 100
	var player := Node3D.new()
	player.add_to_group(&"player")
	root.add_child(player)
	var battery := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate()
	battery.kind = &"battery"
	root.add_child(battery)
	battery._on_body_entered(player)
	await process_frame
	_assert(_state.rifle_reserve == 560, "EC-68 pickup refills the shared rifle/DMR pool once")
	var shells := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate()
	shells.kind = &"shotgun_ammo"
	root.add_child(shells)
	shells._on_body_entered(player)
	await process_frame
	_assert(_state.shotgun_reserve == 132, "EC-12 pickup refills shotgun independently")
	for weapon_id: StringName in [&"dmr", &"shotgun"]:
		var equipment := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate()
		equipment.kind = weapon_id
		root.add_child(equipment)
		equipment._on_body_entered(player)
		await process_frame
		_assert(_state.weapon_unlocked[weapon_id], "%s pickup unlocks equipment" % weapon_id)
		_assert(_state.current_weapon == weapon_id, "%s pickup switches to the collected weapon" % weapon_id)
	player.queue_free()
	await process_frame


func _check_reload(data: WeaponData) -> void:
	_state.reset()
	_state.current_weapon = &"shotgun"
	_state.shotgun_mag = 7
	_state.shotgun_reserve = 40
	var weapon := _make_weapon(data)
	weapon._start_reload()
	weapon._start_reload()
	await create_timer(data.reload_time + 0.1).timeout
	_assert(_state.shotgun_mag == 32, "shotgun reload fills magazine")
	_assert(_state.shotgun_reserve == 15, "shotgun reload preserves reserve math")
	_state.shotgun_mag = 7
	_state.shotgun_reserve = 40
	weapon._start_reload()
	await create_timer(0.2).timeout
	_state.current_weapon = &"rifle"
	_events.weapon_switched.emit(&"rifle")
	await create_timer(data.reload_time).timeout
	_assert(_state.shotgun_mag == 7 and _state.shotgun_reserve == 40, "switching cancels shotgun reload without ammunition duplication")
	_assert(not weapon._is_reloading, "switching clears shotgun reload state")
	weapon.queue_free()
	await process_frame


func _on_damage_dealt(amount: float, is_headshot: bool) -> void:
	_damage_events.append([amount, is_headshot])


func _on_hit_confirmed(_is_headshot: bool) -> void:
	_hit_events += 1
