## EC-60E contracts and gameplay integration; missing production produces ordinary FAILs.
extends SceneTree

const PROJECTILE_PATH := "res://scenes/weapons/ec60e_projectile.tscn"
const MODEL_PATH := "res://assets/models/weapons/ec60e_grenade.glb"
const ORIGIN := Vector3(0, 100, 0)
const TARGET_HEALTH := 10000.0
const EXPECTED_CONFIG := {
	"EC60E_STARTING_STOCK": 100,
	"EC60E_FUSE_TIME": 3.0,
	"EC60E_INNER_RADIUS": 15.0,
	"EC60E_OUTER_RADIUS": 25.0,
	"EC60E_INNER_DAMAGE": 900.0,
	"EC60E_OUTER_DAMAGE": 750.0,
	"EC60E_SELF_DAMAGE": false,
}

var _assertions := 0
var _failures := 0
var _state
var _events
var _config
var _world: Node3D
var _case: Node3D
var _projectile_scene: PackedScene
var _explosions: Array[Vector3] = []
var _legacy_explosions := 0
var _player_damage := 0
var _deaths: Array[int] = []


class DamageReceiver extends StaticBody3D:
	var health := TARGET_HEALTH
	var amounts: Array[float] = []
	var heads: Array[bool] = []
	var destroyed := 0

	func take_damage(amount: float, head: bool = false) -> bool:
		health -= amount
		amounts.append(amount)
		heads.append(head)
		return false

	func destroy() -> void:
		destroyed += 1


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _has_property(object: Object, property: String) -> bool:
	for item: Dictionary in object.get_property_list():
		if String(item.name) == property:
			return true
	return false


func _run() -> void:
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state.reset()
	var constants: Dictionary = _config.get_script().get_script_constant_map()
	for key: String in EXPECTED_CONFIG:
		_assert(constants.has(key), "%s is declared in GameConfig" % key)
		if constants.has(key):
			_assert(constants[key] == EXPECTED_CONFIG[key], "%s matches the approved EC-60E value" % key)
	_assert(_has_property(_state, "ec60e_grenades"), "GameState declares an independent EC-60E inventory")
	for signal_name: String in ["ec60e_throw_requested", "ec60e_stock_changed", "ec60e_exploded"]:
		_assert(_events.has_signal(signal_name), "Events declares %s" % signal_name)
	_assert(ResourceLoader.exists(PROJECTILE_PATH), "EC-60E has its own projectile scene")
	_assert(FileAccess.file_exists(MODEL_PATH), "EC-60E has its prepared runtime model")
	if constants.has("WEAPON_CATEGORIES"):
		for category: Dictionary in constants["WEAPON_CATEGORIES"]:
			_assert(not str(category).to_lower().contains("ec60e"), "EC-60E occupies no gun category")
	_assert(_state.rifle_grenades == 200, "EC-40 retains its independent 200-round initial pool")
	_assert(not _state.weapon_unlocked.has(&"ec60e"), "EC-60E is not a selectable gun")
	# Runtime loading happens only after the existing autoloads have initialized.
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	_assert(player.has_node("EC60EController"), "actual Player owns the independent EC60EController")
	var player_constants: Dictionary = player.get_script().get_script_constant_map()
	_assert(player_constants.get("KEY_MEDKIT") == KEY_T, "medkit moves from G to T")
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame
	var inventory: Node = hud.find_child("EC60EInventory", true, false)
	_assert(inventory != null, "actual HUD owns a separate EC60EInventory")
	if inventory is CanvasItem:
		_assert((inventory as CanvasItem).visible, "EC-60E inventory starts visible")
	if _has_property(_state, "ec60e_grenades"):
		_assert(_state.get("ec60e_grenades") == 100, "restart initializes exactly 100 EC-60E grenades")
		_state.set("ec60e_grenades", 0)
		_state.reset()
		_assert(_state.get("ec60e_grenades") == 100, "new-game reset restores depleted EC-60E stock to 100")
	if ResourceLoader.exists(PROJECTILE_PATH):
		var scene := load(PROJECTILE_PATH) as PackedScene
		_assert(scene != null, "EC-60E projectile loads as a PackedScene")
		if scene != null:
			var projectile: Node = scene.instantiate()
			_assert(projectile is RigidBody3D, "EC-60E uses a separate physical RigidBody3D")
			_assert(projectile.has_method("setup"), "EC-60E projectile exposes setup")
			_assert(projectile.has_method("_explode"), "EC-60E projectile exposes its once-only explosion")
			projectile.free()
	player.queue_free()
	hud.queue_free()
	await process_frame
	# A missing HUD must not hide independent projectile/damage/fuse results.
	if not ResourceLoader.exists(PROJECTILE_PATH) or not constants.has("EC60E_FUSE_TIME"):
		_finish()
		return
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_projectile_scene = load(PROJECTILE_PATH) as PackedScene
	_events.ec60e_exploded.connect(_on_exploded)
	_events.rpg_exploded.connect(_on_legacy_exploded)
	_events.player_damaged.connect(_on_player_damaged)
	_events.enemy_died.connect(_on_enemy_died)
	await _check_damage_boundaries()
	await _check_dense_cover()
	await _check_recipient_guards()
	await _check_lethal_chain()
	await _check_fuse()
	_events.ec60e_exploded.disconnect(_on_exploded)
	_events.rpg_exploded.disconnect(_on_legacy_exploded)
	_events.player_damaged.disconnect(_on_player_damaged)
	_events.enemy_died.disconnect(_on_enemy_died)
	_world.queue_free()
	current_scene = null
	await process_frame
	_finish()


