## SkylineBuilder — CBD 远景天际线 v3（AI 贴图化三层结构，street_test 夜景配套）
##
## v3 背景：v1/v2 纯程序化亮窗被机主否决（"黑盒+亮格子"程序味太重）。
## v3 改用 AI 生成贴图（机主提供豆包参考图定风格，assets/textures/skyline/）：
## - 近层：内环塔楼盒体贴 AI 立面照片贴图（skyline_facade.gdshader 提亮窗发光）；
## - 中层：外环剪影盒体（同 shader 压暗）；
## - 远层：全景幕布卡环带（skyline_card.gdshader，AI 全景图，边缘羽化交叠）。
## 天线桅杆沿用 skyline_windows.gdshader 的 is_antenna 分支（顶端红灯闪烁）。
## 布局由 GameConfig.SKYLINE_SEED 确定性生成；全部参数见 game_config.gd 契约。
extends Node3D

const SHADER_FACADE := "res://assets/shaders/skyline_facade.gdshader"
const SHADER_CARD := "res://assets/shaders/skyline_card.gdshader"
const SHADER_ANTENNA := "res://assets/shaders/skyline_windows.gdshader"

const TEX_OFFICE := "res://assets/textures/skyline/facade_office.png"
const TEX_RESIDENTIAL := "res://assets/textures/skyline/facade_residential.png"
const TEX_NEON := "res://assets/textures/skyline/facade_neon.png"
const TEX_PANO_A := "res://assets/textures/skyline/pano_a.png"
const TEX_PANO_B := "res://assets/textures/skyline/pano_b.png"

var _mat_antenna: ShaderMaterial


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.SKYLINE_SEED

	# 立面材质：办公幕墙 / 住宅 / 霓虹媒体（贴图各异，共享 shader）
	var mat_office := _make_facade_material(TEX_OFFICE, 0.55, 1.7)
	var mat_residential := _make_facade_material(TEX_RESIDENTIAL, 0.30, 1.5)  # 住宅贴图偏亮，压更暗
	var mat_neon := _make_facade_material(TEX_NEON, 0.45, 1.9)
	# 外环剪影：住宅贴图极限压暗，只留稀疏亮窗
	var mat_silhouette := _make_facade_material(TEX_RESIDENTIAL, 0.15, 1.1)

	# 天线桅杆材质（沿用程序化 shader 的桅杆分支）
	_mat_antenna = ShaderMaterial.new()
	_mat_antenna.shader = load(SHADER_ANTENNA)

	# 内环塔楼：主街轴线 ±扇区留视线走廊
	var gap_rad := deg_to_rad(GameConfig.SKYLINE_VISTA_GAP_DEG)
	var placed := 0
	var attempts := 0
	while placed < GameConfig.SKYLINE_TOWER_COUNT_INNER and attempts < 200:
		attempts += 1
		var ang := rng.randf() * TAU
		var axis_dist: float = min(abs(ang), abs(ang - PI), abs(ang - TAU))  # 离 ±Z 轴的角距
		if axis_dist < gap_rad:
			continue
		var radius: float = GameConfig.SKYLINE_RING_INNER_M + rng.randf_range(
			-GameConfig.SKYLINE_RING_INNER_JITTER_M, GameConfig.SKYLINE_RING_INNER_JITTER_M)
		var w := rng.randf_range(18.0, 38.0)
		var d := rng.randf_range(18.0, 38.0)
		var h := rng.randf_range(45.0, 150.0)
		# 贴图分配：高塔大概率办公幕墙，15% 霓虹媒体立面，其余住宅
		var mat := mat_residential
		var roll := rng.randf()
		if h > 90.0 and roll < 0.15:
			mat = mat_neon
		elif roll < 0.55:
			mat = mat_office
		_spawn_tower("SkylineInner_%02d" % placed, ang, radius, w, h, d, mat, rng, 1.0)
		placed += 1

	# 轴线地标塔：-Z 街道尽头视线走廊的远景焦点（霓虹/办公高塔）
	for i in GameConfig.SKYLINE_AXIS_TOWERS.size():
		var spec: Array = GameConfig.SKYLINE_AXIS_TOWERS[i]
		var mat := mat_neon if i == 0 else mat_office
		_spawn_tower("SkylineAxis_%d" % i, PI + spec[2], spec[0], 32.0, spec[1], 32.0,
			mat, rng, GameConfig.SKYLINE_AXIS_BRIGHTNESS)

	# 外环剪影：体块更大更暗，压暗的住宅贴图（在走廊尽头充当远景层次）
	for i in GameConfig.SKYLINE_TOWER_COUNT_OUTER:
		var ang := rng.randf() * TAU
		var radius: float = GameConfig.SKYLINE_RING_OUTER_M + rng.randf_range(
			-GameConfig.SKYLINE_RING_OUTER_JITTER_M, GameConfig.SKYLINE_RING_OUTER_JITTER_M)
		var w := rng.randf_range(40.0, 80.0)
		var d := rng.randf_range(40.0, 80.0)
		var h := rng.randf_range(80.0, 200.0)
		_spawn_tower("SkylineOuter_%02d" % i, ang, radius, w, h, d, mat_silhouette, rng, 0.5)

	_build_panorama_cards(rng)


