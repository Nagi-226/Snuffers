## Actual Player damage/regen and Pickup paths; medicine is automatic below 20%.
extends SceneTree

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player: CharacterBody3D
var _state: Node
var _config: Node
var _events: Node
var _uses: Array[int] = []
var _health: Array[float] = []
var _messages: Array[String] = []
var _pickups: Array[int] = []
var _deaths := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _record_use(remaining: int) -> void:
	_uses.append(remaining)


func _record_health(_part: StringName, current: float, _maximum: float) -> void:
	_health.append(current)


func _record_death(_reason: StringName) -> void:
	_deaths += 1


func _record_message(message: String) -> void:
	_messages.append(message)


func _record_pickup(total: int) -> void:
	_pickups.append(total)


func _case(hp: float, medkits: int) -> void:
	_state.reset()
	_state.hp = hp
	_state.armor = 0.0
	_state.medkits = medkits
	_player.set("_armor_regen_wait", 0.0)
	_uses.clear()
	_health.clear()
	_messages.clear()
	_pickups.clear()
	_deaths = 0


func _run() -> void:
	create_timer(50.0, true).timeout.connect(_timeout)
	_state = root.get_node("GameState")
	_config = root.get_node("GameConfig")
	_events = root.get_node("Events")
	_state.reset()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_events.medkit_used.connect(_record_use)
	_events.player_health_changed.connect(_record_health)
	_events.game_over.connect(_record_death)
	_events.message_posted.connect(_record_message)
	_events.medkit_picked.connect(_record_pickup)
	var constants: Dictionary = _config.get_script().get_script_constant_map()
	_assert(constants.get("MEDKIT_AUTO_HEALTH_FRACTION") == 0.2, "Config declares the approved strict 20% automatic medicine threshold")
	_assert(not _player.get_script().get_script_constant_map().has("KEY_MEDKIT"), "Player has no manual medkit key binding")
	_check_damage_threshold()
	await _check_low_health_pickup()
	_check_passive_regen()
	_check_guards()
	_check_unbound_t()
	await _check_max_carry()
	_check_range_supplies()
	await _finish()


func _check_damage_threshold() -> void:
	_case(21.0, 2)
	_player._apply_damage(&"hp", 1.0)
	_assert(is_equal_approx(_state.hp, 20.0) and _state.medkits == 2 and _uses.is_empty(), "21 to exactly 20 HP does not consume a medkit")
	_player._apply_damage(&"hp", 0.001)
	_assert(_state.hp == _config.HEALTH_MAX and _state.medkits == 1, "20 to 19.999 HP immediately consumes exactly one medkit and restores full health")
	_assert(_uses == [1], "one automatic medkit publishes exactly one remaining-stock signal")
	_assert(_health.size() == 3 and is_equal_approx(_health[1], 19.999) and _health[2] == _config.HEALTH_MAX, "damage and automatic healing publish the real low-health then full-health states")
	for callback in 3:
		_player._use_medkit()
		_player._update_armor_regen(0.0)
	_assert(_state.medkits == 1 and _uses == [1], "repeated update callbacks at full health do not consume another medkit")


func _check_low_health_pickup() -> void:
	_case(10.0, 0)
	var pickup := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate() as Area3D
	pickup.kind = &"medkit"
	pickup.position = Vector3(1000, 0, 1000)
	_world.add_child(pickup)
	pickup.set_process(false)
	pickup.call("_on_body_entered", _player)
	_assert(_state.medkits == 1 and _state.hp == 10.0, "real low-health pickup adds one unit before the Player update")
	var message: String = _messages.back() if not _messages.is_empty() else ""
	_assert(message.contains("自动") and not message.contains("F 使用") and not message.contains("T 使用"), "medkit pickup describes automatic use without an obsolete manual-use instruction")
	_player._update_armor_regen(0.0)
	_assert(_state.medkits == 0 and _state.hp == _config.HEALTH_MAX and _uses == [0], "next real regen update consumes the low-health pickup and fills HP before the four-second wait")
	_assert(is_zero_approx(float(_player.get("_armor_regen_wait"))), "automatic medicine bypasses passive regeneration's waiting period")
	await process_frame


func _check_passive_regen() -> void:
	_case(100.0, 0)
	_player._apply_damage(&"hp", 90.0)
	_player._update_armor_regen(float(_config.ARMOR_REGEN_DELAY) - 0.001)
	_assert(_state.hp == 10.0 and _state.medkits == 0 and _uses.is_empty(), "no-stock low health preserves the existing four-second passive wait")
	_player.set("_armor_regen_wait", float(_config.ARMOR_REGEN_DELAY))
	_player._update_armor_regen(1.0)
	_assert(is_equal_approx(_state.hp, 10.0 + float(_config.HEALTH_REGEN_RATE)) and _state.medkits == 0, "without medicine the existing eight-HP-per-second passive regeneration continues")
	_assert(is_equal_approx(_state.armor, float(_config.ARMOR_REGEN_RATE)), "automatic medicine does not change the companion armor recharge")


