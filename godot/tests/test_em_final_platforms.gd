extends SceneTree

var _failures := 0
var _player: CharacterBody3D
var _state
var _world: Node3D
var _sections: Dictionary = {}

class DamageTarget extends StaticBody3D:
	var health := 100000.0
	var hits: Array[float] = []
	var _cached_can_see := false
	var alerted := false
	func take_damage(amount: float, _head: bool) -> void:
		hits.append(amount)
		health -= amount


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	create_timer(30.0).timeout.connect(_timeout)
	for weapon_id in [&"em127m", &"em120r"]:
		_assert(ResourceLoader.exists("res://scenes/weapons/%s.tscn" % weapon_id), "%s has its gameplay scene" % weapon_id)
		_assert(ResourceLoader.exists("res://scenes/weapons/%s.tres" % weapon_id), "%s has its data resource" % weapon_id)
	_assert(ResourceLoader.exists("res://scenes/weapons/ec120_projectile.tscn"), "EC-120 has a modeled missile gameplay scene")
	if _failures:
		quit(1)
		return
	_state = root.get_node("GameState")
	_state.reset()
	var ec120_data = load("res://scenes/weapons/em120r.tres")
	_assert(ec120_data.reserve_size == 150, "Longbow data resource defaults to 150 EC-120 reserve missiles")
	ec120_data.sync_from_config()
	_assert(ec120_data.reserve_size == 150, "Longbow synchronized data uses 150 EC-120 reserve missiles")
	root.size = Vector2i(1920, 1080)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_player.global_position = Vector3(0, 100, 0)
	_player.set_physics_process(false)
	# The fixture calls player methods directly; native capture warp/mouse motion
	# must not change the fixed aim pose between registering a target and firing.
	_player.set_process_unhandled_input(false)
	var hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	_world.add_child(hud)
	for id in _state.weapon_unlocked:
		_state.weapon_unlocked[id] = true
	await process_frame
	_assert(_player._missile_tactical != null and _player._missile_scope != null, "Longbow scope initializes without script errors")
	if _player._missile_tactical == null or _player._missile_scope == null:
		_world.queue_free()
		quit(1)
		return
	_assert(_state.em127m_mag == 500 and _state.em120r_mag == 10, "new magazines initialize to 500 and 10")
	_assert(_state.em120r_reserve == 150, "EC-120 reserve initializes to the approved 150 missiles")
	_assert(_state.fire_modes[&"em127m"] == &"auto" and _state.fire_modes[&"em120r"] == &"semi", "Thunder starts auto and Longbow stays semi-auto")
	var thunder = _player.get_node("Camera3D/WeaponMount/Em127m")
	var launcher = _player.get_node("Camera3D/WeaponMount/Em120r")
	thunder.set_physics_process(false)
	launcher.set_physics_process(false)
	_assert(thunder.weapon_data.mag_size == 500 and thunder.weapon_data.damage_body == 450.0 and is_equal_approx(thunder.weapon_data.fire_interval, 60.0 / 700.0), "Thunder data is 500 rounds, 450 damage and 700 RPM")
	_assert(launcher.weapon_data.kind == WeaponData.Kind.PROJECTILE and launcher.weapon_data.mag_size == 10 and launcher.weapon_data.damage_body == 1200.0, "Longbow is a 10-round 1200-damage projectile weapon")
	_assert(&"em127m" in GameConfig.WEAPON_CATEGORIES[4].weapons and &"em120r" in GameConfig.WEAPON_CATEGORIES[5].weapons, "Thunder and Longbow are selectable in their weapon categories")
	var icons = load("res://scripts/ui/weapon_icon.gd").ICONS
	_assert(icons.has(&"em127m") and icons.has(&"em120r"), "both new weapons have explicit HUD icons rather than the rifle fallback")
	if icons.has(&"em127m") and icons.has(&"em120r"):
		_assert(icons[&"em127m"] != icons[&"em120r"] and icons[&"em127m"] != icons[&"rifle"] and icons[&"em120r"] != icons[&"rifle"], "new HUD icons use distinct textures")
	for id in [&"em127m", &"em120r"]:
		_player._switch_weapon(id)
		hud._refresh_ammo()
		var ammo = hud._weapon_ammo
		_assert(ammo.weapon_name.contains("雷霆" if id == &"em127m" else "长弓") and ammo.ammo_type == ("EC-127" if id == &"em127m" else "EC-120"), "%s HUD shows the requested weapon name and ammunition type" % id)
		_assert(ammo.mag == (500 if id == &"em127m" else 10), "%s HUD shows its own magazine" % id)
		if id == &"em120r":
			_assert(ammo.reserve == 150, "Longbow HUD shows its separate 150-missile reserve")
	_state.em120r_mag = 0
	_player._switch_weapon(&"em120r")
	launcher._start_reload()
	await create_timer(launcher.weapon_data.reload_time + 0.1).timeout
	_assert(_state.em120r_mag == 10 and _state.em120r_reserve == 140 and not launcher._is_reloading, "real timed Longbow reload transfers ten missiles from the reserve")
	_assert(hud._weapon_ammo.mag == 10 and hud._weapon_ammo.reserve == 140, "Longbow reload immediately updates magazine and reserve in the HUD")
	_state.em120r_mag = 0
	_state.em120r_reserve = 7
	launcher._on_weapon_reloaded(&"em120r")
	_assert(_state.em120r_mag == 7 and _state.em120r_reserve == 0, "last partial Longbow reload transfers only the seven remaining missiles")
	_assert(hud._weapon_ammo.mag == 7 and hud._weapon_ammo.reserve == 0, "partial Longbow reload updates the HUD without creating ammo")
	_state.em120r_mag = 10
	_state.em120r_reserve = 150
	root.get_node("Events").ammo_changed.emit(&"em120r", 10, 150)
	_player._switch_weapon(&"em127m")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em127m"] == &"semi", "Thunder X selects semi-auto")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em127m"] == &"auto", "Thunder X returns to auto without a burst mode")
	var target := _target(Vector3(0, 102, -30))
	await physics_frame
	await physics_frame
	thunder.weapon_data.spread_hip = 0.0
	thunder.weapon_data.spread_aim = 0.0
	var before_hit: Dictionary = thunder._cast_spread_ray()
	print("THUNDER_FIXTURE_BEFORE: mouse=", Input.mouse_mode,
		" player_rotation=", _player.rotation, " camera_rotation=", _player._camera.rotation,
		" pitch=", _player._pitch, " weapon_origin=", thunder.global_position,
		" weapon_forward=", -thunder.global_basis.z, " target=", target.global_position,
		" hits=", target.hits, " ammo=", _state.em127m_mag,
		" ray_hit=", before_hit.get("collider"), " ray_position=", before_hit.get("position"))
	var body_fired: bool = thunder._fire()
	var after_hit: Dictionary = thunder._cast_spread_ray()
	print("THUNDER_FIXTURE_AFTER: fired=", body_fired,
		" player_rotation=", _player.rotation, " camera_rotation=", _player._camera.rotation,
		" pitch=", _player._pitch, " hits=", target.hits, " ammo=", _state.em127m_mag,
		" ray_hit=", after_hit.get("collider"), " ray_position=", after_hit.get("position"))
	_assert(target.hits.size() == 1 and target.hits[0] == 450.0 and _state.em127m_mag == 499, "real Thunder body hit deals exactly 450 and consumes one round")
	_state.em127m_mag = 0
	_state.magnum_reserve = 1500
	thunder._on_weapon_reloaded(&"em127m")
	_assert(_state.em127m_mag == 500 and _state.magnum_reserve == 1000, "Thunder reload consumes the existing shared EC-127 reserve")
	_state.em127g_mag = 0
	_player.get_node("Camera3D/WeaponMount/Em127g")._on_weapon_reloaded(&"em127g")
	_assert(_state.em127g_mag == 30 and _state.magnum_reserve == 970, "Gauss sees the same reserve already consumed by Thunder")
	_state.em127m_mag = 500
	thunder._camera_kick = 0.0
	thunder._fire_cooldown = 0.0
	thunder._trigger_held = true
	var fired := [0]
	var record = func(id: StringName):
		if id == &"em127m":
			fired[0] += 1
	var events = root.get_node("Events")
	events.weapon_fired.connect(record)
	for frame in 600:
		thunder._tick_weapon(1.0 / 60.0)
	thunder._trigger_held = false
	events.weapon_fired.disconnect(record)
	_assert(absi(fired[0] - 117) <= 1, "Thunder sustains 700 RPM at 60Hz over ten seconds (got %d shots)" % fired[0])
	thunder._camera_kick = 0.0
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	await _scope_checks(&"em127m", thunder)
	if not _section_completed(&"em127m_scope"):
		return
	_assert(_player._dmr_tactical._range_text != "RNG --- M", "Thunder full-screen scope retains rangefinding")
	_player._set_aiming(false)
	_player._switch_weapon(&"em120r")
	var initial_mode: StringName = _state.em120r_guidance_mode
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em120r"] == &"semi" and _state.em120r_guidance_mode != initial_mode, "Longbow X changes guidance while keeping semi-auto")
	_assert(hud._weapon_ammo.mode_tag.contains("追踪"), "Longbow HUD immediately shows autonomous guidance after X")
	_player._cycle_fire_mode()
	_assert(hud._weapon_ammo.mode_tag.contains("激光") and _state.fire_modes[&"em120r"] == &"semi", "Longbow HUD immediately shows laser guidance while retaining semi-auto")
	_player._cycle_fire_mode()
	await _scope_checks(&"em120r", launcher)
	if not _section_completed(&"em120r_scope"):
		return
	_assert(_player._missile_scope_material.shader.resource_path != _player._dmr_scope_material.shader.resource_path, "Longbow has its own full-screen reticle shader")
	await _lock_checks(target)
	if not _section_completed(&"lock"):
		return
	_player._set_aiming(false)
	_assert(_state.em120r_locked_target == null, "releasing ADS immediately clears the unfired lock")
	_player._set_aiming(true)
	for frame in 30:
		_player._process(1.0 / 60.0)
	_player._missile_tactical._refresh_targets()
	_player._missile_tactical._update_lock(0.01)
	_player._missile_tactical._update_lock(1.01)
	_player._switch_weapon(&"em127m")
	_assert(_state.em120r_locked_target == null, "switching weapons clears the unfired Longbow lock")
	await _near_wall_checks(launcher)
	if not _section_completed(&"near_wall"):
		return
	_world.queue_free()
	await process_frame
	print("test_em_final_platforms: %d assertion(s) failed" % _failures)
	quit(1 if _failures else 0)


