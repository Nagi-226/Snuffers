## SkylineBuilder — CBD 远景天际线 v2（多环带 LOD 几何 + 真实化立面，street_test 夜景配套）
##
## v2 相对 v1 的真实化（参考广州珠江新城类 CBD 夜景照片，详见 shader 头注）：
## - 体量退台：高塔由 2~3 段收分盒体叠成，不再是单一方盒；
## - 裙楼底座：约半数塔楼底部带更宽的商业裙楼（shader 中裙楼层更亮更暖）；
## - 天线桅杆：>70m 塔楼约半数顶部带细桅杆，顶端红色障碍灯闪烁；
## - LED 轮廓/竖向灯带、媒体立面由 instance uniform neon_mode/media_mode 驱动。
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
		_spawn_tower("SkylineInner_%02d" % placed, ang, radius, w, h, d, mat_inner, rng, 1.0, true)
		placed += 1

	# 轴线地标塔：-Z 街道尽头视线走廊的远景焦点（"广州塔式" anchor，契约 SKYLINE_AXIS_TOWERS）
	for i in GameConfig.SKYLINE_AXIS_TOWERS.size():
		var spec: Array = GameConfig.SKYLINE_AXIS_TOWERS[i]
		_spawn_tower("SkylineAxis_%d" % i, PI + spec[2], spec[0], 30.0, spec[1], 30.0,
			mat_inner, rng, GameConfig.SKYLINE_AXIS_BRIGHTNESS, true)

	# 外环剪影：体块更大更暗，单盒不细分（在走廊尽头充当远景层次）
	for i in GameConfig.SKYLINE_TOWER_COUNT_OUTER:
		var ang := rng.randf() * TAU
		var radius: float = GameConfig.SKYLINE_RING_OUTER_M + rng.randf_range(
			-GameConfig.SKYLINE_RING_OUTER_JITTER_M, GameConfig.SKYLINE_RING_OUTER_JITTER_M)
		var w := rng.randf_range(40.0, 80.0)
		var d := rng.randf_range(40.0, 80.0)
		var h := rng.randf_range(80.0, 200.0)
		_spawn_tower("SkylineOuter_%02d" % i, ang, radius, w, h, d, mat_outer, rng, 0.5, false)


func _make_material(lit_ratio: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_SKYLINE)
	mat.set_shader_parameter("lit_ratio", lit_ratio)
	mat.set_shader_parameter("dark_floor_ratio", GameConfig.SKYLINE_DARK_FLOOR_RATIO)
	mat.set_shader_parameter("podium_height", GameConfig.SKYLINE_PODIUM_HEIGHT_M)
	return mat


## 一栋塔楼 = 裙楼（可选）+ 1~3 段退台主体 + 天线桅杆（可选）
func _spawn_tower(node_name: String, ang: float, radius: float, w: float, h: float, d: float,
		mat: ShaderMaterial, rng: RandomNumberGenerator, brightness: float, detailed: bool) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)
	add_child(root)

	var seed_off := rng.randf() * 97.0
	var neon := 0.0
	var media := 0.0
	if detailed:
		if rng.randf() < GameConfig.SKYLINE_NEON_RATIO:
			var r := rng.randf()
			neon = 1.0 if r < 0.5 else (2.0 if r < 0.8 else 3.0)  # 冷蓝白/暖金/变色
		if h > 90.0 and rng.randf() < GameConfig.SKYLINE_MEDIA_RATIO:
			media = 1.0
	else:
		if rng.randf() < 0.1:
			neon = 1.0

	# 裙楼底座（更宽的商业底座，shader 按世界高度提亮）
	var body_base_y := 0.0
	if detailed and rng.randf() < GameConfig.SKYLINE_PODIUM_RATIO:
		var ph: float = GameConfig.SKYLINE_PODIUM_HEIGHT_M
		_spawn_box(root, "Podium", w * 1.18, ph, d * 1.18, ph * 0.5,
			mat, seed_off, h, brightness, neon, media, 0.0)
		body_base_y = 0.0  # 主体仍从地面起（裙楼外包底部），退台段在上方

	# 主体退台段：高塔 2~3 段收分，矮塔单段
	var sections := 1
	if detailed:
		if h > 110.0:
			sections = 3
		elif h > 70.0:
			sections = 2
	var y := body_base_y
	var sec_w := w
	var sec_d := d
	for s in sections:
		var sec_h := (h - body_base_y) / float(sections)
		_spawn_box(root, "Section_%d" % s, sec_w, sec_h, sec_d, y + sec_h * 0.5,
			mat, seed_off, h, brightness, neon, media, 0.0)
		y += sec_h
		sec_w *= 0.78
		sec_d *= 0.78

	# 天线桅杆（顶端障碍灯由 shader 依据 tower_height 闪烁）；
	# 超过航空障碍灯高度的塔楼必装桅杆（写实：高层强制航空障碍灯）
	if detailed and h > 70.0 and (rng.randf() < GameConfig.SKYLINE_ANTENNA_RATIO
			or h > GameConfig.SKYLINE_BEACON_MIN_HEIGHT_M):
		var ah := rng.randf_range(5.0, 10.0)
		_spawn_box(root, "Antenna", 0.7, ah, 0.7, h + ah * 0.5,
			mat, seed_off, h + ah, brightness, 0.0, 0.0, 1.0)


func _spawn_box(parent: Node3D, node_name: String, w: float, h: float, d: float, center_y: float,
		mat: ShaderMaterial, seed_off: float, tower_h: float, brightness: float,
		neon: float, media: float, antenna: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = Vector3(0.0, center_y, 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed_offset", seed_off)
	mi.set_instance_shader_parameter("tower_height", tower_h)
	mi.set_instance_shader_parameter("brightness", brightness)
	mi.set_instance_shader_parameter("neon_mode", neon)
	mi.set_instance_shader_parameter("media_mode", media)
	mi.set_instance_shader_parameter("is_antenna", antenna)
	parent.add_child(mi)
