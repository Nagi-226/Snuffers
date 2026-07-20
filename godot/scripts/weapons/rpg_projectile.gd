## RPGProjectile — 火箭弹投射物（W2 火力蜂）
##
## 弹道忠实复刻网页版 updateRocket（index.html L3133-3180）：
## 恒定初速 + vy -= g·delta 手动积分 + 每帧扫掠射线碰撞 + 朝向速度方向 +
## 超程（300u）或坠地（y < -10）空中自爆。
## 不用 RigidBody3D：网页版为纯运动学弹道，手动积分才能 1:1 对齐 §7 参数表。
##
## 爆炸结算（explode，index.html L1510-1625）：
## - 爆径 10u 内可伤害目标即杀（explode_damage 为契约缺口暂定值，网页版不经 HP 直接移除）；
## - group "bunker" 目标在 爆径+5u 内特杀（destroy() 鸭子调用；
##   彻底总线化的 Events.bunker_destroyed 信号为契约缺口，见交付报告）；
## - 玩家零自伤（GameConfig.RPG_SELF_DAMAGE=false，经发射方 RID 排除实现）。
extends Node3D

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")

var _velocity: Vector3 = Vector3.ZERO
var _excludes: Array[RID] = []
var _data: WeaponData
var _traveled: float = 0.0
var _exploded: bool = false


## 由 rpg_controller 在实例化后调用：方向、发射方排除 RID、武器数据。
func setup(direction: Vector3, excludes: Array[RID], data: WeaponData) -> void:
	_data = data
	_velocity = direction.normalized() * data.projectile_speed
	_excludes = excludes


func _physics_process(delta: float) -> void:
	if _exploded:
		return

	_velocity.y -= _data.projectile_gravity * delta
	var from := global_position
	var motion := _velocity * delta

	# 扫掠射线（网页版同款：射线长 = 本帧位移 + 余量，L3164）。
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.exclude = _excludes
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit.position)
		return

	global_position = from + motion
	# 朝向速度方向（网页版 L3142）；模型 -Z 为弹头。
	if _velocity.length_squared() > 0.0001:
		look_at(global_position + _velocity, Vector3.UP)

	_traveled += motion.length()
	if _traveled >= _data.projectile_max_range or global_position.y < _data.projectile_explode_below_y:
		_explode(global_position)


## 爆炸：球形范围查询结算 + 灰盒占位视觉（火球放大淡出，对应网页版 animExplosion）。
func _explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	_apply_area_damage(at)
	_spawn_explosion_placeholder(at)
	queue_free()


func _apply_area_damage(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = _data.explode_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, at)
	params.collide_with_areas = true
	params.exclude = _excludes

	var damaged: Array[Node] = []
	for result in space.intersect_shape(params, 32):
		var collider: Object = result.collider

		# 碉堡特杀：判定半径 = 爆径 + 加成（index.html L1593-1610）。
		var bunker := HitSolver.find_group_ancestor(collider, &"bunker")
		if bunker != null:
			if bunker.global_position.distance_to(at) <= _data.explode_radius + _data.bunker_radius_bonus:
				if bunker.has_method(&"destroy"):
					bunker.destroy()
			continue

		var target := HitSolver.find_damageable(collider)
		if target == null or damaged.has(target):
			continue
		damaged.append(target)
		# 爆径内即杀（网页版不经 HP 直接移除，L1556-1591）；不分部位。
		target.take_damage(_data.explode_damage, false)


## 灰盒占位视觉：半透明火球 1.0s 放大淡出（正式爆炸特效属 W5 域，经 weapon_fired/后续爆炸信号接入）。
func _spawn_explosion_placeholder(at: Vector3) -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = _data.explode_radius
	sphere.height = _data.explode_radius * 2.0
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.27, 0.0, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = material
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_tree().root
	container.add_child(ball)
	ball.global_position = at
	var tween := ball.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * 1.5, 1.0)
	tween.tween_property(material, "albedo_color:a", 0.0, 1.0)
	tween.chain().tween_callback(ball.queue_free)
