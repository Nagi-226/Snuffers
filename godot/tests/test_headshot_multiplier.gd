## All hitscan weapons: actual rays, ordinary/sniper head ratios and real hitboxes.
extends SceneTree

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")
const NEW_WEAPONS := {&"sig516": 45.0, &"sr25": 105.0, &"m700": 140.0}
const PROJECTILE_IDS := [&"em40t1", &"em120r"]

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player
var _state
var _weapons: Array = []


class DamageTarget extends StaticBody3D:
	var amounts: Array[float] = []
	var heads: Array[bool] = []
	var health := 1000000.0
	var _dead := false

	func take_damage(amount: float, head: bool) -> void:
		amounts.append(amount)
		heads.append(head)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(75.0).timeout.connect(func() -> void:
		push_error("all weapon headshot test timed out")
		quit(1))
	_state = root.get_node("GameState")
	_state.reset()
	for id: StringName in NEW_WEAPONS:
		var path := "res://scenes/weapons/%s.tres" % id
		_assert(ResourceLoader.exists(path), "%s has its own approved weapon data" % id)
		if ResourceLoader.exists(path):
			var data = load(path).duplicate()
			data.sync_from_config()
			_assert(is_equal_approx(data.damage_body, NEW_WEAPONS[id]), "%s retains the approved body damage %s" % [id, NEW_WEAPONS[id]])
	for file: String in DirAccess.get_files_at("res://scenes/weapons"):
		if not file.ends_with(".tres"):
			continue
		var data = load("res://scenes/weapons/" + file).duplicate()
		if not data.has_method("sync_from_config"):
			continue
		data.sync_from_config()
		if data.kind == 0 and data.weapon_id not in PROJECTILE_IDS:
			_assert(is_equal_approx(data.headshot_factor, 3.0), "%s runtime WeaponData has the universal three-times head multiplier" % data.weapon_id)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0, 100, 0)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	for weapon in _player.get_node("Camera3D/WeaponMount").get_children():
		weapon.set_process(false)
		weapon.set_physics_process(false)
		weapon.set_process_unhandled_input(false)
		if not _has_property(weapon, "weapon_data") or weapon.weapon_data == null or weapon.weapon_data.kind != 0 or weapon.weapon_data.weapon_id in PROJECTILE_IDS:
			continue
		weapon.weapon_data = weapon.weapon_data.duplicate()
		weapon.weapon_data.spread_hip = 0.0
		weapon.weapon_data.spread_prone = 0.0
		weapon.weapon_data.spread_aim = 0.0
		_weapons.append(weapon)
	_assert(_weapons.size() >= 20, "all existing and three new hitscan platforms participate in real-ray headshot verification")
	for new_id: StringName in NEW_WEAPONS:
		var mounted := false
		for weapon in _weapons:
			mounted = mounted or weapon.weapon_data.weapon_id == new_id
		_assert(mounted, "%s new hitscan controller is tested through the actual Player mount" % new_id)
	for weapon in _weapons:
		await _check_weapon(weapon)
	await _check_real_hitboxes()
	_world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	print("HEADSHOT_MULTIPLIER assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _check_weapon(weapon) -> void:
	var id: StringName = weapon.weapon_data.weapon_id
	_state.weapon_unlocked[id] = true
	_player._switch_weapon(id)
	_state.fire_modes[id] = &"semi"
	var target := DamageTarget.new()
	target.add_to_group(&"enemy")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.2)
	shape.shape = box
	target.add_child(shape)
	_world.add_child(target)
	for sniper: bool in [false, true]:
		if sniper:
			target.add_to_group(&"sniper")
		else:
			target.remove_from_group(&"sniper")
		var body_damage := await _record_shot(weapon, target, false)
		var head_damage := await _record_shot(weapon, target, true)
		print("HEADSHOT_RAY id=", id, " sniper=", sniper, " body=", body_damage, " head=", head_damage)
		_assert(body_damage > 0.0 and is_equal_approx(head_damage, body_damage * 3.0), "%s actual %s head damage is exactly three times its body hit" % [id, "sniper" if sniper else "ordinary"])
	if id == &"em127g":
		weapon._charged_shot = true
		var body_damage := await _record_shot(weapon, target, false)
		var head_damage := await _record_shot(weapon, target, true)
		_assert(is_equal_approx(body_damage, root.get_node("GameConfig").EM127G_CHARGED_DAMAGE_BODY) and is_equal_approx(head_damage, body_damage * 3.0), "fully charged Gauss actual head ray retains charged body damage and applies the same triple multiplier")
		weapon._charged_shot = false
	target.queue_free()
	await process_frame


