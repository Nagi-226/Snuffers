## ExplosionFx — 榴弹爆炸特效（W2 火力蜂，2026-10-22 机主立项：替换灰盒占位橙球）
##
## 程序化多层组合（真实火光风格）：爆闪 OmniLight + 噪声火球（白炽→橙→暗红）
## + 上升烟团 + 火花碎屑 + 地面冲击波环 + 地面焦痕贴花。
##
## 契约约束（AGENTS.md）：
## - 参数全部走 GameConfig.EXPLOSION_FX_*，脚本零硬编码数值（颜色常量沿用
##   player_combat_fx.gd 先例留在脚本内）；
## - 只监听 Events 总线（rpg_exploded，G2 冻结信号），不引用任何业务节点；
## - 全部纹理运行时程序合成（FastNoiseLite 噪声 + 径向渐变），零第三方资产。
##
## 挂载约定：player.tscn 根节点下 ExplosionFx（Node3D），同 PlayerCombatFx。
extends Node3D

const _WHITE := Color(1.0, 0.98, 0.92)
const _ORANGE := Color(1.0, 0.45, 0.08)
const _DARK_RED := Color(0.4, 0.08, 0.02)

var _instances: Array = [] ## [{root, light, fire_mat, fire_quads, smoke_mat, smoke_quads, smoke_offsets, smoke_scales, ring_mat, ring, sparks, t, active}]
var _cursor: int = 0
var _scorches: Array[Decal] = [] ## 焦痕池（FIFO，同弹坑机制）

var _fireball_texture: ImageTexture
var _smoke_texture: ImageTexture
var _ring_texture: ImageTexture
var _scorch_texture: ImageTexture


func _ready() -> void:
	_build_fireball_texture()
	_build_smoke_texture()
	_build_ring_texture()
	_build_scorch_texture()
	for i: int in GameConfig.EXPLOSION_FX_POOL:
		_instances.append(_build_instance(i))
	Events.rpg_exploded.connect(_on_rpg_exploded)


func _exit_tree() -> void:
	Events.rpg_exploded.disconnect(_on_rpg_exploded)


# ===== 纹理程序合成 =====