func _new_case(label: String) -> void:
	if _case != null:
		_case.queue_free()
		await process_frame
	_case = Node3D.new()
	_case.name = label.to_pascal_case()
	_world.add_child(_case)
	_explosions.clear()
	_legacy_explosions = 0
	_player_damage = 0


func _box(parent: Node3D, size: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)
	return collision


func _target(offset: Vector3, range_target: bool = false):
	var path := "res://scripts/levels/range_target.gd" if range_target else "res://scripts/enemies/enemy_base.gd"
	var target = (load(path) as GDScript).new()
	var eye := Marker3D.new()
	eye.name = "Eye"
	target.add_child(eye)
	_box(target, Vector3(0.2, 0.2, 0.2))
	if range_target:
		target.target_health = TARGET_HEALTH
	_case.add_child(target)
	target.global_position = ORIGIN + offset
	target.health = TARGET_HEALTH
	target.set_process(false)
	target.set_physics_process(false)
	return target


func _receiver(offset: Vector3, groups: Array[StringName]) -> DamageReceiver:
	var target := DamageReceiver.new()
	_box(target, Vector3(0.2, 0.2, 0.2))
	_case.add_child(target)
	target.global_position = ORIGIN + offset
	for group: StringName in groups:
		target.add_to_group(group)
	return target


func _projectile(position: Vector3 = ORIGIN) -> RigidBody3D:
	var projectile := _projectile_scene.instantiate() as RigidBody3D
	_case.add_child(projectile)
	projectile.global_position = position
	var excludes: Array[RID] = []
	projectile.call("setup", Vector3.FORWARD, Vector3.ZERO, excludes)
	projectile.freeze = true
	projectile.set_physics_process(false)
	return projectile