## 一栋塔楼 = 单盒体贴立面贴图（贴图自带基座-皇冠完整构图）+ 天线桅杆（可选）
func _spawn_tower(node_name: String, ang: float, radius: float, w: float, h: float, d: float,
		mat: ShaderMaterial, rng: RandomNumberGenerator, brightness: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)
	add_child(root)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.position = Vector3(0.0, h * 0.5, 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("brightness", brightness)
	mi.set_instance_shader_parameter("flip_x", 1.0 if rng.randf() < 0.5 else 0.0)
	root.add_child(mi)

	# 天线桅杆：>70m 半数，>航空障碍灯高度强制（顶端红灯由 shader 闪烁）
	if h > 70.0 and (rng.randf() < GameConfig.SKYLINE_ANTENNA_RATIO
			or h > GameConfig.SKYLINE_BEACON_MIN_HEIGHT_M):
		var ah := rng.randf_range(5.0, 10.0)
		var a_mesh := BoxMesh.new()
		a_mesh.size = Vector3(0.7, ah, 0.7)
		var antenna := MeshInstance3D.new()
		antenna.name = "Antenna"
		antenna.mesh = a_mesh
		antenna.position = Vector3(0.0, h + ah * 0.5, 0.0)
		antenna.material_override = _mat_antenna
		antenna.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		antenna.set_instance_shader_parameter("seed_offset", rng.randf() * 97.0)
		antenna.set_instance_shader_parameter("tower_height", h + ah)
		antenna.set_instance_shader_parameter("brightness", brightness)
		antenna.set_instance_shader_parameter("is_antenna", 1.0)
		root.add_child(antenna)


func _make_facade_material(tex_path: String, wall_darken: float, emit_gain: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_FACADE)
	mat.set_shader_parameter("facade_tex", load(tex_path))
	mat.set_shader_parameter("wall_darken", wall_darken)
	mat.set_shader_parameter("emit_gain", emit_gain)
	return mat


## 全景幕布卡环带：面朝原点的 QuadMesh 卡片交替贴两张 AI 全景，边缘羽化交叠。
## sky_color 从场景 WorldEnvironment 实时读取注入——天色改动自动同步到幕布卡，
## 保证幕布夜空与场景夜空永远一致（机主 2026-09-27 要求：禁止出现两个夜空的分界）。
func _build_panorama_cards(rng: RandomNumberGenerator) -> void:
	var sky_color := Color(0.024, 0.09, 0.18)  # 兜底值，与 street_test.tscn 天空一致
	var world_env := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null and world_env.environment.sky != null:
		var sky_mat := world_env.environment.sky.sky_material as ProceduralSkyMaterial
		if sky_mat != null:
			sky_color = sky_mat.sky_top_color
	var texs := [TEX_PANO_A, TEX_PANO_B]
	var count: int = GameConfig.SKYLINE_CARD_COUNT
	for i in count:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER_CARD)
		mat.set_shader_parameter("pano_tex", load(texs[i % texs.size()]))
		mat.set_shader_parameter("gain", 1.35)
		mat.set_shader_parameter("sky_color", sky_color)
		var ang := TAU * float(i) / float(count)
		var radius: float = GameConfig.SKYLINE_CARD_RADIUS_M + rng.randf_range(-40.0, 40.0)
		var mesh := QuadMesh.new()  # 竖直四边形，法线 +Z（PlaneMesh 默认平躺，不可用）
		mesh.size = Vector2(GameConfig.SKYLINE_CARD_WIDTH_M, GameConfig.SKYLINE_CARD_HEIGHT_M)
		var card := MeshInstance3D.new()
		card.name = "PanoCard_%d" % i
		card.mesh = mesh
		card.position = Vector3(sin(ang) * radius,
			GameConfig.SKYLINE_CARD_HEIGHT_M * 0.45, cos(ang) * radius)  # 地平线压低的构图
		card.rotation.y = ang + PI  # 面朝原点
		card.material_override = mat
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(card)