func _timeout() -> void:
	push_error("test_em_final_platforms timed out before completing assertions")
	quit(1)


func _section_completed(section: StringName) -> bool:
	if _sections.has(section):
		print("COMPLETED: ", section)
		return true
	_assert(false, "%s tests did not finish; refusing a partial result" % section)
	quit(1)
	return false


func _target(at: Vector3) -> DamageTarget:
	var target := DamageTarget.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	collision.shape = box
	target.add_child(collision)
	_world.add_child(target)
	target.global_position = at
	target.add_to_group(&"enemy")
	return target


func _scope_checks(id: StringName, weapon: Node3D) -> void:
	_player._set_aiming(false)
	_player._switch_weapon(id)
	_player._set_aiming(true)
	for frame in 30:
		_player._process(1.0 / 60.0)
		weapon._process(1.0 / 60.0)
	var scope: Control = _player._missile_scope if id == &"em120r" else _player._dmr_scope
	var tactical: Control = _player._missile_tactical if id == &"em120r" else _player._dmr_tactical
	_assert(scope.visible and tactical.visible and not weapon._view_model.visible, "%s uses the full-screen scope and hides the weapon model" % id)
	_assert(is_equal_approx(_player._camera.fov, 17.5), "%s starts at 16x" % id)
	_player._adjust_em86s_zoom(1)
	_player._process(1.0 / 60.0)
	_assert(is_equal_approx(_player._camera.fov, 8.75), "%s wheel selects 32x" % id)
	_player._adjust_em86s_zoom(1)
	_player._process(1.0 / 60.0)
	_assert(is_equal_approx(_player._camera.fov, 4.375), "%s wheel selects 64x" % id)
	_player._adjust_em86s_zoom(1)
	_assert(_player._em86s_zoom_index == 2, "%s clamps at 64x" % id)
	_player._set_aiming(false)
	_player._set_aiming(true)
	for frame in 30:
		_player._process(1.0 / 60.0)
	_assert(is_equal_approx(_player._camera.fov, 17.5), "%s fresh ADS resets to 16x" % id)
	tactical._refresh_range()
	tactical._refresh_targets()
	_sections[StringName(id + "_scope")] = true