func _record_shot(weapon, target: DamageTarget, head: bool) -> float:
	_prepare_round(weapon)
	target.set_meta(&"hit_part", &"head" if head else &"body")
	target.global_position = weapon.global_position - weapon.global_basis.z * 1.5
	await physics_frame
	await physics_frame
	var before := target.amounts.size()
	var fired: bool = weapon._fire()
	var expected_count: int = weapon.weapon_data.pellet_count
	_assert(fired and target.amounts.size() == before + expected_count, "%s actual ray delivers every fired pellet to the physical %s collider" % [weapon.weapon_data.weapon_id, "head" if head else "body"])
	var damage := 0.0
	var flags_match := true
	for index in range(before, target.amounts.size()):
		damage += target.amounts[index]
		flags_match = flags_match and target.heads[index] == head
	_assert(flags_match and target.amounts.size() > before, "%s forwards the actual head marker to its damage receiver" % weapon.weapon_data.weapon_id)
	return damage


func _prepare_round(weapon) -> void:
	var id: StringName = weapon.weapon_data.weapon_id
	_state.set(String(id) + "_mag", maxi(2, weapon.weapon_data.mag_size - 1))
	if _state.weapon_chambered.has(id):
		_state.weapon_chambered[id] = true
	weapon._fire_cooldown = 0.0
	if _has_property(weapon, "_pump_left"):
		weapon._pump_left = 0.0
	if _has_property(weapon, "_bolt_left"):
		weapon._bolt_left = 0.0


func _check_real_hitboxes() -> void:
	var rifle = _player.get_node("Camera3D/WeaponMount/Rifle")
	_player._switch_weapon(&"rifle")
	for path: String in ["res://scenes/enemies/infantry.tscn", "res://scenes/enemies/sniper.tscn", "res://scenes/enemies/hulking_host.tscn"]:
		var actor = (load(path) as PackedScene).instantiate()
		_world.add_child(actor)
		actor.set_physics_process(false)
		actor.health = 1000000.0
		var marker := actor.get_node("HeadHitbox") as Area3D
		_assert(HitSolver.is_headshot(marker) and HitSolver.find_damageable(marker) == actor, path + " exposes a real head hitbox that resolves to its actor")
		var damages: Array[float] = []
		for head: bool in [false, true]:
			_prepare_round(rifle)
			# Earlier real shots accumulate camera recoil despite the frozen Player
			# process. Start each anatomical ray horizontally, as the Gauss fixture
			# does, so its rising line cannot enter the body below the forehead.
			_player._pitch = 0.0
			_player._camera.rotation = Vector3.ZERO
			rifle.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 100, 0))
			var head_shape := marker.get_node("CollisionShape3D") as CollisionShape3D
			var head_radius: float = (head_shape.shape as SphereShape3D).radius
			# Body capsules overlap the lower head sphere. Aim at the exposed upper
			# forehead rather than expecting the head center to precede the body.
			var anchor: Vector3 = head_shape.to_global(Vector3(0, head_radius * 0.85, 0)) if head else (actor.get_node("CollisionShape3D") as Node3D).global_position
			actor.global_position += rifle.global_position - rifle.global_basis.z * 1.5 - anchor
			await physics_frame
			await physics_frame
			await process_frame
			var query := PhysicsRayQueryParameters3D.create(rifle.global_position, rifle.global_position - rifle.global_basis.z * 3.0)
			query.collide_with_areas = true
			query.exclude = HitSolver.collect_owner_rids(rifle)
			var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
			print("HEADSHOT_REAL_HITBOX path=", path, " head=", head, " collider=", str(hit.get("collider", null)), " position=", hit.get("position"), " head_center=", marker.global_position, " ray_origin=", query.from)
			_assert(not hit.is_empty() and HitSolver.find_damageable(hit.collider) == actor and HitSolver.is_headshot(hit.collider) == head, "%s real physics selects the intended %s hitbox" % [path, "head" if head else "body"])
			var before: float = actor.health
			rifle._fire()
			damages.append(before - actor.health)
		_assert(damages[0] > 0.0 and is_equal_approx(damages[1], damages[0] * 3.0), path + " receives triple head damage through its production take_damage method")
		actor.queue_free()
		await process_frame


func _has_property(object: Object, name: String) -> bool:
	for property in object.get_property_list():
		if property.name == name:
			return true
	return false


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
