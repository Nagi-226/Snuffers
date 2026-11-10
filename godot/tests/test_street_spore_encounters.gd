extends SceneTree

const SPORE_NAMES := ["Spore_WA", "Spore_EA", "Spore_GY", "Spore_North"]

var _failures := 0
var _assertions := 0
var _scene: Node3D
var _player: CharacterBody3D
var _state: Node
var _damage: Array[float] = []
var _deaths: Array[String] = []


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
	_state.player_position = _player.global_position
	var street := _scene.get_node("StreetTest")
	var spores: Array = []
	var infantry := 0
	for enemy in get_nodes_in_group(&"enemy"):
		if enemy.get("enemy_kind") == &"spore_husk":
			spores.append(enemy)
		else:
			infantry += 1
			enemy.set_physics_process(false)
	_assert(spores.size() == 4, "first street contains four real spore entities")
	_assert(infantry == 14, "all fourteen existing host infantry remain in the first street")
	for expected in SPORE_NAMES:
		_assert(street.has_node(NodePath(expected)), "named encounter exists: " + expected)
	var gate := street.get_node("SceneGate/Link_BGate_E") as Node3D
	_assert(gate.get("requires_key") and gate.get("target_scene") == "res://scenes/levels/district_b.tscn", "existing locked district transition remains connected")
	_assert(_state.intel_total == 3 and _state.mission_points.has("GateKeyPickup"), "existing key and three-terminal mission remain registered")
	for frame in 90:
		await physics_frame
	for spore in spores:
		_assert(spore.get_state_name() == &"DORMANT", "%s remains dormant at the player spawn" % spore.name)
		_assert(spore.is_on_floor(), "%s settles on the real street ground" % spore.name)
		_assert(spore.health == root.get_node("GameConfig").SPORE_HUSK_HP, "%s uses existing health config" % spore.name)
		_assert(spore._animation_player != null and spore._animation_player.has_animation(&"crawl") and spore._animation_player.has_animation(&"leap") and spore._animation_player.has_animation(&"death"), "%s retains the animated spore model" % spore.name)
		_assert(Vector2(spore.global_position.x, spore.global_position.z).distance_to(Vector2(_player.global_position.x, _player.global_position.z)) > 12.0, "%s is outside the spawn alert radius" % spore.name)
		_assert(spore.global_position.distance_to(gate.global_position) > 5.0, "%s avoids the transition doorway" % spore.name)
		var shape := spore.get_node("CollisionShape3D") as CollisionShape3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform.translated(Vector3(0, 0.04, 0))
		query.exclude = [spore.get_rid()]
		query.collide_with_areas = false
		_assert(spore.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "%s is not embedded in walls or props" % spore.name)
		spore.set_physics_process(false)
	if spores.is_empty():
		await _finish()
		return

	root.get_node("Events").player_damaged.connect(_on_damage)
	root.get_node("Events").enemy_died.connect(_on_death)
	for spore in spores:
		var original_position: Vector3 = spore.global_position
		var approach := _approach_point(spore)
		_assert(approach != Vector3.ZERO, "%s has an unobstructed local approach" % spore.name)
		if approach == Vector3.ZERO:
			continue
		_player.global_position = approach
		_state.player_position = approach
		for frame in 3:
			await physics_frame
		spore.set_physics_process(true)
		_damage.clear()
		var leaped := false
		var alerted := false
		for frame in 180:
			await physics_frame
			alerted = alerted or spore.alerted
			leaped = leaped or spore.get_state_name() == &"LEAP"
			if not _damage.is_empty():
				break
		_assert(alerted, "%s naturally detects the nearby visible player" % spore.name)
		_assert(leaped, "%s naturally performs a physical leap" % spore.name)
		_assert(spore.global_position.distance_to(original_position) > 0.5, "%s physically advances during the encounter" % spore.name)
		_assert(_damage.size() == 1 and is_equal_approx(_damage[0], root.get_node("GameConfig").SPORE_HUSK_DAMAGE), "%s deals one configured attack hit" % spore.name)
		spore.set_physics_process(false)
		var survivor_health: float = spore.health - 1.0
		_assert(not spore.take_damage(1.0, false) and is_equal_approx(spore.health, survivor_health), "%s survives nonfatal damage" % spore.name)
		var link = gate
		var snapshot: Array = link._capture_enemies()
		var recorded := false
		for record in snapshot:
			if record.name == String(spore.name):
				recorded = is_equal_approx(record.health, survivor_health) and record.pos.is_equal_approx(spore.global_position)
		_assert(recorded, "%s participates in the existing scene-return snapshot" % spore.name)
		var saved_position: Vector3 = spore.global_position
		spore.global_position += Vector3(1, 0, 0)
		spore.health = 1.0
		link._restore_enemies()
		_assert(spore.global_position.is_equal_approx(saved_position) and is_equal_approx(spore.health, survivor_health), "%s position and wounded health are restored by the actual scene-return path" % spore.name)
		var dead_name := String(spore.name)
		_assert(spore.take_damage(survivor_health, false), "%s accepts fatal weapon-style damage" % spore.name)
		_assert(spore._dead and not spore.is_in_group(&"enemy") and spore.collision_layer == 0 and _deaths.has(String(spore.name)), "%s emits death and stops blocking movement immediately" % spore.name)
		for frame in 240:
			if not is_instance_valid(spore):
				break
			await physics_frame
		_assert(not is_instance_valid(spore), "dead spore is removed after its death animation")
		link._capture_enemies()
		var respawn := (load("res://scenes/enemies/spore_husk.tscn") as PackedScene).instantiate() as CharacterBody3D
		respawn.name = dead_name
		respawn.position = original_position
		street.add_child(respawn)
		respawn.set_physics_process(false)
		link._restore_enemies()
		await process_frame
		_assert(not is_instance_valid(respawn), "%s does not respawn when the death snapshot is restored" % dead_name)
	root.get_node("Events").player_damaged.disconnect(_on_damage)
	root.get_node("Events").enemy_died.disconnect(_on_death)
	await _finish()


func _approach_point(spore: Node3D) -> Vector3:
	for distance in [3.0, 2.3]:
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var candidate: Vector3 = spore.global_position + direction * distance
			var query := PhysicsRayQueryParameters3D.create(spore.global_position + Vector3(0, 0.4, 0), candidate + Vector3(0, 0.4, 0))
			query.exclude = [spore.get_rid(), _player.get_rid()]
			if spore.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				return candidate
	return Vector3.ZERO


func _on_damage(_part: StringName, amount: float) -> void:
	_damage.append(amount)


func _on_death(enemy: Node3D) -> void:
	_deaths.append(String(enemy.name))


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _timeout() -> void:
	push_error("street spore test timed out")
	quit(1)


func _finish() -> void:
	_scene.queue_free()
	await process_frame
	print("STREET_SPORE assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