## 火球：ADD 混合下 alpha 不参与衰减，渐变必须做进 RGB（边缘黑=零贡献）。
## 纹理只承载亮度场（白炽核增强 + FastNoiseLite 侵蚀边缘 + 径向窗口强制边界归零），
## 色相完全由 albedo_color 时间轴承载——否则纹理橙 × 材质橙双乘会把 G/B 通道压没，
## 火球提前缩成暗红小点（2026-10-22 探针实证）。
func _build_fireball_texture() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 4022
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center := Vector2(64.0, 64.0)
	for y: int in 128:
		for x: int in 128:
			var d := Vector2(float(x), float(y)).distance_to(center) / 64.0
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var r := d * (0.55 + 0.45 * n)
			var w := clampf((1.0 - d) / 0.22, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			var glow := pow(clampf(1.0 - r, 0.0, 1.0), 0.9) * w
			var core := pow(clampf(1.0 - d * 2.4, 0.0, 1.0), 2.2)
			var v := clampf(glow + core * 0.4, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_fireball_texture = ImageTexture.create_from_image(img)


## 烟团：普通 alpha 混合，深灰 RGB + 噪声破碎团块 + 径向窗口强制面片边界归零。
func _build_smoke_texture() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 8173
	noise.frequency = 0.07
	noise.fractal_octaves = 4
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center := Vector2(64.0, 64.0)
	for y: int in 128:
		for x: int in 128:
			var d := Vector2(float(x), float(y)).distance_to(center) / 64.0
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var w := clampf((1.0 - d) / 0.3, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			var a := pow(clampf(1.0 - d * (0.55 + 0.5 * n), 0.0, 1.0), 1.6) * 0.6 * w
			var shade := 0.09 + 0.07 * n
			img.set_pixel(x, y, Color(shade, shade, shade * 1.06, a))
	_smoke_texture = ImageTexture.create_from_image(img)


## 冲击波环：ADD 混合细环带（高斯环，半径 0.85 处峰值）。
func _build_ring_texture() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center := Vector2(64.0, 64.0)
	for y: int in 128:
		for x: int in 128:
			var d := Vector2(float(x), float(y)).distance_to(center) / 64.0
			var band := exp(-pow((d - 0.85) * 8.0, 2.0))
			img.set_pixel(x, y, Color(1.0 * band, 0.6 * band, 0.28 * band, 1.0))
	_ring_texture = ImageTexture.create_from_image(img)


## 焦痕：近实黑中心 + 噪声侵蚀边缘（比弹坑更大更不规则）。
func _build_scorch_texture() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 5521
	noise.frequency = 0.11
	noise.fractal_octaves = 3
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center := Vector2(64.0, 64.0)
	for y: int in 128:
		for x: int in 128:
			var d := Vector2(float(x), float(y)).distance_to(center) / 60.0
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var w := clampf((1.0 - d) / 0.25, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			var a := pow(clampf(1.0 - d * (0.55 + 0.55 * n), 0.0, 1.0), 1.3) * 0.95 * w
			img.set_pixel(x, y, Color(0.015, 0.015, 0.018, a))
	_scorch_texture = ImageTexture.create_from_image(img)


# ===== 实例池构建 =====

func _build_instance(idx: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Explosion%d" % idx
	root.visible = false
	add_child(root)

	var light := OmniLight3D.new()
	light.name = "FlashLight"
	light.light_color = Color(1.0, 0.62, 0.25)
	light.omni_range = GameConfig.EXPLOSION_FX_FLASH_RANGE
	light.visible = false
	root.add_child(light)

	# 4.6.2 引擎坑③：透明/ADD 材质会被雾整面漂白成雾色方片（探针实证）→ 全部特效材质禁雾。
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.disable_fog = true
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_mat.albedo_texture = _fireball_texture
	var fire_quads: Array[MeshInstance3D] = []
	for i: int in GameConfig.EXPLOSION_FX_FIREBALL_QUADS:
		var q := MeshInstance3D.new()
		q.name = "Fireball%d" % i
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 1.0)
		q.mesh = qm
		q.material_override = fire_mat
		root.add_child(q)
		fire_quads.append(q)

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.disable_fog = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.albedo_texture = _smoke_texture
	var smoke_quads: Array[MeshInstance3D] = []
	for i: int in GameConfig.EXPLOSION_FX_SMOKE_COUNT:
		var q := MeshInstance3D.new()
		q.name = "Smoke%d" % i
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 1.0)
		q.mesh = qm
		q.material_override = smoke_mat
		root.add_child(q)
		smoke_quads.append(q)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.disable_fog = true
	ring_mat.albedo_texture = _ring_texture
	var ring := MeshInstance3D.new()
	ring.name = "ShockRing"
	var rm := QuadMesh.new()
	rm.size = Vector2(1.0, 1.0)
	ring.mesh = rm
	ring.material_override = ring_mat
	ring.rotation_degrees.x = -90.0
	root.add_child(ring)

	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.disable_fog = true
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.albedo_color = Color(1.0, 0.72, 0.3, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.6, 0.2)
	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = GameConfig.EXPLOSION_FX_SPARK_COUNT
	sparks.lifetime = GameConfig.EXPLOSION_FX_SPARK_LIFETIME
	sparks.one_shot = true
	sparks.explosiveness = 0.92
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 90.0
	pm.initial_velocity_min = GameConfig.EXPLOSION_FX_SPARK_VELOCITY_MIN
	pm.initial_velocity_max = GameConfig.EXPLOSION_FX_SPARK_VELOCITY_MAX
	pm.gravity = Vector3(0.0, -14.0, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	sparks.process_material = pm
	# 4.6.2 引擎坑（2026-10-22 探针实证）：BILLBOARD_PARTICLES 材质下
	# ParticleProcessMaterial.scale_min/max 不生效（粒子按网格原始尺寸渲染）。
	# 故粒径直接烘进 draw pass 网格：双通道 = 下限/上限两档粒径均分。
	var sq_min := QuadMesh.new()
	sq_min.size = Vector2(GameConfig.EXPLOSION_FX_SPARK_SCALE_MIN, GameConfig.EXPLOSION_FX_SPARK_SCALE_MIN)
	sq_min.material = spark_mat
	var sq_max := QuadMesh.new()
	sq_max.size = Vector2(GameConfig.EXPLOSION_FX_SPARK_SCALE_MAX, GameConfig.EXPLOSION_FX_SPARK_SCALE_MAX)
	sq_max.material = spark_mat
	sparks.draw_pass_1 = sq_min
	sparks.draw_pass_2 = sq_max
	root.add_child(sparks)

	return {
		"root": root,
		"light": light,
		"fire_mat": fire_mat,
		"fire_quads": fire_quads,
		"smoke_mat": smoke_mat,
		"smoke_quads": smoke_quads,
		"smoke_offsets": [] as Array[Vector3],
		"smoke_scales": [] as Array[float],
		"ring_mat": ring_mat,
		"ring": ring,
		"sparks": sparks,
		"t": 0.0,
		"active": false,
	}


# ===== 触发与逐帧驱动 =====

func _on_rpg_exploded(pos: Vector3) -> void:
	var inst: Dictionary = _instances[_cursor]
	_cursor = (_cursor + 1) % _instances.size()
	var root := inst["root"] as Node3D
	root.global_position = pos
	root.visible = true
	# 火球面片随机滚转防重复感；中心抬升 0.3 倍直径（真实火球腾起在爆点上方，
	# 贴地爆炸时避免半颗球埋进地面/被路面遮挡）
	for q: MeshInstance3D in inst["fire_quads"]:
		q.rotation_degrees.z = randf_range(0.0, 360.0)
		q.position.y = GameConfig.EXPLOSION_FX_FIREBALL_SIZE * 0.3
	# 烟团逐片随机偏移/倍率（触发时重掷，池复用不呆板）
	var offsets := [] as Array[Vector3]
	var scales := [] as Array[float]
	for i: int in GameConfig.EXPLOSION_FX_SMOKE_COUNT:
		var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		offsets.append(dir * randf_range(0.3, GameConfig.EXPLOSION_FX_FIREBALL_SIZE * 0.3)
			+ Vector3(0.0, randf_range(0.2, 1.2), 0.0))
		scales.append(randf_range(0.7, 1.3))
		(inst["smoke_quads"][i] as MeshInstance3D).rotation_degrees.z = randf_range(0.0, 360.0)
	inst["smoke_offsets"] = offsets
	inst["smoke_scales"] = scales
	# 冲击波环/焦痕只贴近地面的爆炸才有（rpg_exploded 冻结契约只传位置，地面假设 y≈0）
	var near_ground := pos.y <= GameConfig.EXPLOSION_FX_SCORCH_MAX_HEIGHT
	(inst["ring"] as MeshInstance3D).visible = near_ground
	if near_ground:
		(inst["ring"] as MeshInstance3D).position.y = 0.06 - pos.y
		_spawn_scorch(pos)
	(inst["sparks"] as GPUParticles3D).restart()
	inst["t"] = 0.0
	inst["active"] = true


func _process(delta: float) -> void:
	for inst: Dictionary in _instances:
		if not inst["active"]:
			continue
		inst["t"] += delta
		var t: float = inst["t"]
		_drive_flash(inst, t)
		_drive_fireball(inst, t)
		_drive_smoke(inst, t)
		_drive_ring(inst, t)
		if t >= GameConfig.EXPLOSION_FX_SMOKE_LIFETIME:
			inst["active"] = false
			(inst["root"] as Node3D).visible = false
			(inst["light"] as OmniLight3D).visible = false


## 爆闪：能量平方衰减（真实火光的"白闪-速暗"节奏）。
func _drive_flash(inst: Dictionary, t: float) -> void:
	var light := inst["light"] as OmniLight3D
	var p := t / GameConfig.EXPLOSION_FX_FLASH_LIFETIME
	if p >= 1.0:
		light.visible = false
		return
	light.visible = true
	light.light_energy = GameConfig.EXPLOSION_FX_FLASH_ENERGY * pow(1.0 - p, 2.0)


## 火球：快速膨胀（ease-out）+ 白炽→橙→暗红色温退行（ADD 混合经 RGB 衰减）。
func _drive_fireball(inst: Dictionary, t: float) -> void:
	var p := clampf(t / GameConfig.EXPLOSION_FX_FIREBALL_LIFETIME, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - p, 3.0)
	var s: float = GameConfig.EXPLOSION_FX_FIREBALL_SIZE * (0.25 + 0.75 * ease)
	var col: Color
	if p < 0.3:
		col = _WHITE.lerp(_ORANGE, p / 0.3)
	elif p < 0.7:
		col = _ORANGE.lerp(_DARK_RED, (p - 0.3) / 0.4)
	else:
		col = _DARK_RED * (1.0 - (p - 0.7) / 0.3)
	(inst["fire_mat"] as StandardMaterial3D).albedo_color = col
	# 4.6.2 引擎坑②：BILLBOARD_ENABLED 重建 modelview 时归一化基向量，节点 scale 被剥离
	# （探针实证：billboard 面片 scale=5 渲染仍 1m）→ 尺寸必须逐帧写进 QuadMesh.size。
	for q: MeshInstance3D in inst["fire_quads"]:
		q.visible = p < 1.0
		(q.mesh as QuadMesh).size = Vector2(s, s)


## 烟团：火球褪色后接棒，上升 + 膨胀 + alpha 淡出。
func _drive_smoke(inst: Dictionary, t: float) -> void:
	var p := clampf(t / GameConfig.EXPLOSION_FX_SMOKE_LIFETIME, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - p, 2.0)
	var alpha := 0.85 * minf(p * 6.0, 1.0) * (1.0 - p)
	(inst["smoke_mat"] as StandardMaterial3D).albedo_color = Color(1.0, 1.0, 1.0, alpha)
	var offsets: Array[Vector3] = inst["smoke_offsets"]
	var scales: Array[float] = inst["smoke_scales"]
	for i: int in (inst["smoke_quads"] as Array).size():
		var q := (inst["smoke_quads"][i] as MeshInstance3D)
		if i >= offsets.size():
			q.visible = false
			continue
		q.position = offsets[i] + Vector3(0.0, GameConfig.EXPLOSION_FX_SMOKE_RISE * t * scales[i], 0.0)
		var s: float = GameConfig.EXPLOSION_FX_SMOKE_SIZE * scales[i] * (0.35 + 0.65 * ease)
		(q.mesh as QuadMesh).size = Vector2(s, s)  # billboard 吞节点缩放，尺寸写网格


## 冲击波环：贴地高速扩散淡出。
func _drive_ring(inst: Dictionary, t: float) -> void:
	var ring := inst["ring"] as MeshInstance3D
	var p := clampf(t / GameConfig.EXPLOSION_FX_RING_LIFETIME, 0.0, 1.0)
	if p >= 1.0:
		ring.visible = false
		return
	var ease := 1.0 - pow(1.0 - p, 3.0)
	var s: float = GameConfig.EXPLOSION_FX_RING_SIZE * (0.1 + 0.9 * ease)
	(ring.mesh as QuadMesh).size = Vector2(s, s)  # billboard/缩放坑同理，尺寸写网格
	(inst["ring_mat"] as StandardMaterial3D).albedo_color = Color(1.0 - p, 1.0 - p, 1.0 - p, 1.0)


## 焦痕贴花：FIFO 池（同弹坑机制），地面投影 y≈0 假设与冲击波环一致。
func _spawn_scorch(pos: Vector3) -> void:
	var d: Decal
	if _scorches.size() < GameConfig.EXPLOSION_FX_SCORCH_POOL:
		d = Decal.new()
		d.texture_albedo = _scorch_texture
		d.size = Vector3(GameConfig.EXPLOSION_FX_SCORCH_SIZE, GameConfig.EXPLOSION_FX_SCORCH_SIZE, 0.08)
		d.modulate = Color(1, 1, 1, 0.9)
		add_child(d)
		_scorches.append(d)
	else:
		d = _scorches.pop_front()
		_scorches.append(d)
	var ground := Vector3(pos.x, 0.02, pos.z)
	d.look_at_from_position(ground + Vector3.UP * 0.02, ground - Vector3.UP, Vector3.FORWARD)
	d.rotate_object_local(Vector3.FORWARD, randf() * TAU)
