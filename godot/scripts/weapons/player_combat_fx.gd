## PlayerCombatFx — 玩家弹道特效（W2 火力蜂，2026-10-19 机主立项）
##
## 三件套：微弱青蓝枪口焰（电磁武器观感）+ 弹坑贴花（Decal 池 FIFO 复用）+
## 金属表面溅射火星（GPUParticles3D one-shot 池）。
##
## 契约约束（AGENTS.md）：
## - 参数全部走 GameConfig.PLAYER_MUZZLE_* / BULLET_*，脚本零硬编码数值；
## - 只监听 Events 总线，弹孔接收者由 bullet_mark_requested 显式传入；
## - 弹坑贴花纹理运行时程序合成（径向焦痕），无第三方资产。
##
## 挂载约定：player.tscn 根节点下 PlayerCombatFx（Node3D）。
extends Node3D

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")

var _flashes: Array = [] ## [{light, quad, remaining}] 枪口焰池（4 个轮转）
var _flash_cursor: int = 0
var _decals: Array[Decal] = [] ## 弹坑池（FIFO）
var _decal_remaining: Dictionary = {} ## 已命中实体上的贴花寿命；复用时重新计时
var _decal_texture: ImageTexture
var _sparks: Array[GPUParticles3D] = [] ## 火花池（8 个轮转）
var _spark_cursor: int = 0


func _ready() -> void:
	_build_flash_pool()
	_build_decal_texture()
	_build_spark_pool()
	Events.player_muzzle_flash.connect(_on_muzzle_flash)
	Events.bullet_impacted.connect(_on_bullet_impacted)
	Events.bullet_mark_requested.connect(_on_bullet_mark_requested)


func _exit_tree() -> void:
	Events.player_muzzle_flash.disconnect(_on_muzzle_flash)
	Events.bullet_impacted.disconnect(_on_bullet_impacted)
	Events.bullet_mark_requested.disconnect(_on_bullet_mark_requested)
	# 贴花挂在命中对象上，拥有者离树时仍须清掉自己分配的池。
	for decal: Variant in _decals:
		if is_instance_valid(decal) and not decal.is_queued_for_deletion():
			decal.queue_free()
	_decals.clear()
	_decal_remaining.clear()


func _process(delta: float) -> void:
	for f: Dictionary in _flashes:
		if f["remaining"] > 0.0:
			f["remaining"] -= delta
			if f["remaining"] <= 0.0:
				(f["light"] as OmniLight3D).visible = false
				(f["quad"] as MeshInstance3D).visible = false
	_update_decals(delta)


func _update_decals(delta: float) -> void:
	for index in range(_decals.size() - 1, -1, -1):
		var decal: Variant = _decals[index]
		if not is_instance_valid(decal) or decal.is_queued_for_deletion():
			_decal_remaining.erase(decal)
			_decals.remove_at(index)
			continue
		var remaining: float = maxf(0.0, float(_decal_remaining.get(decal, 0.0)) - delta)
		_decal_remaining[decal] = remaining
		if remaining <= 0.0:
			decal.visible = false


# ===== 枪口焰（青蓝电磁焰，微弱口径）=====

var _flash_texture: ImageTexture

## 程序合成枪口焰纹理：64×64 径向青蓝光斑（中心亮核 + 羽化边缘，ADD 叠加）。
## 注意：ADD 混合下 alpha 不参与衰减，必须把渐变做进 RGB（边缘黑=零贡献）。
func _build_flash_texture() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(32.0, 32.0)
	for y: int in 64:
		for x: int in 64:
			var d := Vector2(float(x), float(y)).distance_to(center) / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # 平方羽化
			img.set_pixel(x, y, Color(0.5 * a, 0.95 * a, 1.0 * a, 1.0))
	_flash_texture = ImageTexture.create_from_image(img)


func _build_flash_pool() -> void:
	_build_flash_texture()
	var quad_mat := StandardMaterial3D.new()
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad_mat.albedo_texture = _flash_texture
	quad_mat.albedo_color = Color(0.45, 0.9, 1.0, 0.85)
	quad_mat.emission_enabled = true
	quad_mat.emission = Color(0.4, 0.9, 1.0)
	quad_mat.no_depth_test = false
	for i: int in 4:
		var light := OmniLight3D.new()
		light.name = "FlashLight%d" % i
		light.light_color = Color(0.4, 0.9, 1.0)
		light.light_energy = GameConfig.PLAYER_MUZZLE_FLASH_ENERGY
		light.omni_range = GameConfig.PLAYER_MUZZLE_FLASH_RANGE
		light.visible = false
		add_child(light)
		var quad := MeshInstance3D.new()
		quad.name = "FlashQuad%d" % i
		var qm := QuadMesh.new()
		qm.size = Vector2(0.1, 0.1)
		quad.mesh = qm
		quad.material_override = quad_mat
		quad.visible = false
		add_child(quad)
		_flashes.append({"light": light, "quad": quad, "remaining": 0.0})


func _on_muzzle_flash(_weapon_id: StringName, pos: Vector3) -> void:
	var f: Dictionary = _flashes[_flash_cursor]
	_flash_cursor = (_flash_cursor + 1) % _flashes.size()
	(f["light"] as OmniLight3D).global_position = pos
	(f["quad"] as MeshInstance3D).global_position = pos
	var quad := f["quad"] as MeshInstance3D
	quad.rotation_degrees.z = randf_range(0.0, 360.0)
	(f["light"] as OmniLight3D).visible = true
	quad.visible = true
	f["remaining"] = GameConfig.MUZZLE_FLASH_LIFETIME