func _sync_physics() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _check_damage_boundaries() -> void:
	await _new_case("sphere_boundaries")
	var samples: Array[Array] = [
		["center", Vector3.ZERO, 900.0],
		["just_inside_15", Vector3(14.999, 0, 0), 900.0],
		["exact_15", Vector3(15, 0, 0), 900.0],
		["just_outside_15", Vector3(15.001, 0, 0), 750.0],
		["just_inside_25", Vector3(24.999, 0, 0), 750.0],
		["exact_25", Vector3(25, 0, 0), 750.0],
		["just_outside_25", Vector3(25.001, 0, 0), 0.0],
		["vertical_exact_15", Vector3(0, 15, 0), 900.0],
		["vertical_outer", Vector3(0, 15.001, 0), 750.0],
		["vertical_exact_25", Vector3(0, 25, 0), 750.0],
		["vertical_outside", Vector3(0, 25.001, 0), 0.0],
		["diagonal_exact_15", Vector3(12, 9, 0), 900.0],
		["diagonal_exact_25", Vector3(15, 20, 0), 750.0],
		["flat_near_vertical_far", Vector3(1, 26, 0), 0.0],
	]
	var targets: Array[Node3D] = []
	for sample: Array in samples:
		targets.append(_target(sample[1]))
	var projectile := _projectile()
	await _sync_physics()
	projectile.call("_explode")
	for index in samples.size():
		_assert(is_equal_approx(float(targets[index].get("health")), TARGET_HEALTH - float(samples[index][2])), "%s uses true spherical distance and the approved damage band" % samples[index][0])
	_assert(_explosions == [ORIGIN] and _legacy_explosions == 0, "EC-60E emits exactly its own blue-pulse event")
	projectile.call("_explode")
	_assert(_explosions.size() == 1, "repeating explosion before queued deletion cannot emit a second pulse")
	for index in samples.size():
		_assert(is_equal_approx(float(targets[index].get("health")), TARGET_HEALTH - float(samples[index][2])), "%s receives damage at most once after repeated explosion" % samples[index][0])


func _check_dense_cover() -> void:
	await _new_case("sixty_four_enemies_behind_wall")
	var wall := StaticBody3D.new()
	_box(wall, Vector3(12, 12, 1))
	_case.add_child(wall)
	wall.global_position = ORIGIN + Vector3(0, 0, -3)
	var targets: Array[Node3D] = []
	for index in 64:
		targets.append(_target(Vector3((index % 8 - 3.5) * 0.4, 0, -8.0 - (index / 8) * 0.4)))
	var projectile := _projectile()
	await _sync_physics()
	var query := PhysicsRayQueryParameters3D.create(ORIGIN, targets[0].global_position)
	query.collision_mask = 1
	var hit: Dictionary = _world.get_world_3d().direct_space_state.intersect_ray(query)
	_assert(not hit.is_empty() and hit.get("collider") == wall, "real physics verifies an opaque wall covers the dense enemy set")
	projectile.call("_explode")
	var damaged := 0
	for target: Node3D in targets:
		if is_equal_approx(float(target.get("health")), TARGET_HEALTH - 900.0):
			damaged += 1
	_assert(damaged == 64, "all 64 actual enemies behind cover receive 900 without the 32-result physics-query limit")


func _check_recipient_guards() -> void:
	await _new_case("recipient_guards")
	var range_target = _target(Vector3(0, 0, -5), true)
	_assert(range_target.is_in_group(&"range_target") and not range_target.is_in_group(&"enemy"), "fixture uses the actual passive range_target script and its distinct group")
	var duplicate = _target(Vector3(0, 0, -6), true)
	duplicate.add_to_group(&"enemy")
	var protected_player := _receiver(Vector3(0, 0, -1), [&"player", &"enemy", &"range_target"])
	var ordinary_cover := _receiver(Vector3(0, 0, -2), [])
	var bunker := _receiver(Vector3(0, 0, -8), [&"enemy", &"bunker"])
	var outside_bunker := _receiver(Vector3(0, 0, -26), [&"enemy", &"bunker"])
	var dead = _target(Vector3(0, 0, -7))
	dead.health = 0.0
	dead._dead = true
	var pending = _target(Vector3(0, 0, -9))
	var projectile := _projectile()
	await _sync_physics()
	pending.queue_free()
	var hp_before: float = _state.hp
	var armor_before: float = _state.armor
	projectile.call("_explode")
	_assert(range_target.health == TARGET_HEALTH - 900.0, "actual passive range target receives the same radial damage")
	_assert(duplicate.health == TARGET_HEALTH - 900.0, "a target in enemy and range_target groups is deduplicated")
	_assert(protected_player.amounts.is_empty() and _player_damage == 0 and _state.hp == hp_before and _state.armor == armor_before, "player group remains immune even when also listed as an enemy/target")
	_assert(ordinary_cover.amounts.is_empty(), "non-enemy damageable scenery is not a grenade recipient")
	_assert(bunker.amounts == [900.0] and bunker.heads == [false] and bunker.destroyed == 0, "bunker uses ordinary body damage without EC-40 destroy special kill")
	_assert(outside_bunker.amounts.is_empty() and outside_bunker.destroyed == 0, "EC-60E does not inherit EC-40's bonus bunker radius")
	_assert(dead.health == 0.0 and pending.health == TARGET_HEALTH, "dead and pending-deletion enemies receive no new grenade damage")


