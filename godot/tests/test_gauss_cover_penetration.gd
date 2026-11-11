## EM-127G real physics: a full charge ignores cover and stops at the first live enemy.
extends SceneTree

const Chamber = preload("res://tests/chamber_test_support.gd")

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")
const ORIGIN := Vector3(0, 100, 0)
const TARGET_HEALTH := 10000.0

var _assertions := 0
var _failures := 0
var _world: Node3D
var _case: Node3D
var _player
var _weapon
var _state
var _events
var _shots := 0
var _charges := 0
var _muzzles: Array[Vector3] = []
var _ammo: Array[Vector2i] = []
var _damage: Array[float] = []
var _heads: Array[bool] = []
var _hit_confirmations := 0
var _ricochets := 0


class DamageableCover extends StaticBody3D:
	var damage := 0.0

	func take_damage(amount: float, _head: bool) -> void:
		damage += amount


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(65.0).timeout.connect(func() -> void:
		push_error("gauss cover penetration timed out")
		quit(1))
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_state.reset()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)
	_player.global_position = ORIGIN
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process(false)
		controller.set_physics_process(false)
		controller.set_process_unhandled_input(false)
	_state.weapon_unlocked[&"em127g"] = true
	_player._switch_weapon(&"em127g")
	_weapon = _player.get_node("Camera3D/WeaponMount/Em127g")
	_weapon.weapon_data = _weapon.weapon_data.duplicate()
	_weapon.weapon_data.spread_hip = 0.0
	_weapon.weapon_data.spread_aim = 0.0
	_weapon.weapon_data.spread_prone = 0.0
	_events.weapon_fired.connect(_on_shot)
	_events.weapon_charge_fired.connect(_on_charge)
	_events.player_muzzle_flash.connect(_on_muzzle)
	_events.ammo_changed.connect(_on_ammo)
	_events.damage_dealt.connect(_on_damage)
	_events.hit_confirmed.connect(_on_hit)
	_events.ricochet_on_bunker.connect(_on_ricochet)
	await _sync_physics()
	_assert(_weapon.weapon_data.damage_body == 450.0 and _weapon.weapon_data.headshot_factor == 2.0 and _weapon.weapon_data.hitscan_range == 320.0, "production Gauss retains 450 normal damage, doubled head damage and 320m range")
	_assert(root.get_node("GameConfig").EM127G_CHARGE_TIME == 1.0 and root.get_node("GameConfig").EM127G_CHARGED_DAMAGE_BODY == 900.0, "production full charge remains one second and 900 body damage")
	await _check_cover_cases()
	await _check_normal_shots()
	await _check_first_enemy()
	await _check_head_and_range()
	await _check_owner_exclusion()
	await _check_range_target()
	await _check_bunker()
	await _check_empty_and_no_target()
	await _check_reload_and_switch()
	await _check_reload_hold_edges()
	await _check_capture_release()
	_events.weapon_fired.disconnect(_on_shot)
	_events.weapon_charge_fired.disconnect(_on_charge)
	_events.player_muzzle_flash.disconnect(_on_muzzle)
	_events.ammo_changed.disconnect(_on_ammo)
	_events.damage_dealt.disconnect(_on_damage)
	_events.hit_confirmed.disconnect(_on_hit)
	_events.ricochet_on_bunker.disconnect(_on_ricochet)
	_world.queue_free()
	current_scene = null
	await process_frame
	print("GAUSS_COVER_PENETRATION COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _new_case(label: String, mag: int = 10, reserve: int = 100) -> void:
	if _case != null:
		_case.queue_free()
		await process_frame
	_case = Node3D.new()
	_case.name = label.to_pascal_case()
	_world.add_child(_case)
	_player._switch_weapon(&"pistol")
	_player._switch_weapon(&"em127g")
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	_weapon.global_transform = Transform3D(Basis.IDENTITY, ORIGIN)
	_weapon._trigger_held = false
	_weapon._charge_elapsed = 0.0
	_weapon._charge_fired = false
	_weapon._charged_shot = false
	_weapon._fire_cooldown = 0.0
	Chamber.set_total(_state, &"em127g", mag)
	_state.magnum_reserve = reserve
	_shots = 0
	_charges = 0
	_muzzles.clear()
	_ammo.clear()
	_damage.clear()
	_heads.clear()
	_hit_confirmations = 0
	_ricochets = 0


func _box(parent: Node3D, size: Vector3, position: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = position
	parent.add_child(collision)
	return collision


func _wall(distance: float, thickness: float, parent: Node3D = null) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "ConcreteWall"
	_box(wall, Vector3(6, 6, thickness), Vector3.ZERO)
	(parent if parent != null else _case).add_child(wall)
	wall.global_position = ORIGIN + Vector3.FORWARD * distance
	return wall


func _target(distance: float, head: bool = false, range_target: bool = false):
	var path := "res://scripts/levels/range_target.gd" if range_target else "res://scripts/enemies/enemy_base.gd"
	var target = load(path).new()
	target.name = "RangeTarget" if range_target else "EnemyTarget"
	var eye := Marker3D.new()
	eye.name = "Eye"
	eye.position = Vector3(0, 1.6, 0)
	target.add_child(eye)
	_box(target, Vector3(1.0, 1.0, 0.4), Vector3(0, 0.85, 0))
	var head_area := Area3D.new()
	head_area.name = "HeadHitbox"
	head_area.set_meta(&"hit_part", &"head")
	_box(head_area, Vector3(0.3, 0.3, 0.3), Vector3.ZERO)
	head_area.position = Vector3(0, 1.6, 0)
	target.add_child(head_area)
	if range_target:
		target.target_health = TARGET_HEALTH
	_case.add_child(target)
	target.global_position = ORIGIN + Vector3(0, -1.6 if head else -0.85, -distance)
	target.health = TARGET_HEALTH
	target.set_process(false)
	target.set_physics_process(false)
	return target


func _sync_physics() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _raw_hit(exclude_owner: bool = true) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(ORIGIN, ORIGIN + Vector3.FORWARD * _weapon.weapon_data.hitscan_range)
	query.collide_with_areas = true
	if exclude_owner:
		query.exclude = HitSolver.collect_owner_rids(_weapon)
	return _world.get_world_3d().direct_space_state.intersect_ray(query)


func _trigger(pressed: bool) -> void:
	if DisplayServer.get_name() == "headless" and pressed:
		_weapon._trigger_held = true
		_weapon._on_trigger_pressed()
		return
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	_weapon._unhandled_input(event)


func _charge_once(label: String) -> void:
	_trigger(true)
	_weapon._tick_weapon(0.5)
	_assert(_shots == 0 and _charges == 0 and _ammo.is_empty() and _damage.is_empty(), "%s does not shoot or consume ammo below the one-second threshold" % label)
	_weapon._tick_weapon(0.5)
	_weapon._tick_weapon(1.5)
	_trigger(false)
	_weapon._tick_weapon(0.6)


func _reload_input() -> void:
	if DisplayServer.get_name() == "headless":
		_weapon._start_reload()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.physical_keycode = KEY_R
	event.pressed = true
	_weapon._unhandled_input(event)


func _check_shot(label: String, charged: bool, damage: float = 0.0, head: bool = false, initial_mag: int = 10, initial_reserve: int = 100) -> void:
	_assert(_shots == 1 and _charges == int(charged), "%s emits one real shot and the expected charged event exactly once per hold" % label)
	_assert(_muzzles.size() == 1 and _muzzles[0].is_finite(), "%s emits exactly one finite actual muzzle event" % label)
	var remaining := initial_mag - 1
	var container := maxi(0, remaining - 1)
	_assert(Chamber.total(_state, &"em127g") == remaining and _state.em127g_mag == container and _state.magnum_reserve == initial_reserve and _ammo == [Vector2i(container, initial_reserve)], "%s consumes one Gauss round and broadcasts its conserved container-only EC127 ammo update" % label)
	if damage > 0.0:
		_assert(_damage == [damage] and _heads == [head] and _hit_confirmations == 1, "%s settles one target hit for %.0f damage with the correct head flag" % [label, damage])
	else:
		_assert(_damage.is_empty() and _hit_confirmations == 0, "%s does not invent a target hit" % label)


func _check_cover_cases() -> void:
	for sample: Array in [["wall", [[6.0, 0.25]]], ["thick_wall", [[9.0, 8.0]]], ["multilayer", [[4.0, 0.25], [8.0, 1.0], [13.0, 3.0]]]]:
		var label: String = sample[0]
		await _new_case(label)
		var walls: Array[StaticBody3D] = []
		for layer: Array in sample[1]:
			walls.append(_wall(float(layer[0]), float(layer[1])))
		var first = _target(22.0)
		var second = _target(29.0)
		await _sync_physics()
		var hit := _raw_hit()
		_assert(not hit.is_empty() and hit.collider == walls[0], "%s positive control confirms real opaque cover blocks the initial physical ray" % label)
		_charge_once(label)
		_check_shot(label, true, 900.0)
		_assert(first.health == TARGET_HEALTH - 900.0 and second.health == TARGET_HEALTH, "%s charged ray ignores all cover but stops at the first live enemy" % label)
	await _new_case("damageable_cover")
	var cover := DamageableCover.new()
	_box(cover, Vector3(4, 4, 1), Vector3.ZERO)
	_case.add_child(cover)
	cover.global_position = ORIGIN + Vector3.FORWARD * 5.0
	var enemy = _target(15.0)
	await _sync_physics()
	_assert(HitSolver.find_damageable(cover) == cover and not cover.is_in_group(&"enemy"), "damageable-cover control implements take_damage but is not an enemy")
	_charge_once("damageable_cover")
	_check_shot("damageable_cover", true, 900.0)
	_assert(cover.damage == 0.0 and enemy.health == TARGET_HEALTH - 900.0, "charged Gauss skips a non-enemy damageable scene obstacle")


func _check_normal_shots() -> void:
	for covered in [false, true]:
		var label := "normal_covered" if covered else "normal_open"
		await _new_case(label)
		var enemy = _target(16.0)
		if covered:
			_wall(5.0, 2.0)
		await _sync_physics()
		_trigger(true)
		_weapon._tick_weapon(0.1)
		_trigger(false)
		_check_shot(label, false, 0.0 if covered else 450.0)
		_assert(enemy.health == TARGET_HEALTH - (0.0 if covered else 450.0), "%s short-press 450 round retains ordinary cover blocking" % label)


func _check_first_enemy() -> void:
	await _new_case("first_enemy_without_cover")
	var first = _target(8.0)
	var second = _target(18.0)
	await _sync_physics()
	_charge_once("first_enemy_without_cover")
	_check_shot("first_enemy_without_cover", true, 900.0)
	_assert(first.health == TARGET_HEALTH - 900.0 and second.health == TARGET_HEALTH, "charged Gauss never passes through the first live enemy to hurt a second")
	await _new_case("dead_enemy_before_live_enemy")
	var dead = _target(8.0)
	dead._dead = true
	var live = _target(18.0)
	await _sync_physics()
	_charge_once("dead_enemy_before_live_enemy")
	_check_shot("dead_enemy_before_live_enemy", true, 900.0)
	_assert(dead.health == TARGET_HEALTH and live.health == TARGET_HEALTH - 900.0, "a dead enemy collider is not a valid charged-shot stopping target")
	await _new_case("queued_enemy_before_live_enemy")
	var queued = _target(8.0)
	live = _target(18.0)
	await _sync_physics()
	queued.queue_free()
	# No frame is yielded before the shot: the queued collider still exists in physics.
	var hit := _raw_hit()
	_assert(queued.is_queued_for_deletion() and not hit.is_empty() and hit.collider == queued, "queued-enemy control preserves its actual pending-deletion collider until the frame ends")
	_charge_once("queued_enemy_before_live_enemy")
	_check_shot("queued_enemy_before_live_enemy", true, 900.0)
	_assert(queued.health == TARGET_HEALTH and live.health == TARGET_HEALTH - 900.0, "a queued enemy collider cannot stop or receive the charged round before the first live enemy")


func _check_head_and_range() -> void:
	for sample: Array in [["head_behind_cover", 20.0, true, 1800.0], ["inside_range", 319.9, false, 900.0], ["outside_range", 321.0, false, 0.0]]:
		var label: String = sample[0]
		await _new_case(label)
		_wall(5.0, 1.0)
		var enemy = _target(float(sample[1]), bool(sample[2]))
		await _sync_physics()
		_charge_once(label)
		_check_shot(label, true, float(sample[3]), bool(sample[2]))
		_assert(enemy.health == TARGET_HEALTH - float(sample[3]), "%s preserves the 320m endpoint and charged head/body damage" % label)


func _check_owner_exclusion() -> void:
	await _new_case("owner_exclusion")
	var owner_shape := _box(_player, Vector3(3, 3, 1), Vector3(0, 0, -3))
	var enemy = _target(14.0)
	await _sync_physics()
	var blocked := _raw_hit(false)
	var excluded := _raw_hit(true)
	_assert(not blocked.is_empty() and blocked.collider == _player, "owner control places the real Player RID ahead of the charged ray")
	_assert(not excluded.is_empty() and HitSolver.find_damageable(excluded.collider) == enemy, "production owner-RID collection excludes the physical holder before tracing")
	_charge_once("owner_exclusion")
	_check_shot("owner_exclusion", true, 900.0)
	_assert(enemy.health == TARGET_HEALTH - 900.0, "charged Gauss excludes its physical holder and reaches the first enemy")
	owner_shape.queue_free()
	await _sync_physics()


func _check_range_target() -> void:
	await _new_case("passive_range_target")
	_wall(4.0, 2.0)
	var first = _target(15.0, false, true)
	var second = _target(23.0)
	await _sync_physics()
	_assert(first.is_in_group(&"range_target") and not first.is_in_group(&"enemy"), "passive target uses the actual range_target script and its distinct group")
	_charge_once("passive_range_target")
	_check_shot("passive_range_target", true, 900.0)
	_assert(first.health == TARGET_HEALTH - 900.0 and second.health == TARGET_HEALTH, "the first passive range target is valid and stops charged penetration")


func _check_bunker() -> void:
	for charged in [false, true]:
		var label := "charged_bunker" if charged else "normal_bunker"
		await _new_case(label)
		var bunker := Node3D.new()
		bunker.name = "BunkerShell"
		bunker.add_to_group(&"bunker")
		_case.add_child(bunker)
		var wall := _wall(5.0, 2.0, bunker)
		wall.add_to_group(&"bunker_wall")
		var gunner = (load("res://scenes/enemies/bunker_machine_gunner.tscn") as PackedScene).instantiate()
		bunker.add_child(gunner)
		gunner.global_position = ORIGIN + Vector3(0, -1.3, -15.0 + 0.4)
		gunner.health = TARGET_HEALTH
		gunner.set_process(false)
		gunner.set_physics_process(false)
		await _sync_physics()
		_assert(gunner.is_in_group(&"enemy") and HitSolver.find_group_ancestor(gunner, &"bunker") == bunker, "bunker control separates the actual enemy gunner from its ancestor shell and wall")
		if charged:
			_charge_once(label)
		else:
			_trigger(true)
			_weapon._tick_weapon(0.1)
			_trigger(false)
		_check_shot(label, charged, 900.0 if charged else 0.0)
		_assert(gunner.health == TARGET_HEALTH - (900.0 if charged else 0.0), "%s treats bunker walls as cover and its machine gunner as the first valid enemy" % label)
		if not charged:
			_assert(_ricochets == 1, "normal Gauss retains exactly one bunker ricochet event")


func _check_empty_and_no_target() -> void:
	await _new_case("charged_no_target")
	_wall(7.0, 5.0)
	await _sync_physics()
	_charge_once("charged_no_target")
	_check_shot("charged_no_target", true)
	await _new_case("empty_weapon", 0, 0)
	var enemy = _target(12.0)
	await _sync_physics()
	_charge_once("empty_weapon")
	_assert(_shots == 0 and _charges == 0 and _muzzles.is_empty() and _ammo.is_empty() and _damage.is_empty(), "empty Gauss cannot emit a charged round, muzzle event or invented hit")
	_assert(_state.em127g_mag == 0 and _state.magnum_reserve == 0 and enemy.health == TARGET_HEALTH and not _weapon._is_reloading, "empty no-reserve Gauss preserves ammunition and cannot invent a reload")


func _check_reload_and_switch() -> void:
	await _new_case("reload_during_charge", 5, 100)
	var enemy = _target(15.0)
	await _sync_physics()
	_trigger(true)
	_weapon._tick_weapon(0.5)
	_weapon._start_reload()
	_weapon._tick_weapon(0.7)
	_trigger(false)
	_assert(_weapon._is_reloading and _shots == 0 and _charges == 0 and enemy.health == TARGET_HEALTH, "real reload interrupts a partial charge without firing during reload or on release")
	await create_timer(_weapon.weapon_data.reload_time + 0.1).timeout
	_weapon._tick_weapon(1.1)
	_assert(not _weapon._is_reloading and _state.em127g_mag == _weapon.weapon_data.mag_size and Chamber.total(_state, &"em127g") + _state.magnum_reserve == 105 and _shots == 0 and _charges == 0, "completed timed reload conserves ammo and cannot revive the released partial charge")
	await _new_case("switch_during_charge")
	enemy = _target(15.0)
	await _sync_physics()
	_trigger(true)
	_weapon._tick_weapon(0.5)
	_player._switch_weapon(&"pistol")
	_weapon._physics_process(0.1)
	_trigger(false)
	_player._switch_weapon(&"em127g")
	_weapon._physics_process(1.1)
	_trigger(false)
	_assert(_shots == 0 and _charges == 0 and Chamber.total(_state, &"em127g") == 10 and _state.magnum_reserve == 100 and enemy.health == TARGET_HEALTH, "switching away cancels charge and returning cannot fire a stale hold or release")


func _check_reload_hold_edges() -> void:
	await _new_case("half_charge_released")
	var enemy = _target(15.0)
	await _sync_physics()
	_trigger(true)
	_weapon._tick_weapon(0.5)
	_trigger(false)
	_weapon._tick_weapon(1.2)
	_trigger(false)
	_weapon._tick_weapon(1.2)
	_check_shot("half_charge_released", false, 450.0)
	_assert(enemy.health == TARGET_HEALTH - 450.0, "releasing at half charge produces one normal shot and no delayed charged or repeated-release shot")
	await _new_case("partial_charge_reload_held", 5, 100)
	enemy = _target(15.0)
	await _sync_physics()
	_trigger(true)
	_weapon._tick_weapon(0.5)
	_reload_input()
	_weapon._tick_weapon(0.7)
	_assert(_weapon._is_reloading and _shots == 0 and _charges == 0, "R during a held partial charge blocks its original hold while reloading")
	await create_timer(_weapon.weapon_data.reload_time + 0.1).timeout
	# No new press is synthesized after reload: this is the original held input.
	_weapon._tick_weapon(1.1)
	_trigger(false)
	_weapon._tick_weapon(1.1)
	_assert(_shots == 0 and _charges == 0 and _damage.is_empty() and enemy.health == TARGET_HEALTH, "R cancels the original partial-charge hold so reload completion and release cannot fire a ghost shot")
	_assert(_state.em127g_mag == _weapon.weapon_data.mag_size and Chamber.total(_state, &"em127g") + _state.magnum_reserve == 105 and _ammo == [Vector2i(30, 74)], "cancelled held charge reload transfers exactly the missing rounds without a ghost ammo update")
	await _new_case("charged_shot_reload_held", 5, 100)
	enemy = _target(15.0)
	await _sync_physics()
	_trigger(true)
	_weapon._tick_weapon(0.5)
	_weapon._tick_weapon(0.5)
	_check_shot("charged_shot_reload_held before R", true, 900.0, false, 5, 100)
	_reload_input()
	_weapon._tick_weapon(0.2)
	_assert(_weapon._is_reloading and _shots == 1 and _charges == 1, "R after the charged round cannot fire again from the same original hold during reload")
	await create_timer(_weapon.weapon_data.reload_time + 0.1).timeout
	_weapon._tick_weapon(1.1)
	_trigger(false)
	_weapon._tick_weapon(1.1)
	_assert(_shots == 1 and _charges == 1 and _muzzles.size() == 1 and _damage == [900.0] and enemy.health == TARGET_HEALTH - 900.0, "R after one charged shot cannot revive its consumed hold after reload or on release")
	_assert(_state.em127g_mag == _weapon.weapon_data.mag_size and Chamber.total(_state, &"em127g") + _state.magnum_reserve == 104 and _ammo == [Vector2i(3, 100), Vector2i(30, 73)], "charged shot then reload conserves one fired round and exactly one reload transfer")


func _check_capture_release() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: native Gauss mouse-capture release requires a native display")
		return
	for release_first: bool in [false, true]:
		await _new_case("capture_loss_release_first" if release_first else "capture_loss_physics_first")
		var enemy = _target(15.0)
		await _sync_physics()
		_trigger(true)
		_weapon._tick_weapon(0.5)
		_assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _shots == 0 and _weapon._trigger_held, "native capture-loss control starts a real held half-charge")
		# Esc/menu has already released capture. Do not use _trigger(false),
		# whose ordinary-shot fixture intentionally restores capture.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "native Esc/menu control actually releases mouse capture")
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		if release_first:
			_weapon._unhandled_input(release)
			_weapon._physics_process(1.1)
		else:
			_weapon._physics_process(1.1)
			_weapon._unhandled_input(release)
		_weapon._tick_weapon(1.1)
		_assert(_shots == 0 and _charges == 0 and _muzzles.is_empty() and _damage.is_empty() and enemy.health == TARGET_HEALTH, "native capture loss cancels charge with either physics/release order and cannot emit a ghost shot")
		_assert(Chamber.total(_state, &"em127g") == 10 and _state.magnum_reserve == 100 and _ammo.is_empty(), "native capture loss preserves ammunition without a ghost ammo update")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_weapon._physics_process(1.1)
		_weapon._unhandled_input(release)
		_assert(_shots == 0 and _charges == 0 and not _weapon._trigger_held, "recapturing the mouse cannot revive the old held charge without a new press")


func _on_shot(id: StringName) -> void:
	if id == &"em127g":
		_shots += 1


func _on_charge(id: StringName) -> void:
	if id == &"em127g":
		_charges += 1


func _on_muzzle(id: StringName, position: Vector3) -> void:
	if id == &"em127g":
		_muzzles.append(position)


func _on_ammo(id: StringName, mag: int, reserve: int) -> void:
	if id == &"em127g":
		_ammo.append(Vector2i(mag, reserve))


func _on_damage(amount: float, head: bool) -> void:
	_damage.append(amount)
	_heads.append(head)


func _on_hit(_head: bool) -> void:
	_hit_confirmations += 1


func _on_ricochet() -> void:
	_ricochets += 1


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