func _lock_checks(first: DamageTarget) -> void:
	var overlay = _player._missile_tactical
	overlay.set_process(false)
	_player._camera.look_at(first.global_position)
	await physics_frame
	overlay.clear_lock()
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	overlay._update_lock(0.6)
	_assert(_state.em120r_locked_target == null, "Longbow cannot lock before one second")
	var second := _target(Vector3(10, 102, -30))
	_player._camera.look_at(second.global_position)
	await physics_frame
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	overlay._update_lock(0.6)
	_assert(_state.em120r_locked_target == null, "partial acquisition of two targets cannot add up to a lock")
	overlay._update_lock(0.41)
	_assert(_state.em120r_locked_target == second, "continuous selection for one second locks the selected target")
	second.health = 0.0
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	_assert(_state.em120r_locked_target == null, "dead target loses the unfired lock")
	_player._camera.look_at(first.global_position)
	await physics_frame
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	overlay._update_lock(1.01)
	_assert(_state.em120r_locked_target == first, "a new live target can be acquired after the previous target dies")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 1)
	collision.shape = box
	wall.add_child(collision)
	_world.add_child(wall)
	wall.global_position = Vector3(0, 102, -15)
	await physics_frame
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	_assert(_state.em120r_locked_target == null, "wall occlusion clears acquisition even though explosion damage ignores cover")
	wall.queue_free()
	await physics_frame
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	overlay._update_lock(1.01)
	_player._cycle_fire_mode()
	_assert(_state.em120r_locked_target == null and _state.fire_modes[&"em120r"] == &"semi", "changing guidance mode clears the unfired lock")
	_player._cycle_fire_mode()
	overlay._refresh_targets()
	overlay._update_lock(0.01)
	overlay._update_lock(1.01)
	var launcher = _player.get_node("Camera3D/WeaponMount/Em120r")
	launcher._fire_cooldown = 0.0
	var fired: bool = launcher._fire()
	_assert(fired and _state.em120r_locked_target == null, "real homing launch consumes the scope lock so the next target can be acquired")
	_sections[&"lock"] = true


