## SkylineBuilder — CBD 远景天际线（多环带 LOD 几何，street_test 夜景配套）
##
## 方案（2026-09-27 机主批准）：不走天空盒贴图，用几何环带——
## - 内环（~180m）：低模塔楼盒体 + skyline_windows 程序化亮窗 shader；
## - 外环（~420m）：更大更暗的剪影体块，亮窗稀疏；
## - 主街轴线 ±SKYLINE_VISTA_GAP_DEG 扇区不放内环塔楼，街道尽头留视线走廊。
## 亮窗材质 render_mode fog_disabled，使灯光穿透夜雾（减薄后的夜雾仍会吞掉
## 180m 外的几何，fog_disabled 是夜景天际线可见的前提）。
## 布局由 GameConfig.SKYLINE_SEED 确定性生成；全部参数见 game_config.gd 契约。
extends Node3D

const SHADER_SKYLINE := "res://assets/shaders/skyline_windows.gdshader"


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.SKYLINE_SEED

	var mat_inner := _make_material(GameConfig.SKYLINE_LIT_RATIO)
	var mat_outer := _make_material(GameConfig.SKYLINE_LIT_RATIO_OUTER)

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
		var w := rng.randf_range(15.0, 35.0)
		var d := rng.randf_range(15.0, 35.0)
		var h := rng.randf_range(45.0, 150.0)
		_spawn_tower("SkylineInner_%02d" % placed, ang, radius, w, h, d, mat_inner, rng, 1.0)
		placed += 1

	# 外环剪影：体块更大更暗，不避扇区（在走廊尽头充当远景层次）
	for i in GameConfig.SKYLINE_TOWER_COUNT_OUTER:
		var ang := rng.randf() * TAU
		var radius: float = GameConfig.SKYLINE_RING_OUTER_M + rng.randf_range(
			-GameConfig.SKYLINE_RING_OUTER_JITTER_M, GameConfig.SKYLINE_RING_OUTER_JITTER_M)
		var w := rng.randf_range(40.0, 80.0)
		var d := rng.randf_range(40.0, 80.0)
		var h := rng.randf_range(80.0, 200.0)
		_spawn_tower("SkylineOuter_%02d" % i, ang, radius, w, h, d, mat_outer, rng, 0.5)


func _make_material(lit_ratio: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_SKYLINE)
	mat.set_shader_parameter("lit_ratio", lit_ratio)
	mat.set_shader_parameter("beacon_min_height", GameConfig.SKYLINE_BEACON_MIN_HEIGHT_M)
	return mat


func _spawn_tower(node_name: String, ang: float, radius: float, w: float, h: float, d: float,
		mat: ShaderMaterial, rng: RandomNumberGenerator, brightness: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = Vector3(sin(ang) * radius, h * 0.5, cos(ang) * radius)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed_offset", rng.randf() * 97.0)
	mi.set_instance_shader_parameter("tower_height", h)
	mi.set_instance_shader_parameter("brightness", brightness)
	add_child(mi)