# ===== 弹坑贴花（Decal 池）=====

## 程序合成焦痕纹理：64×64 径向暗斑，中心不透明、边缘羽化，带少量噪声缺口。
func _build_decal_texture() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(32.0, 32.0)
	for y: int in 64:
		for x: int in 64:
			var d := Vector2(float(x), float(y)).distance_to(center) / 30.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.9  # 平方羽化，边缘柔和
			if d < 0.45:
				a = 0.95  # 弹心近实黑
			img.set_pixel(x, y, Color(0.02, 0.02, 0.025, a))
	_decal_texture = ImageTexture.create_from_image(img)


func _on_bullet_impacted(pos: Vector3, normal: Vector3, metal: bool) -> void:
	if metal:
		_spawn_sparks(pos, normal)


func _on_bullet_mark_requested(pos: Vector3, normal: Vector3, receiver: Node3D) -> void:
	_spawn_decal(pos, normal, receiver)


func _spawn_decal(pos: Vector3, normal: Vector3, receiver: Node3D = null) -> void:
	if receiver != null and (not is_instance_valid(receiver) \
			or receiver.is_queued_for_deletion() or not receiver.is_inside_tree()):
		return
	if normal.length() < 0.01:
		normal = Vector3.UP
	normal = normal.normalized()
	if receiver != null:
		var surface := HitSolver.resolve_visual_surface(pos, normal, receiver)
		if not surface.is_empty():
			pos = surface.position
			normal = surface.normal
	_update_decals(0.0)
	var d: Decal
	var unused := -1
	for index in _decals.size():
		if not _decals[index].visible:
			unused = index
			break
	if unused >= 0:
		d = _decals[unused]
		_decals.remove_at(unused)
		_decals.append(d)
	elif _decals.size() < GameConfig.BULLET_DECAL_POOL:
		d = Decal.new()
		d.texture_albedo = _decal_texture
		d.size = Vector3(GameConfig.BULLET_DECAL_SIZE, GameConfig.BULLET_DECAL_DEPTH, GameConfig.BULLET_DECAL_SIZE)
		d.modulate = Color(1, 1, 1, 0.9)
		d.normal_fade = GameConfig.BULLET_DECAL_NORMAL_FADE
		d.upper_fade = 0.0
		d.lower_fade = 0.0
		_decals.append(d)
	else:
		d = _decals.pop_front()  # FIFO：复用最旧弹坑
		_decals.append(d)
	var holder: Node3D = receiver if receiver != null else self
	if d.get_parent() == null:
		holder.add_child(d)
	elif d.get_parent() != holder:
		d.reparent(holder, false)
	# 旧私有调用无接收者时也使用世界坐标，不继承玩家位移。
	d.top_level = receiver == null
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var tangent := up.cross(normal).normalized()
	# Godot Decal 沿局部 -Y 投射，X/Z 是纹理平面，不能用沿 -Z 的 look_at。
	d.global_transform = Transform3D(Basis(tangent, normal, tangent.cross(normal)),
		pos + normal * GameConfig.BULLET_DECAL_OFFSET)
	d.rotate_object_local(Vector3.UP, randf() * TAU)  # 绕投射轴滚转，法线保持不变
	d.visible = true
	_decal_remaining[d] = GameConfig.BULLET_DECAL_LIFETIME


# ===== 金属火花（GPUParticles3D one-shot 池）=====

func _build_spark_pool() -> void:
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.albedo_color = Color(1.0, 0.82, 0.45, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.75, 0.35)
	for i: int in 8:
		var p := GPUParticles3D.new()
		p.name = "Sparks%d" % i
		p.amount = GameConfig.BULLET_SPARK_COUNT
		p.lifetime = GameConfig.BULLET_SPARK_LIFETIME
		p.one_shot = true
		p.explosiveness = 0.95
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = GameConfig.BULLET_SPARK_SPREAD
		pm.initial_velocity_min = GameConfig.BULLET_SPARK_VELOCITY_MIN
		pm.initial_velocity_max = GameConfig.BULLET_SPARK_VELOCITY_MAX
		pm.gravity = Vector3(0.0, -12.0, 0.0)
		pm.damping_min = 1.5
		pm.damping_max = 3.0
		p.process_material = pm
		# 4.6.2 引擎坑（2026-10-22 探针实证）：BILLBOARD_PARTICLES 下
		# process_material 的 scale_min/max 不生效，粒径须烘进 draw pass 网格。
		# 双通道 = 契约下限/上限两档粒径均分（此前 scale 写法实际渲染 1m 方块）。
		# 注意：必须先声明 draw_passes=2 再挂第二通道，否则运行期报 p_pass 越界。
		p.draw_passes = 2
		var quad_min := QuadMesh.new()
		quad_min.size = Vector2(GameConfig.BULLET_SPARK_SCALE_MIN, GameConfig.BULLET_SPARK_SCALE_MIN)
		quad_min.material = spark_mat
		var quad_max := QuadMesh.new()
		quad_max.size = Vector2(GameConfig.BULLET_SPARK_SCALE_MAX, GameConfig.BULLET_SPARK_SCALE_MAX)
		quad_max.material = spark_mat
		p.draw_pass_1 = quad_min
		p.draw_pass_2 = quad_max
		add_child(p)
		_sparks.append(p)


func _spawn_sparks(pos: Vector3, normal: Vector3) -> void:
	var p := _sparks[_spark_cursor]
	_spark_cursor = (_spark_cursor + 1) % _sparks.size()
	p.global_position = pos + normal * 0.03
	# 喷射主方向沿表面法线外弹
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = normal
	p.restart()
