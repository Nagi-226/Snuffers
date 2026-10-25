## SporeProjectile — 寄生体孢子团投射物（W3 敌智蜂）
##
## 2026-10-25 机主指令：远程孢子必须有「真正扔过来」的模型效果对应——直线曳光
## 退役。弹道复用 rpg_projectile 的运动学模式（手动积分 + 帧扫掠射线，不用
## RigidBody，帧精确）；直击结算不爆炸：命中玩家 → 随机部位 player_damaged
## （enemy_base._damage_player 同款信号对）；命中世界/超程 → 绿色溅落闪光。
## 抛物线补偿按估算飞行时间抬高瞄准点（移动目标可闪避——2.6s 单发慎重投掷
## 节奏下的刻意设计，参考《针锋相对》戈诺姆远程孢子）。
extends Node3D

## 与 enemy_base.PLAYER_HIT_PARTS 同源（私有常量不跨文件引用，双处维护）。
const HIT_PARTS: Array[StringName] = [&"head", &"body", &"legs"]

var _velocity: Vector3 = Vector3.ZERO
var _thrower_rid: RID
var _traveled: float = 0.0


## 发射方（infantry._attack）在 add_child 后调用：出手点、玩家胸口目标、投掷者排除。
func setup(from: Vector3, target_chest: Vector3, thrower: CollisionObject3D) -> void:
	global_position = from
	_thrower_rid = thrower.get_rid()
	var flight_t: float = from.distance_to(target_chest) / GameConfig.INFANTRY_SPORE_SPEED
	var aim := target_chest + Vector3.UP * (0.5 * GameConfig.INFANTRY_SPORE_GRAVITY * flight_t * flight_t)
	_velocity = (aim - from).normalized() * GameConfig.INFANTRY_SPORE_SPEED


func _physics_process(delta: float) -> void:
	_velocity.y -= GameConfig.INFANTRY_SPORE_GRAVITY * delta
	var from := global_position
	var motion := _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.exclude = [_thrower_rid]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit.position, hit.collider)
		return
	global_position = from + motion
	if _velocity.length_squared() > 0.0001:
		look_at(global_position + _velocity, Vector3.UP)
	_traveled += motion.length()
	if _traveled >= GameConfig.INFANTRY_SPORE_MAX_RANGE:
		_splat(global_position)
		queue_free()


func _impact(pos: Vector3, collider: Object) -> void:
	_splat(pos)
	if collider is Node and (collider as Node).is_in_group(&"player"):
		Events.player_damaged.emit(HIT_PARTS[randi() % HIT_PARTS.size()], GameConfig.INFANTRY_DAMAGE)
		Events.player_hit_direction.emit(global_position)
	queue_free()


## 溅落闪光：加色绿球 0.3s 胀大淡出（combat_fx 孢子材质同色系，无外部资产）。
func _splat(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.9, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.85, 0.3)
	mesh.material_override = mat
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	scene_root.add_child(mesh)
	mesh.global_position = at
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3(2.6, 2.6, 2.6), 0.3)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(mesh.queue_free)
