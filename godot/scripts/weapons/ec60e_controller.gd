## EC-60E：消费独立投掷请求，安全生成后唯一扣除手雷库存。
## 挂载于 Player 根下；不切枪、不使用枪械弹药或换弹接口。
extends Node3D

const PROJECTILE_SCENE := preload("res://scenes/weapons/ec60e_projectile.tscn")

var _cooldown := 0.0
var _projectiles: Array[RigidBody3D] = []


func _ready() -> void:
	Events.ec60e_throw_requested.connect(_on_throw_requested)


func _exit_tree() -> void:
	Events.ec60e_throw_requested.disconnect(_on_throw_requested)
	# 正常投体挂在关卡；玩家/控制器提前退出也必须清理自己生成的投体。
	for projectile in _projectiles:
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			projectile.queue_free()
	_projectiles.clear()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	for i in range(_projectiles.size() - 1, -1, -1):
		if not is_instance_valid(_projectiles[i]):
			_projectiles.remove_at(i)


func _on_throw_requested(origin: Vector3, direction: Vector3,
		inherited_velocity: Vector3, excludes: Array[RID]) -> void:
	if get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or GameState.mission_phase in [GameState.MissionPhase.COMPLETED, GameState.MissionPhase.GAME_OVER]:
		return
	if _cooldown > 0.0:
		return
	if GameState.ec60e_grenades <= 0:
		Events.message_posted.emit("EC-60E 手雷已用尽")
		return
	if not origin.is_finite() or not direction.is_finite() or not inherited_velocity.is_finite() \
			or direction.length_squared() <= 0.000001:
		return
	var forward := direction.normalized()
	var spawn: Variant = _safe_spawn_position(origin, forward, excludes)
	if spawn == null:
		Events.message_posted.emit("空间不足，无法投掷手雷")
		return
	var projectile := PROJECTILE_SCENE.instantiate() as RigidBody3D
	if projectile == null:
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = self # 单独 Player/无关卡的夹具仍有明确生命周期。
	host.add_child(projectile)
	projectile.top_level = true
	projectile.global_position = spawn
	projectile.reset_physics_interpolation()
	projectile.setup(forward, inherited_velocity, excludes)
	_projectiles.append(projectile)
	GameState.ec60e_grenades -= 1
	_cooldown = GameConfig.EC60E_THROW_INTERVAL
	Events.ec60e_stock_changed.emit(GameState.ec60e_grenades)


func _safe_spawn_position(origin: Vector3, direction: Vector3, excludes: Array[RID]) -> Variant:
	var shape := SphereShape3D.new()
	shape.radius = GameConfig.EC60E_QUERY_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.margin = GameConfig.EC60E_SPAWN_MARGIN
	query.collision_mask = GameConfig.EC60E_COLLISION_MASK
	query.exclude = excludes
	query.collide_with_areas = false
	query.transform = Transform3D(Basis.IDENTITY, origin)
	var space := get_world_3d().direct_space_state
	# cast_motion 会忽略起点已有重叠，必须先显式拒绝墙内/无余量的相机起点。
	if not space.intersect_shape(query, 1).is_empty():
		return null
	query.motion = direction * GameConfig.EC60E_LAUNCH_FORWARD
	var fractions := space.cast_motion(query)
	if fractions.size() < 2:
		return null
	var travel := maxf(0.0, query.motion.length() * fractions[0] - GameConfig.EC60E_SPAWN_MARGIN)
	var spawn := origin + direction * travel
	query.motion = Vector3.ZERO
	query.transform.origin = spawn
	if not space.intersect_shape(query, 1).is_empty():
		return null
	return spawn