func _check_guards() -> void:
	_case(10.0, 2)
	_player._apply_damage(&"hp", 10.0)
	_assert(_state.hp == 0.0 and _state.medkits == 2 and _uses.is_empty(), "lethal damage reaches zero without consuming medicine or reviving")
	_assert(_state.mission_phase == _state.MissionPhase.GAME_OVER and _deaths == 1, "lethal damage still publishes exactly one ordinary game over")
	_player._update_armor_regen(10.0)
	_assert(_state.hp == 0.0 and _state.medkits == 2, "game-over updates cannot restore health or consume medicine")
	_case(10.0, 1)
	paused = true
	_player._use_medkit()
	_player._update_armor_regen(0.0)
	paused = false
	_assert(_state.hp == 10.0 and _state.medkits == 1 and _uses.is_empty(), "paused callbacks cannot automatically consume medicine")
	for phase: int in [_state.MissionPhase.COMPLETED, _state.MissionPhase.GAME_OVER]:
		_case(10.0, 1)
		_state.mission_phase = phase
		_player._use_medkit()
		_player._update_armor_regen(0.0)
		_assert(_state.hp == 10.0 and _state.medkits == 1 and _uses.is_empty(), "ended phase %d blocks automatic medicine" % phase)
	_case(0.0, 1)
	_player._use_medkit()
	_assert(_state.hp == 0.0 and _state.medkits == 1, "the medkit helper independently rejects zero health")
	_case(10.0, 0)
	_player._use_medkit()
	_assert(_state.hp == 10.0 and _state.medkits == 0 and _uses.is_empty(), "empty automatic stock never goes negative")


func _check_unbound_t() -> void:
	for hp: float in [50.0, 10.0]:
		_case(hp, 1)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_T
		event.pressed = true
		_player._unhandled_input(event)
		_assert(_state.hp == hp and _state.medkits == 1 and _uses.is_empty(), "T at %s HP no longer manually uses medicine" % hp)


func _check_max_carry() -> void:
	_assert(_config.MEDKIT_MAX_CARRY == 50, "Config sets the approved medkit carry limit to fifty")
	_case(float(_config.HEALTH_MAX), 49)
	var accepted := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate() as Area3D
	accepted.kind = &"medkit"
	accepted.position = Vector3(1000, 0, 1000)
	_world.add_child(accepted)
	accepted.set_process(false)
	accepted.call("_on_body_entered", _player)
	_assert(_state.medkits == 50 and _pickups == [50] and accepted.is_queued_for_deletion(), "real pickup increases forty-nine to fifty and publishes medkit_picked(50)")
	var retained := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate() as Area3D
	retained.kind = &"medkit"
	retained.position = Vector3(1000, 0, 1000)
	_world.add_child(retained)
	retained.set_process(false)
	retained.call("_on_body_entered", _player)
	_assert(_state.medkits == 50 and _pickups == [50] and not retained.is_queued_for_deletion() and not retained.get("_collected"), "full stock refuses another pickup without exceeding fifty or deleting the supply")
	_state.hp = 21.0
	_player._apply_damage(&"hp", 2.0)
	_assert(_state.medkits == 49 and _uses == [49] and _state.hp == _config.HEALTH_MAX, "automatic use frees exactly one slot from a full fifty-medkit inventory")
	retained.call("_on_body_entered", _player)
	_assert(_state.medkits == 50 and _pickups == [50, 50] and retained.is_queued_for_deletion(), "the retained real supply refills the freed slot to fifty")
	await process_frame


func _check_range_supplies() -> void:
	_state.reset()
	var range_scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	_world.add_child(range_scene)
	var medkits: Array[Area3D] = []
	for node: Node in range_scene.find_children("*", "Area3D", true, false):
		if node.get_script() != null and node.get_script().resource_path == "res://scripts/levels/pickup.gd" and node.get("kind") == &"medkit":
			medkits.append(node as Area3D)
	_assert(medkits.size() >= 5, "actual weapons range provides at least five medkit pickups for testing")
	for pickup: Area3D in medkits:
		var visual := pickup.get_node_or_null("Visual")
		_assert(visual != null and not visual.find_children("*", "MeshInstance3D", true, false).is_empty(), "%s supply contains the actual medkit model" % pickup.name)
		var shapes := pickup.find_children("*", "CollisionShape3D", true, false)
		_assert(not shapes.is_empty() and (shapes[0] as CollisionShape3D).shape != null, "%s supply contains a real pickup trigger shape" % pickup.name)
	range_scene.queue_free()


func _finish() -> void:
	_events.medkit_used.disconnect(_record_use)
	_events.player_health_changed.disconnect(_record_health)
	_events.game_over.disconnect(_record_death)
	_events.message_posted.disconnect(_record_message)
	_events.medkit_picked.disconnect(_record_pickup)
	_world.queue_free()
	current_scene = null
	await process_frame
	print("AUTO_MEDKIT COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _timeout() -> void:
	paused = false
	print("FAIL: AUTO_MEDKIT timed out before completion")
	quit(1)