func _near_wall_checks(launcher: Node3D) -> void:
	_player._set_aiming(false)
	_player._switch_weapon(&"em120r")
	if _state.em120r_guidance_mode != &"laser":
		_player._cycle_fire_mode()
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	_player._process(1.0 / 60.0)
	var camera := _player._camera as Camera3D
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.05)
	collision.shape = box
	wall.add_child(collision)
	_world.add_child(wall)
	wall.global_position = camera.global_position - camera.global_basis.z * 0.3
	await physics_frame
	await physics_frame
	_player._process(1.0 / 60.0)
	_player._update_ec120_aim()
	_assert(_state.em120r_aim_origin.is_equal_approx(camera.global_position), "guidance publishes the actual camera origin for launch clearance")
	var explosions: Array[Vector3] = []
	var record = func(at: Vector3): explosions.append(at)
	var events = root.get_node("Events")
	events.rpg_exploded.connect(record)
	_state.em120r_mag = 10
	launcher._fire_cooldown = 0.0
	var fired: bool = launcher._fire()
	events.rpg_exploded.disconnect(record)
	_assert(fired and explosions.size() == 1 and explosions[0].distance_to(camera.global_position) < 0.4, "wall 0.3m ahead of the player detonates the shot immediately instead of spawning it beyond cover")
	wall.queue_free()
	await process_frame
	# A same-frame selection must publish the new camera pose before any firing.
	_player._switch_weapon(&"em127m")
	_player.global_position += Vector3(10, 0, 10)
	var new_camera_origin := camera.global_position
	var next_wall := StaticBody3D.new()
	var next_collision := CollisionShape3D.new()
	next_collision.shape = box.duplicate()
	next_wall.add_child(next_collision)
	_world.add_child(next_wall)
	next_wall.global_position = new_camera_origin - camera.global_basis.z * 0.3
	await physics_frame
	await physics_frame
	explosions.clear()
	events.rpg_exploded.connect(record)
	launcher._fire_cooldown = 0.0
	_player._switch_weapon(&"em120r")
	_assert(_state.em120r_aim_origin.is_equal_approx(new_camera_origin), "same-frame Longbow selection publishes the moved camera origin")
	var first_shot: bool = launcher._fire()
	events.rpg_exploded.disconnect(record)
	_assert(first_shot and explosions.size() == 1 and explosions[0].distance_to(new_camera_origin) < 0.4, "the first shot immediately after selecting Longbow cannot spawn beyond a nearby wall using stale guidance")
	next_wall.queue_free()
	await process_frame
	_sections[&"near_wall"] = true
