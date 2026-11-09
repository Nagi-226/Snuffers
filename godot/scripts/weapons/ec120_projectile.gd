## EC-120：电磁冷推出筒，再点火制导。爆炸只结算一次，不另叠直击伤害。
extends Node3D

var _velocity := Vector3.ZERO
var _excludes: Array[RID] = []
var _data: WeaponData
var _traveled := 0.0
var _exploded := false
var _engine_ignited := false
var _guidance_mode: StringName = &"laser"
var _locked_target: Node3D
var _aim_point := Vector3.ZERO
var _engine_flame: MeshInstance3D
var _engine_light: OmniLight3D


func _ready() -> void:
	_build_engine_visuals()
	Events.ec120_aim_changed.connect(_on_aim_changed)


func _exit_tree() -> void:
	Events.ec120_aim_changed.disconnect(_on_aim_changed)


func setup(direction: Vector3, excludes: Array[RID], data: WeaponData,
		mode: StringName = &"laser", target: Node3D = null) -> void:
	if data == null or direction.length_squared() <= 0.000001 or mode not in [&"laser", &"homing"]:
		push_error("EC-120 缺少有效发射方向或武器数据")
		queue_free()
		return
	_data = data
	_excludes = excludes
	_guidance_mode = mode
	_locked_target = target if mode == &"homing" else null
	_velocity = direction.normalized() * GameConfig.EM120R_EJECT_SPEED
	_aim_point = global_position + direction.normalized() * data.projectile_max_range
	if mode == &"laser" and GameState.em120r_aim_point != Vector3.ZERO:
		_aim_point = GameState.em120r_aim_point
	_face_velocity()


func _on_aim_changed(aim_point: Vector3) -> void:
	if _guidance_mode == &"laser":
		_aim_point = aim_point


func _physics_process(delta: float) -> void:
	if _exploded or _data == null:
		return
	var remaining := delta
	if not _engine_ignited:
		var to_ignition := maxf(GameConfig.EM120R_IGNITION_DISTANCE - _traveled, 0.0)
		var eject_time := minf(remaining, to_ignition / GameConfig.EM120R_EJECT_SPEED)
		if eject_time > 0.0 and not _advance(eject_time):
			return
		remaining -= eject_time
		if _traveled + 0.000001 < GameConfig.EM120R_IGNITION_DISTANCE:
			return
		_engine_ignited = true
		_velocity = _velocity.normalized() * _data.projectile_speed
		_engine_flame.visible = true
		_engine_light.visible = true
	if remaining > 0.0:
		_steer(remaining)
		_advance(remaining)


func _steer(delta: float) -> void:
	var point := _aim_point
	if _guidance_mode == &"homing":
		if not _target_alive(_locked_target):
			_locked_target = null
			return # 目标丢失后沿当前速度继续，不改追踪其他目标。
		point = _locked_target.global_position
		for shape in _locked_target.find_children("*", "CollisionShape3D", true, false):
			if (shape as CollisionShape3D).shape != null:
				point = (shape as CollisionShape3D).global_position
				break
	var difference := point - global_position
	if difference.length_squared() <= 0.000001:
		return
	var forward := _velocity.normalized()
	var desired := difference.normalized()
	var angle := forward.angle_to(desired)
	if angle <= 0.000001:
		return
	var axis := forward.cross(desired).normalized()
	if axis.length_squared() <= 0.000001:
		axis = forward.cross(Vector3.UP).normalized()
		if axis.length_squared() <= 0.000001:
			axis = Vector3.RIGHT
	var rotation := Quaternion(axis, minf(angle, GameConfig.EM120R_TURN_RATE * delta))
	_velocity = (rotation * forward).normalized() * _data.projectile_speed


func _target_alive(target: Variant) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	var health: Variant = target.get("health")
	return health == null or float(health) > 0.0


func _advance(delta: float) -> bool:
	var from := global_position
	var remaining_range := maxf(_data.projectile_max_range - _traveled, 0.0)
	var motion := _velocity.normalized() * minf(_velocity.length() * delta, remaining_range)
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.exclude = _excludes
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var receiver := hit.collider as Node3D
		if is_instance_valid(receiver):
			Events.explosion_surface_impacted.emit(hit.position, hit.normal, receiver)
		_explode(hit.position)
		return false
	global_position += motion
	_traveled += motion.length()
	_face_velocity()
	if _traveled >= _data.projectile_max_range:
		_explode(global_position)
		return false
	return true


func _face_velocity() -> void:
	if _velocity.length_squared() <= 0.000001:
		return
	var up := Vector3.RIGHT if absf(_velocity.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(global_position + _velocity, up)


func _explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	Events.rpg_exploded.emit(at)
	_apply_area_damage(at)
	queue_free()


func _apply_area_damage(at: Vector3) -> void:
	if _data == null:
		return
	var damaged: Dictionary = {}
	var targets := get_tree().get_nodes_in_group(&"enemy") + get_tree().get_nodes_in_group(&"range_target")
	for node in targets:
		var target := node as Node3D
		if not _target_alive(target) or not target.has_method(&"take_damage") or damaged.has(target):
			continue
		var distance := target.global_position.distance_to(at)
		if distance > _data.explode_radius:
			continue
		damaged[target] = true
		var damage := _data.explode_kill_damage if distance <= _data.explode_kill_radius \
			else _data.explode_damage * _data.explode_falloff_factor
		target.take_damage(damage, false)
		Events.damage_dealt.emit(damage, false)
		Events.hit_confirmed.emit(false)


func _build_engine_visuals() -> void:
	var tail := 0.0
	for node in $Model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var box := mesh_node.get_aabb()
		var to_local := global_transform.affine_inverse() * mesh_node.global_transform
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					tail = maxf(tail, (to_local * Vector3(x, y, z)).z)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GameConfig.EM120R_ENGINE_FLAME_COLOR
	material.emission_enabled = true
	material.emission = GameConfig.EM120R_ENGINE_FLAME_COLOR
	material.emission_energy_multiplier = GameConfig.EM120R_ENGINE_LIGHT_ENERGY
	var cone := CylinderMesh.new()
	cone.top_radius = GameConfig.EM120R_ENGINE_FLAME_RADIUS
	cone.bottom_radius = 0.0
	cone.height = GameConfig.EM120R_ENGINE_FLAME_LENGTH
	_engine_flame = MeshInstance3D.new()
	_engine_flame.name = "EngineFlame"
	_engine_flame.mesh = cone
	_engine_flame.material_override = material
	_engine_flame.rotation.x = -PI * 0.5
	_engine_flame.position.z = tail + GameConfig.EM120R_ENGINE_FLAME_LENGTH * 0.5
	_engine_flame.visible = false
	add_child(_engine_flame)
	_engine_light = OmniLight3D.new()
	_engine_light.name = "EngineLight"
	_engine_light.position.z = tail
	_engine_light.light_color = GameConfig.EM120R_ENGINE_FLAME_COLOR
	_engine_light.light_energy = GameConfig.EM120R_ENGINE_LIGHT_ENERGY
	_engine_light.omni_range = GameConfig.EM120R_ENGINE_LIGHT_RANGE
	_engine_light.visible = false
	add_child(_engine_light)