func _check_fuse() -> void:
	await _new_case("exact_three_second_fuse")
	var projectile := _projectile()
	projectile.call("_physics_process", 2.999)
	_assert(_explosions.is_empty(), "EC-60E does not explode before its three-second fuse")
	projectile.call("_physics_process", 0.001)
	_assert(_explosions == [ORIGIN] and projectile.is_queued_for_deletion(), "EC-60E explodes exactly when physics delta reaches three seconds")
	projectile.call("_physics_process", 10.0)
	projectile.call("_explode")
	_assert(_explosions.size() == 1, "expired fuse and repeated callbacks cannot explode twice")
	await _new_case("paused_physics_fuse")
	projectile = _projectile()
	projectile.set_physics_process(true)
	for frame in 30:
		await physics_frame
	var age_before_pause: float = float(projectile.get("_age"))
	paused = true
	for frame in 30:
		await process_frame
	_assert(is_equal_approx(float(projectile.get("_age")), age_before_pause) and _explosions.is_empty(), "SceneTree pause stops the physical grenade fuse")
	paused = false
	var remaining := 240
	while is_instance_valid(projectile) and not projectile.is_queued_for_deletion() and remaining > 0:
		await physics_frame
		remaining -= 1
	_assert(_explosions.size() == 1 and remaining > 0, "real physics resumes and produces one timed explosion")
	await _new_case("sleeping_rigid_body_fuse")
	projectile = _projectile()
	projectile.freeze = false
	projectile.gravity_scale = 0.0
	projectile.linear_velocity = Vector3.ZERO
	projectile.angular_velocity = Vector3.ZERO
	projectile.sleeping = true
	projectile.set_physics_process(true)
	remaining = 240
	while is_instance_valid(projectile) and not projectile.is_queued_for_deletion() and remaining > 0:
		await physics_frame
		remaining -= 1
	_assert(_explosions.size() == 1 and remaining > 0, "a sleeping landed RigidBody still completes its three-second fuse")


func _check_lethal_chain() -> void:
	await _new_case("real_enemy_death_chain")
	var inside = _target(Vector3(1, 0, 0))
	inside.health = 150.0
	var outer = _target(Vector3(20, 0, 0))
	outer.health = 750.0
	var outside = _target(Vector3(26, 0, 0))
	outside.health = 150.0
	var killed_ids: Array[int] = [inside.get_instance_id(), outer.get_instance_id()]
	var before: int = _state.kills
	var deaths_before := _deaths.size()
	var projectile := _projectile()
	await _sync_physics()
	projectile.call("_explode")
	_assert(inside._dead and outer._dead and not outside._dead and outside.health == 150.0, "real enemies die inside either damage band while outside enemy survives")
	_assert(_state.kills == before + 2 and _deaths.size() == deaths_before + 2 and _deaths.has(killed_ids[0]) and _deaths.has(killed_ids[1]), "production enemy_died bus increments GameState kills exactly once for each lethal recipient")
	projectile.call("_explode")
	_assert(_state.kills == before + 2 and _deaths.size() == deaths_before + 2, "repeated grenade explosion cannot double-count real kills")


func _on_exploded(position: Vector3) -> void:
	_explosions.append(position)


func _on_legacy_exploded(_position: Vector3) -> void:
	_legacy_explosions += 1


func _on_player_damaged(_part: StringName, _amount: float) -> void:
	_player_damage += 1


func _on_enemy_died(enemy: Node) -> void:
	_deaths.append(enemy.get_instance_id())


func _finish() -> void:
	print("EC60E_GRENADE COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
