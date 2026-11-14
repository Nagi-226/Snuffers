## EC-60E「闷罐」：物理落地/弹跳，投出后三秒产生穿墙等离子脉冲。
## 独立于 EC-40 榴弹；玩家免伤，不附带碉堡 destroy 特杀。
extends RigidBody3D

var _armed := false
var _age := 0.0
var _exploded := false


func _ready() -> void:
	freeze = true # setup 前不启动物理与引信，单独场景冒烟也不会误爆。
	collision_layer = 0
	collision_mask = GameConfig.EC60E_COLLISION_MASK
	continuous_cd = true
	max_contacts_reported = GameConfig.EC60E_MAX_CONTACTS
	mass = GameConfig.EC60E_MASS
	gravity_scale = GameConfig.EC60E_GRAVITY_SCALE
	linear_damp = GameConfig.EC60E_LINEAR_DAMP
	angular_damp = GameConfig.EC60E_ANGULAR_DAMP
	var material := PhysicsMaterial.new()
	material.bounce = GameConfig.EC60E_BOUNCE
	material.friction = GameConfig.EC60E_FRICTION
	physics_material_override = material
	var shape := CylinderShape3D.new()
	shape.radius = GameConfig.EC60E_COLLISION_RADIUS
	shape.height = GameConfig.EC60E_COLLISION_HEIGHT
	shape.margin = GameConfig.EC60E_SPAWN_MARGIN
	$CollisionShape3D.shape = shape


func setup(direction: Vector3, inherited_velocity: Vector3, excludes: Array[RID]) -> void:
	if _armed or _exploded:
		return
	if not direction.is_finite() or not inherited_velocity.is_finite() \
			or direction.length_squared() <= 0.000001:
		queue_free()
		return
	for excluded_rid in excludes:
		if excluded_rid.is_valid():
			PhysicsServer3D.body_add_collision_exception(get_rid(), excluded_rid)
	_age = 0.0
	_armed = true
	freeze = false
	linear_velocity = direction.normalized() * GameConfig.EC60E_THROW_SPEED \
			+ Vector3.UP * GameConfig.EC60E_THROW_UP_SPEED \
			+ inherited_velocity * GameConfig.EC60E_INHERIT_VELOCITY
	angular_velocity = GameConfig.EC60E_SPIN


## GodotPhysics BodyPair3D 向 add_contact 传入世界法线和接触点；local_normal 名称不代表本体局部坐标。
## 按当前旋转后的圆柱支持面纠正本体穿透，保留引擎重力、反弹和 CCD，不改世界容差。
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _armed or _exploded:
		return
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is CylinderShape3D:
		return
	var shape := collision.shape as CylinderShape3D
	var corrected := state.transform
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index).normalized()
		if not normal.is_finite() or normal.length_squared() < 0.000001:
			continue
		var shape_transform := corrected * collision.transform
		var local_direction := shape_transform.basis.transposed() * normal
		var support := shape.radius * Vector2(local_direction.x, local_direction.z).length() \
				+ shape.height * 0.5 * absf(local_direction.y)
		var depth := support - (shape_transform.origin - state.get_contact_collider_position(index)).dot(normal)
		corrected.origin += normal * maxf(0.0, depth - GameConfig.EC60E_CONTACT_ALLOWED_PENETRATION)
	state.transform = corrected


func _physics_process(delta: float) -> void:
	if not _armed or _exploded:
		return
	# RigidBody 的 sleeping 不会停止本节点回调；落地静止仍按时引爆。
	_age += delta
	if _age >= GameConfig.EC60E_FUSE_TIME:
		_explode()


func _explode() -> void:
	if _exploded or not is_inside_tree():
		return
	_exploded = true
	set_physics_process(false)
	var at := global_position
	Events.ec60e_exploded.emit(at)
	_apply_area_damage(at)
	queue_free()


func _apply_area_damage(at: Vector3) -> void:
	var damaged: Dictionary = {}
	var targets := get_tree().get_nodes_in_group(&"enemy") + get_tree().get_nodes_in_group(&"range_target")
	for node in targets:
		var target := node as Node3D
		if not is_instance_valid(target) or target.is_queued_for_deletion() \
				or not target.has_method(&"take_damage") or damaged.has(target):
			continue
		if target.is_in_group(&"player") and not GameConfig.EC60E_SELF_DAMAGE:
			continue
		var health: Variant = target.get("health")
		if health != null and float(health) <= 0.0:
			continue
		if not target.global_position.is_finite():
			continue
		var distance := target.global_position.distance_to(at)
		if distance > GameConfig.EC60E_OUTER_RADIUS:
			continue
		var damage := GameConfig.EC60E_INNER_DAMAGE if distance <= GameConfig.EC60E_INNER_RADIUS \
				else GameConfig.EC60E_OUTER_DAMAGE
		damaged[target] = true
		# 组遍历不受物理查询32结果上限影响，也不进行视线/墙壁检测。
		target.take_damage(damage, false)
		Events.damage_dealt.emit(damage, false)
		Events.hit_confirmed.emit(false)
