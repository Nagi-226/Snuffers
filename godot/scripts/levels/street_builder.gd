extends Node3D
## P0 街区 builder — 解释布局数据表生成几何与碰撞。
## 借鉴 Claude-of-Duty：builder 不含尺寸硬编码；调色板限定命名集（文档10 §1-P1 纪律）。
## P0 阶段材质为纯色占位；P1 将替换为程序化 shader（混凝土/沥青/锈蚀金属）。

## 布局数据表（preload 而非 class_name 全局缓存，避免 headless 首次导入时序问题）
const Layout := preload("res://scripts/levels/street_layout_test.gd")

## 限定调色板（tint 控制在 0.02–0.9 反射率区间，见文档10）
const PALETTE := {
	"asphalt": Color(0.14, 0.14, 0.145),
	"kerb": Color(0.42, 0.41, 0.39),
	"dirt": Color(0.42, 0.34, 0.22),
	"gravel": Color(0.38, 0.37, 0.35),
	"plaster_cream": Color(0.81, 0.75, 0.64),
	"plaster_sand": Color(0.73, 0.65, 0.51),
	"plaster_white": Color(0.85, 0.82, 0.77),
	"plaster_pink": Color(0.75, 0.60, 0.53),
	"brick": Color(0.66, 0.52, 0.42),
	"wire_dark": Color(0.045, 0.045, 0.05),
	"metal_dark": Color(0.10, 0.10, 0.11),
	"rubber_dark": Color(0.03, 0.03, 0.032),
	"canvas_red": Color(0.52, 0.14, 0.12),
	"plastic_white": Color(0.80, 0.79, 0.74),
	"fence_metal": Color(0.30, 0.33, 0.30),
}

var _materials := {}

## P1 程序化 shader 调色板映射: key → [shader路径, world_scale, seed]
## 尺度分档纪律（文档10 §1-P1）：建筑面 2.5m 周期，金属件 1.2m 更密，
## 道具级混凝土 1.0m 最密（「2.5m 贴图贴在 0.5m 块上会糊成塑料感」）
const SHADER_MAP := {
	"asphalt": ["res://assets/shaders/mat_asphalt.gdshader", 2.5, 47.0],
	"kerb": ["res://assets/shaders/mat_concrete.gdshader", 2.5, 11.0],
	"rust_metal": ["res://assets/shaders/mat_rust_metal.gdshader", 1.2, 23.0],
	"concrete_prop": ["res://assets/shaders/mat_concrete.gdshader", 1.0, 31.0],
	"paving": ["res://assets/shaders/mat_paving.gdshader", 1.0, 5.0],
}


func _ready() -> void:
	_apply_fog()
	_compute_barriers()  # 围挡需在 backdrop 前算好（墙体要进楼块排除区）
	_build_ground()
	_build_buildings()
	_build_backdrop()
	_build_barriers()
	_build_props()
	# 开发者截图: godot --path . res://scenes/levels/street_test.tscn -- --shot <输出路径>
	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		var out_path := "user://street_test_shot.png"
		var idx := args.find("--shot")
		if idx + 1 < args.size():
			out_path = args[idx + 1]
		for i in 15:
			await get_tree().process_frame
		var cam := get_node("OverviewCamera") as Camera3D
		print("STREET_DEBUG children=%d ground=%d bldgs=%d cam_forward=%s cam_pos=%s" % [
			get_child_count(), get_node("Ground").get_child_count(),
			get_node("Buildings").get_child_count(),
			-cam.global_transform.basis.z, cam.global_position])
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out_path)
		print("STREET_SHOT saved=%s err=%d" % [out_path, err])
		get_tree().quit()


func _get_material(key: String) -> Material:
	if not _materials.has(key):
		if SHADER_MAP.has(key):
			var entry: Array = SHADER_MAP[key]
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = load(entry[0])
			shader_mat.set_shader_parameter("world_scale", entry[1])
			shader_mat.set_shader_parameter("seed", entry[2])
			_materials[key] = shader_mat
		elif key == "edaa_field":
			# EDAA 能量屏蔽力场（程序化 shader，纵向扫描带+两端增亮+微闪烁）
			var field_mat := ShaderMaterial.new()
			field_mat.shader = load("res://assets/shaders/mat_energy_field.gdshader")
			_materials[key] = field_mat
		elif key == "edaa_blue_glow":
			# 发射柱顶部发光帽：暗蓝底 + 青蓝发光
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(0.05, 0.12, 0.25)
			glow.emission_enabled = true
			glow.emission = Color(0.35, 0.70, 1.0)
			glow.emission_energy_multiplier = 2.2
			_materials[key] = glow
		elif key == "hazard_red":
			# EDAA 路障警示灯条：暗红底 + 红发光（夜里路障的远距离可读性）
			var hazard := StandardMaterial3D.new()
			hazard.albedo_color = Color(0.35, 0.05, 0.05)
			hazard.emission_enabled = true
			hazard.emission = Color(1.0, 0.15, 0.1)
			hazard.emission_energy_multiplier = 1.6
			_materials[key] = hazard
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = PALETTE.get(key, Color(0.5, 0.5, 0.5))
			mat.roughness = 0.9
			_materials[key] = mat
	return _materials[key]


## 在 parent 下生成一个带碰撞的盒体块。center 为盒中心，size 为全尺寸。
## tint ≠ 白时复制材质并线性乘算 albedo（逐楼个体差异，文档10 tint 纪律：0.02–0.9 反射率区间）
func _add_box(parent: Node3D, name: String, center: Vector3, size: Vector3, palette_key: String,
		tint := Color(1, 1, 1)) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = center

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := _get_material(palette_key)
	if tint != Color(1, 1, 1) and mat is StandardMaterial3D:
		var tinted: StandardMaterial3D = mat.duplicate()
		tinted.albedo_color = Color(mat.albedo_color.r * tint.r,
			mat.albedo_color.g * tint.g, mat.albedo_color.b * tint.b)
		mat = tinted
	box.material = mat
	mesh_inst.mesh = box
	body.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	parent.add_child(body)


func _build_ground() -> void:
	var s: Dictionary = Layout.STREET
	var z_len: float = s["z_max"] - s["z_min"]
	var z_mid: float = (s["z_max"] + s["z_min"]) * 0.5

	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)

	# 外围大地面（兜底地皮，覆盖整张地图外加足量边距，避免任何角度看到天空地线）
	_add_box(ground, "OuterGround", Vector3(0, -0.08, z_mid),
		Vector3(200.0, 0.1, z_len + 320.0), "dirt")
	# 沥青主街（略低于人行道顶面，避免 z-fighting）
	_add_box(ground, "Asphalt", Vector3(0, -0.05, z_mid),
		Vector3(s["half_width"] * 2.0, 0.1, z_len), "asphalt")
	# 两侧人行道
	var walk_w: float = s["kerb"] - s["half_width"]
	for side in [-1.0, 1.0]:
		var x: float = side * (s["half_width"] + walk_w * 0.5)
		_add_box(ground, "Sidewalk_%s" % ("W" if side < 0 else "E"), Vector3(x, s["walk_h"] * 0.5, z_mid),
			Vector3(walk_w, s["walk_h"], z_len), "kerb")
	# 巷道/空地地面
	for i in Layout.ALLEYS.size():
		var alley: Dictionary = Layout.ALLEYS[i]
		var r: Array = alley["rect"]
		var w: float = absf(r[2] - r[0])
		var d: float = absf(r[3] - r[1])
		var cx: float = (r[0] + r[2]) * 0.5
		var cz: float = (r[1] + r[3]) * 0.5
		_add_box(ground, "Alley_%d" % i, Vector3(cx, 0.02, cz),
			Vector3(w, 0.1, d), alley["surface"])
	# 南端 T 字横街：沥青 + 南侧人行道（主街不再被建筑堵死，机主 2026-09-27 裁决）
	var c: Dictionary = Layout.CROSS
	var c_x_len: float = c["x_max"] - c["x_min"]
	var c_z_mid: float = (c["z_min"] + c["z_max"]) * 0.5
	_add_box(ground, "CrossAsphalt", Vector3(0, -0.05, c_z_mid),
		Vector3(c_x_len, 0.1, c["z_max"] - c["z_min"]), "asphalt")
	# 横街南侧人行道：南延走廊（x=±6.5 以内）断开，让主街向南贯通（2026-09-27 机主裁决）
	var sw_d: float = c["walk_south_z"] - c["z_max"]
	var sw_half: float = (c_x_len * 0.5 - s["kerb"]) * 0.5
	var sw_x: float = s["kerb"] + sw_half
	_add_box(ground, "CrossSidewalk_SW", Vector3(-sw_x, s["walk_h"] * 0.5, c["z_max"] + sw_d * 0.5),
		Vector3(sw_half * 2.0, s["walk_h"], sw_d), "kerb")
	_add_box(ground, "CrossSidewalk_SE", Vector3(sw_x, s["walk_h"] * 0.5, c["z_max"] + sw_d * 0.5),
		Vector3(sw_half * 2.0, s["walk_h"], sw_d), "kerb")
	# 主街南延段：沥青 + 两侧人行道，延伸进夜雾（SOUTH_EXT，南端力场幕墙外）
	var se: Dictionary = Layout.SOUTH_EXT
	var se_len: float = se["z_max"] - se["z_min"]
	var se_mid: float = (se["z_max"] + se["z_min"]) * 0.5
	_add_box(ground, "SouthAsphalt", Vector3(0, -0.05, se_mid),
		Vector3(s["half_width"] * 2.0, 0.1, se_len), "asphalt")
	for side in [-1.0, 1.0]:
		var sx: float = side * (s["half_width"] + walk_w * 0.5)
		_add_box(ground, "SouthSidewalk_%s" % ("W" if side < 0 else "E"), Vector3(sx, s["walk_h"] * 0.5, se_mid),
			Vector3(walk_w, s["walk_h"], se_len), "kerb")
	# 横街两端铁栅栏门 + 北端 EDAA 路障（分段加载气闸/边界合理化，文档11 §6.6、文档12）
	for barrier in Layout.BARRIERS:
		_add_box(ground, barrier["id"],
			Vector3(barrier["x"], barrier["h"] * 0.5, barrier["z"]),
			Vector3(barrier["w"], barrier["h"], barrier["d"]),
			barrier.get("palette", "rust_metal"))
		if barrier.get("hazard", false):  # 警示灯条贴在隔离墩顶面前沿
			_add_box(ground, "%s_hazard" % barrier["id"],
				Vector3(barrier["x"], barrier["h"] + 0.04, barrier["z"]),
				Vector3(barrier["w"] * 0.8, 0.08, barrier["d"] * 0.8), "hazard_red")
		if barrier.get("tip_glow", false):  # 发射柱蓝色发光帽
			_add_box(ground, "%s_tip" % barrier["id"],
				Vector3(barrier["x"], barrier["h"] + 0.15, barrier["z"]),
				Vector3(barrier["w"] + 0.16, 0.3, barrier["d"] + 0.16), "edaa_blue_glow")
		if barrier.get("palette", "") == "edaa_field":
			# 力场蓝光灯：把能量场的光晕投到路面与两侧墙根
			var glow_light := OmniLight3D.new()
			glow_light.name = "%s_light" % barrier["id"]
			glow_light.position = Vector3(barrier["x"], 2.6, barrier["z"] + 0.8)
			glow_light.light_color = Color(0.35, 0.65, 1.0)
			glow_light.light_energy = 1.1
			glow_light.omni_range = 9.0
			glow_light.shadow_enabled = false
			ground.add_child(glow_light)


func _build_buildings() -> void:
	var s: Dictionary = Layout.STREET
	var row := Node3D.new()
	row.name = "Buildings"
	add_child(row)

	var rng := RandomNumberGenerator.new()
	for bi in Layout.BUILDINGS.size():
		var b: Dictionary = Layout.BUILDINGS[bi]
		rng.seed = GameConfig.STREET_DRESS_SEED + bi * 7919
		# ② tint 个体差异：逐楼 albedo 抖动 ±STREET_TINT_JITTER（去复制粘贴感）
		var j: float = GameConfig.STREET_TINT_JITTER
		var tint := Color(1.0 - j + rng.randf() * j * 2.0,
			1.0 - j + rng.randf() * j * 2.0, 1.0 - j + rng.randf() * j * 2.0)
		var h: float = b["floors"] * s["floor_h"]
		# 结构盒沿临街轴内缩 0.3m，给立面套件的门窗内退件让位（否则玻璃/门板被埋）
		# 立面法线沿 Z 的（门楼/横街南排）缩 Z，沿 X 的（东西排）缩 X
		var size := Vector3(b["w"], h, b["d"])
		if absf(b["x"]) < 0.1 or b.get("face", "") != "":
			size.z -= 0.3
		else:
			size.x -= 0.3
		_add_box(row, "Bldg_%s" % b["id"],
			Vector3(b["x"], h * 0.5, b["z"]), size, b["palette"], tint)
		_dress_facade(row, b, s["floor_h"], rng)
		# 巷弄立面：临街排楼的背街面/侧面若与巷弄院落相邻，补门窗（2026-09-27 机主裁决）
		if b.get("face", "") == "" and absf(b["x"]) > 0.1:
			_dress_alley_faces(row, b, s["floor_h"], rng)
	_build_wires(rng)


## P1 立面套件（Blender headless 烘焙，build_facade_kit.py）
## P2 道具套件（build_props_kit.py）：shopfront 卷帘门商铺 / ac_unit 空调外机 / drainpipe 排水管
const KIT := {
	"wall": preload("res://assets/models/kit_wall.glb"),
	"window": preload("res://assets/models/kit_window.glb"),
	"door": preload("res://assets/models/kit_door.glb"),
	"balcony": preload("res://assets/models/kit_balcony.glb"),
	"shopfront": preload("res://assets/models/kit_shopfront.glb"),
	"ac_unit": preload("res://assets/models/kit_ac_unit.glb"),
	"drainpipe": preload("res://assets/models/kit_drainpipe.glb"),
}

const KIT_BAY := 3.0  # 套件开间宽，与 layout floor_h=3.0 对齐


## 夜雾定标（契约: GameConfig.NIGHT_FOG_*）——指数深度雾，60m 能见度目标
## street_test 已固化为蓝调时刻夜景：夜里本身能见度低，雾比白天浓雾（FOG_* 30m）减薄一半
func _apply_fog() -> void:
	var env: Environment = get_node("WorldEnvironment").environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = GameConfig.NIGHT_FOG_DENSITY
	env.fog_light_color = GameConfig.NIGHT_FOG_LIGHT_COLOR
	env.fog_sun_scatter = GameConfig.NIGHT_FOG_SUN_SCATTER
	env.fog_sky_affect = GameConfig.NIGHT_FOG_SKY_AFFECT


## 巷弄邻接扫描：临街排楼的非临街面，外推 5m 条带与任一巷弄/院落相交 → 该面临巷，补门窗
func _dress_alley_faces(parent: Node3D, b: Dictionary, floor_h: float, rng: RandomNumberGenerator) -> void:
	var street_out := Vector3(1, 0, 0) if b["x"] < 0.0 else Vector3(-1, 0, 0)
	var candidates := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for o in candidates:
		if o == street_out:
			continue
		var wall_len: float = b["d"] if o.x != 0.0 else b["w"]
		var half_along := wall_len * 0.5
		var rect: Array
		if o.x != 0.0:
			var cx: float = b["x"] + o.x * (b["w"] * 0.5 + 2.5)
			rect = [cx - 2.5, b["z"] - half_along, cx + 2.5, b["z"] + half_along]
		else:
			var cz: float = b["z"] + o.z * (b["d"] * 0.5 + 2.5)
			rect = [b["x"] - half_along, cz - 2.5, b["x"] + half_along, cz + 2.5]
		for alley in Layout.ALLEYS:
			if _rects_overlap(rect[0], rect[1], rect[2], rect[3], alley["rect"]):
				_dress_facade(parent, b, floor_h, rng, true, o)
				break


## 临街立面逐开间装配（panel space：件原点在地板线、前墙面，墙身向内侧延伸）
## 一层：中间开间恒为卷帘门商铺，其余开间按 SHOPFRONT_RATIO 改商铺/留窗（城中村底商）；
## 二层中间开间为阳台，上层窗户按 AC_UNIT_RATIO 挂空调外机；开间边线稀疏落排水管
func _dress_facade(parent: Node3D, b: Dictionary, floor_h: float, rng: RandomNumberGenerator,
		alley_mode := false, override_outward := Vector3.ZERO) -> void:
	var outward: Vector3
	var wall_len: float
	var facing: String = b.get("face", "")
	if override_outward != Vector3.ZERO:  # 巷弄立面：显式指定朝向
		outward = override_outward
		wall_len = b["d"] if outward.x != 0.0 else b["w"]
	elif facing == "n":  # 横街南排：面朝北（-Z），临街轴为 X
		outward = Vector3(0, 0, -1)
		wall_len = b["w"]
	elif absf(b["x"]) < 0.1:  # 门楼横跨街道，面朝 +Z
		outward = Vector3(0, 0, 1)
		wall_len = b["w"]
	elif b["x"] < 0.0:
		outward = Vector3(1, 0, 0)
		wall_len = b["d"]
	else:
		outward = Vector3(-1, 0, 0)
		wall_len = b["d"]
	var rot_y := 90.0 if outward.x > 0.0 else (-90.0 if outward.x < 0.0 else (180.0 if outward.z < 0.0 else 0.0))

	var n: int = maxi(1, int(floor(wall_len / KIT_BAY)))
	var total := n * KIT_BAY
	var face := Vector3(b["x"], 0.0, b["z"])
	if outward.x > 0.0:
		face.x += b["w"] * 0.5
	elif outward.x < 0.0:
		face.x -= b["w"] * 0.5
	elif outward.z < 0.0:
		face.z -= b["d"] * 0.5  # 面朝北：锚点在北墙面
	else:
		face.z += b["d"] * 0.5

	## 沿墙局部偏移 → 世界坐标（垂直墙面外凸 0.02 防共面闪面）
	var place := func(kind: String, off: float, y: float, push := 0.02) -> Node3D:
		var inst: Node3D = KIT[kind].instantiate()
		var pos := face + outward * push
		if outward.x != 0.0:
			pos.z += off
		else:
			pos.x += off
		pos.y = y
		inst.position = pos
		inst.rotation_degrees.y = rot_y
		parent.add_child(inst)
		return inst

	for f in b["floors"]:
		for i in n:
			var kind := "window"
			if alley_mode:
				# 巷弄立面：一层中间开间开后门，其余窗户；无商铺/阳台（背街生活面）
				if f == 0 and i == n / 2:
					kind = "door"
			elif f == 0:
				# 一层底商：中间开间恒商铺，其余按概率
				if i == n / 2 or rng.randf() < GameConfig.SHOPFRONT_RATIO:
					kind = "shopfront"
			elif f == 1 and i == n / 2:
				kind = "balcony"
			var off := -total * 0.5 + (float(i) + 0.5) * KIT_BAY
			place.call(kind, off, float(f) * floor_h)
			# 空调外机：上层窗下沿，横向错开 0.7m 不挡窗
			if f >= 1 and kind == "window" and rng.randf() < GameConfig.AC_UNIT_RATIO:
				place.call("ac_unit", off + (0.7 if rng.randf() < 0.5 else -0.7),
					float(f) * floor_h + 0.2, 0.05)
	# 排水管：开间边线每隔 2 条落一根，贯通全高
	for e in n + 1:
		if (e + b["id"].hash()) % 3 != 0:
			continue
		var off := -total * 0.5 + float(e) * KIT_BAY
		for f in b["floors"]:
			place.call("drainpipe", off, float(f) * floor_h, 0.05)


## 跨街悬链线电线（P2 道具布景层，文档10 §1-P2 catenaryTube 思路的 GDScript 实现）
## 在主街两侧立面之间拉线：垂度/高度/间距全部抖动，30% 概率双线并行——城中村天空分割感
func _build_wires(rng: RandomNumberGenerator) -> void:
	var s: Dictionary = Layout.STREET
	var wires := Node3D.new()
	wires.name = "Wires"
	add_child(wires)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE["wire_dark"]
	mat.roughness = 0.6

	var z: float = maxf(s["z_min"] + 5.0, s.get("wire_z_min", s["z_min"] + 5.0))
	while z < s["z_max"] - 4.0:
		var h0 := rng.randf_range(GameConfig.WIRE_HEIGHT_MIN_M, GameConfig.WIRE_HEIGHT_MAX_M)
		var h1 := clampf(h0 + rng.randf_range(-0.5, 0.5),
			GameConfig.WIRE_HEIGHT_MIN_M, GameConfig.WIRE_HEIGHT_MAX_M)
		var sag: float = GameConfig.WIRE_SAG_M * rng.randf_range(0.5, 1.5)
		var pair := 1 + (1 if rng.randf() < 0.3 else 0)  # 30% 双线
		for k in pair:
			var p0 := Vector3(-s["kerb"] - 0.02, h0 - k * 0.18, z + rng.randf_range(-0.4, 0.4))
			var p1 := Vector3(s["kerb"] + 0.02, h1 - k * 0.18, z + rng.randf_range(-0.4, 0.4))
			var mi := MeshInstance3D.new()
			mi.name = "Wire_%.0f_%d" % [z, k]
			mi.mesh = _make_wire_mesh(p0, p1, sag)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wires.add_child(mi)
		z += GameConfig.WIRE_SPACING_M * rng.randf_range(0.7, 1.4)


## 悬链线（小垂度近似抛物线）圆管网格：12 段 × 5 边
func _make_wire_mesh(p0: Vector3, p1: Vector3, sag: float) -> ArrayMesh:
	var segs := 12
	var sides := 5
	var radius := 0.018
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var up_hint := Vector3.UP
	for i in segs + 1:
		var t := float(i) / float(segs)
		var p := p0.lerp(p1, t)
		p.y -= 4.0 * sag * t * (1.0 - t)
		# 切线（抛物线导数）→ 局部坐标架
		var tangent := (p1 - p0).normalized()
		tangent.y -= 4.0 * sag * (1.0 - 2.0 * t) / (p0.distance_to(p1))
		tangent = tangent.normalized()
		var side := tangent.cross(up_hint).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(tangent).normalized()
		for k in sides:
			var a := TAU * float(k) / float(sides)
			verts.append(p + (side * cos(a) + up * sin(a)) * radius)
	for i in segs:
		for k in sides:
			var a := i * sides + k
			var b := i * sides + (k + 1) % sides
			var c := (i + 1) * sides + k
			var d := (i + 1) * sides + (k + 1) % sides
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## —— 巷弄生活道具（P2 布景层，RE3 式街区丰富度，2026-09-27 机主裁决）——
## 全部用引擎原语装配（柱/环/盒），正式美术件待道具批2走 Blender 烘焙替换

func _build_props() -> void:
	var row := Node3D.new()
	row.name = "Props"
	add_child(row)
	for i in Layout.PROPS.size():
		var p: Dictionary = Layout.PROPS[i]
		var prop := Node3D.new()
		prop.name = "Prop_%s_%d" % [p["type"], i]
		prop.position = Vector3(p["x"], p.get("y", 0.0), p["z"])
		prop.rotation_degrees.y = p.get("rot_y", 0.0)
		row.add_child(prop)
		match p["type"]:
			"basket_hoop":
				_prop_basket_hoop(prop)  # 原语架体 + 开源篮圈篮网（内部自动回退）
			"basketball":
				# 散落篮球（开源件提取 Sphere 子节点，CC0 Armory_3D）
				var ball := _attach_extract(prop, "res://assets/models/prop_basketball_hoop.glb", "Sphere", 0.24)
				if ball:
					ball.position = Vector3(0, 0.12, 0)
					_add_prop_collider(prop, Vector3(0.26, 0.26, 0.26), Vector3(0, 0.12, 0))
				else:
					_add_part(prop, _make_cyl(0.12, 0.12, 0.24, 10), Vector3(0, 0.12, 0), "canvas_red")
			"bike":
				# 开源模型优先（Poly Pizza CC-BY，署名见 ATTRIBUTION.md 五）
				if not _prop_model(prop, "res://assets/models/prop_bicycle.glb",
						1.1, Vector3(1.75, 1.1, 0.5), Vector3(0, 0.55, 0)):
					_prop_bike(prop)
			"bistro_set":
				_prop_bistro_set(prop)
			"trash_bin":
				_prop_trash_bin(prop)
			_:
				push_warning("street_builder: unknown prop type %s" % p["type"])


## 道具局部零件（原语网格 + 调色板材质，无独立碰撞）
func _add_part(parent: Node3D, mesh: PrimitiveMesh, offset: Vector3,
		palette_key: String, rot_deg := Vector3.ZERO) -> void:
	mesh.material = _get_material(palette_key)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)


## 道具整体碰撞盒（单盒近似，y_center 为盒中心局部高度）
func _add_prop_collider(prop: Node3D, size: Vector3, center := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	prop.add_child(body)


func _make_cyl(r_top: float, r_bottom: float, h: float, sides := 10) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bottom
	cyl.height = h
	cyl.radial_segments = sides
	return cyl


func _make_torus(r_ring: float, r_tube: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = r_ring - r_tube
	torus.outer_radius = r_ring + r_tube
	torus.rings = 16
	torus.ring_segments = 6
	return torus


## 开源模型道具归一化：量全局包围盒 → 等比缩放到目标高度 → 落地居中 → 附碰撞盒
## 模型源任意尺度/原点（poly.pizza GLB 常见厘米级与偏移原点），全部在运行态归一
func _prop_model(prop: Node3D, path: String, target_h: float,
		collider_size: Vector3, collider_center: Vector3) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	prop.add_child(inst)
	var aabb := AABB()
	var first := true
	for mi in _find_mesh_instances(inst):
		var local: AABB = (prop.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		if first:
			aabb = local
			first = false
		else:
			aabb = aabb.merge(local)
	if first or aabb.size.y <= 0.001:
		prop.remove_child(inst)
		inst.queue_free()
		return false
	var s: float = target_h / aabb.size.y
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)
	_add_prop_collider(prop, collider_size, collider_center)
	return true


## 从 GLB 提取具名子树挂到 prop 下：等比缩放到 target_max（包围盒最大边）、
## 包围盒中心对齐到新 holder 原点。返回 holder（调用方再摆位/旋转），失败 null
func _attach_extract(prop: Node3D, path: String, node_name: String, target_max: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	prop.add_child(inst)
	var node: Node3D = inst.find_child(node_name, true, false) as Node3D
	if node == null:
		prop.remove_child(inst)
		inst.free()
		return null
	var holder := Node3D.new()
	holder.name = "Extract_%s" % node_name
	prop.add_child(holder)
	node.get_parent().remove_child(node)
	holder.add_child(node)
	prop.remove_child(inst)
	inst.free()
	# 量 holder 包围盒（prop 局部空间）→ 缩放 + 居中（居中偏移落在子节点上，
	# holder 的 position/rotation 留给调用方摆位）
	var aabb := AABB()
	var first := true
	for mi in _find_mesh_instances(holder):
		var local: AABB = (prop.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		if first:
			aabb = local
			first = false
		else:
			aabb = aabb.merge(local)
	if first:
		return null
	var s: float = target_max / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	holder.scale = Vector3.ONE * s
	# 内容中心归零：P_new = P_auth − C（赋值会丢失节点原始偏移，导致二次平移）
	node.position -= aabb.get_center()
	return holder


func _find_mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


## 篮球架：立杆 + 伸臂 + 篮板（原语）+ 篮圈带真篮网（开源件 ring 子树提取，CC0 Armory_3D）
func _prop_basket_hoop(prop: Node3D) -> void:
	_add_part(prop, _make_cyl(0.06, 0.06, 3.2), Vector3(0, 1.6, -0.9), "metal_dark")
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 0.95)
	_add_part(prop, arm, Vector3(0, 3.35, -0.45), "metal_dark")
	var board := BoxMesh.new()
	board.size = Vector3(1.2, 0.9, 0.05)
	_add_part(prop, board, Vector3(0, 3.05, 0.0), "plastic_white")
	var ring := _attach_extract(prop, "res://assets/models/prop_basketball_hoop.glb", "ring", 0.46)
	if ring:
		ring.rotation_degrees = Vector3.ZERO  # 模型内已烘平放变换，不再补偿
		ring.position = Vector3(0, 3.0, 0.38)
	else:
		_add_part(prop, _make_torus(0.23, 0.02), Vector3(0, 2.95, 0.35), "rust_metal", Vector3(90, 0, 0))
	_add_prop_collider(prop, Vector3(0.4, 3.4, 1.3), Vector3(0, 1.7, -0.4))


## 自行车：双轮 + 大梁 + 座管 + 车把（局部 X 为车身长向，靠墙停放剪影）
func _prop_bike(prop: Node3D) -> void:
	for sx in [-0.55, 0.55]:
		_add_part(prop, _make_torus(0.32, 0.025), Vector3(sx, 0.32, 0), "rubber_dark")
	var frame := BoxMesh.new()
	frame.size = Vector3(0.95, 0.05, 0.05)
	_add_part(prop, frame, Vector3(0, 0.55, 0), "metal_dark")
	var seat_post := BoxMesh.new()
	seat_post.size = Vector3(0.05, 0.35, 0.05)
	_add_part(prop, seat_post, Vector3(-0.25, 0.72, 0), "metal_dark")
	var bar := BoxMesh.new()
	bar.size = Vector3(0.05, 0.05, 0.42)
	_add_part(prop, bar, Vector3(0.55, 0.88, 0), "metal_dark")
	_add_prop_collider(prop, Vector3(1.25, 1.0, 0.3), Vector3(0, 0.5, 0))


## 露天小酒馆单元：圆桌 + 伞 + 对椅（局部 ±X 两侧落座）
func _prop_bistro_set(prop: Node3D) -> void:
	_add_part(prop, _make_cyl(0.42, 0.42, 0.05, 14), Vector3(0, 0.72, 0), "plastic_white")
	_add_part(prop, _make_cyl(0.04, 0.04, 0.72), Vector3(0, 0.36, 0), "metal_dark")
	_add_part(prop, _make_cyl(0.025, 0.025, 2.3), Vector3(0, 1.15, 0), "metal_dark")
	_add_part(prop, _make_cyl(0.05, 0.95, 0.35, 12), Vector3(0, 2.2, 0), "canvas_red")
	for sx in [-0.85, 0.85]:
		var seat := BoxMesh.new()
		seat.size = Vector3(0.42, 0.05, 0.42)
		_add_part(prop, seat, Vector3(sx, 0.45, 0), "plastic_white")
		var leg := BoxMesh.new()
		leg.size = Vector3(0.06, 0.45, 0.06)
		_add_part(prop, leg, Vector3(sx, 0.225, 0), "metal_dark")
		var back := BoxMesh.new()
		back.size = Vector3(0.42, 0.5, 0.05)
		_add_part(prop, back, Vector3(sx + signf(sx) * 0.19, 0.72, 0), "plastic_white")
	_add_prop_collider(prop, Vector3(2.2, 1.0, 0.9), Vector3(0, 0.5, 0))


## 垃圾桶：桶身 + 盖
func _prop_trash_bin(prop: Node3D) -> void:
	_add_part(prop, _make_cyl(0.30, 0.27, 0.85, 12), Vector3(0, 0.425, 0), "rust_metal")
	_add_part(prop, _make_cyl(0.33, 0.33, 0.07, 12), Vector3(0, 0.89, 0), "metal_dark")
	_add_prop_collider(prop, Vector3(0.65, 0.95, 0.65), Vector3(0, 0.48, 0))


## —— 巷弄周界围挡（2026-09-27 机主裁决：巷子不得直通地图外虚空）——
## 数据全部由 ALLEYS/BUILDINGS/街道带推导：每条巷弄/院落的开敞边放铁栅栏（挡人、可透视），
## 外推 wall_depth 处放红砖长墙（断视线）；墙体自动剪去建筑/街道/其他巷弄，不穿插
## _barriers 元素: {"kind": "fence"/"wall", "axis": 0=沿Z|1=沿X, "pos", "from", "to"}
var _barriers := []


func _pt_in_rect(p: Vector2, r: Array) -> bool:
	return p.x > r[0] and p.x < r[2] and p.y > r[1] and p.y < r[3]


## 覆盖带（玩家可站立/通行的连续铺装区）：主街带 + 南延走廊 + 横街带 + 全部巷弄
func _coverage_rects() -> Array:
	var s: Dictionary = Layout.STREET
	var c: Dictionary = Layout.CROSS
	var rects: Array = [
		[-s["kerb"], s["z_min"], s["kerb"], s["z_max"]],
		[-s["kerb"], s["z_max"], s["kerb"], Layout.SOUTH_EXT["z_max"]],
		[c["x_min"], c["z_min"], c["x_max"], c["walk_south_z"]],
	]
	for a in Layout.ALLEYS:
		rects.append(a["rect"])
	return rects


## 沿 axis 方向、垂直坐标 line 处的区间列表 ivs，剪去与各 rect（外扩 expand）相交的部分
func _subtract_rects_along(ivs: Array, axis: int, line: float, rects: Array, expand: float) -> Array:
	var out: Array = ivs.duplicate()
	for r in rects:
		var p0: float; var p1: float; var a0: float; var a1: float
		if axis == 0:  # 围挡沿 Z 走，垂直坐标是 X
			p0 = r[0]; p1 = r[2]; a0 = r[1]; a1 = r[3]
		else:
			p0 = r[1]; p1 = r[3]; a0 = r[0]; a1 = r[2]
		if line <= p0 - expand or line >= p1 + expand:
			continue
		var next: Array = []
		for iv in out:
			if iv[1] <= a0 - expand or iv[0] >= a1 + expand:
				next.append(iv)
			else:
				if iv[0] < a0 - expand:
					next.append([iv[0], a0 - expand])
				if iv[1] > a1 + expand:
					next.append([a1 + expand, iv[1]])
		out = next
	return out


## 巷弄开敞边扫描：0.5m 采样每条边外 0.3m 的点，不被覆盖带/建筑（外扩 1.2m 楼边地块）
## 覆盖的连续段 = 开敞段 → 铁栅栏贴边、红砖墙外推 wall_depth
func _compute_barriers() -> void:
	_barriers.clear()
	var cover := _coverage_rects()
	var blds: Array = []
	for b in Layout.BUILDINGS:
		blds.append([b["x"] - b["w"] * 0.5, b["z"] - b["d"] * 0.5,
			b["x"] + b["w"] * 0.5, b["z"] + b["d"] * 0.5])
	var style: Dictionary = Layout.BARRIER_STYLE
	var depth: float = style["wall_depth"]
	for ai in Layout.ALLEYS.size():
		var r: Array = Layout.ALLEYS[ai]["rect"]
		# [axis(0=边沿Z走/1=边沿X走), 边线坐标, 起点, 终点, 外法向符号]
		var edges := [
			[0, r[0], r[1], r[3], -1.0], [0, r[2], r[1], r[3], 1.0],
			[1, r[1], r[0], r[2], -1.0], [1, r[3], r[0], r[2], 1.0],
		]
		for e in edges:
			var segs: Array = []
			var t: float = e[2]
			var run_open := false  # 坐标可为负，不能用负数当哨兵（2026-09-27 丢边 bug 教训）
			var run_start := 0.0
			while t < e[3] - 0.01:
				var mid := t + 0.25
				var outside := Vector2(e[1] + e[4] * 0.3, mid) if e[0] == 0 else Vector2(mid, e[1] + e[4] * 0.3)
				var open := true
				for cr in cover:
					if _pt_in_rect(outside, cr):
						open = false
						break
				if open:
					for br in blds:
						if _pt_in_rect(outside, [br[0] - 1.2, br[1] - 1.2, br[2] + 1.2, br[3] + 1.2]):
							open = false
							break
				if open:
					if not run_open:
						run_open = true
						run_start = t
				elif run_open:
					segs.append([run_start, t])
					run_open = false
				t += 0.5
			if run_open:
				segs.append([run_start, e[3]])
			for seg in segs:
				var f0: float = seg[0] - 0.4
				var f1: float = seg[1] + 0.4
				if f1 - f0 < 1.0:
					continue
				_barriers.append({"kind": "fence", "axis": e[0], "pos": e[1], "from": f0, "to": f1})
				var wpos: float = e[1] + e[4] * depth
				var wext: float = style["wall_extend"]
				var ivs: Array = [[f0 - wext, f1 + wext]]
				ivs = _subtract_rects_along(ivs, e[0], wpos, blds, 0.2)
				ivs = _subtract_rects_along(ivs, e[0], wpos, cover, 0.2)
				for w in ivs:
					if w[1] - w[0] >= 1.5:
						_barriers.append({"kind": "wall", "axis": e[0], "pos": wpos, "from": w[0], "to": w[1]})


## 围挡装配：铁栅栏（立柱+镂空竖条板+顶轨，带碰撞）与红砖长墙（薄墙+压顶，带碰撞）
func _build_barriers() -> void:
	if _barriers.is_empty():
		return
	var row := Node3D.new()
	row.name = "Barriers"
	add_child(row)
	var style: Dictionary = Layout.BARRIER_STYLE
	for b in _barriers:
		var length: float = b["to"] - b["from"]
		var mid: float = (b["from"] + b["to"]) * 0.5
		if b["kind"] == "fence":
			_build_fence(row, b, length, mid, style)
		else:
			# 红砖长墙（薄墙体 + 混凝土压顶；axis=0 沿 Z，axis=1 沿 X）
			var wt: float = style["wall_t"]
			var wh: float = style["wall_h"]
			var center := Vector3(b["pos"], wh * 0.5, mid) if b["axis"] == 0 else Vector3(mid, wh * 0.5, b["pos"])
			var size := Vector3(wt, wh, length) if b["axis"] == 0 else Vector3(length, wh, wt)
			_add_box(row, "Wall_%d_%d" % [int(b["pos"] * 10), int(mid * 10)], center, size, "brick")
			var cap_center := center + Vector3(0, wh * 0.5 + 0.06, 0)
			var cap_size := Vector3(wt + 0.12, 0.12, length + 0.12) if b["axis"] == 0 \
				else Vector3(length + 0.12, 0.12, wt + 0.12)
			_add_box(row, "WallCap_%d_%d" % [int(b["pos"] * 10), int(mid * 10)], cap_center, cap_size, "kerb")


## 铁栅栏：端/中立柱 + 竖条镂空板（mat_fence_bars shader，真透视）+ 顶轨；薄盒碰撞挡玩家
func _build_fence(parent: Node3D, b: Dictionary, length: float, mid: float, style: Dictionary) -> void:
	var fh: float = style["fence_h"]
	var holder := Node3D.new()
	holder.name = "Fence_%d_%d" % [int(b["pos"] * 10), int(mid * 10)]
	holder.position = Vector3(b["pos"], 0.0, mid) if b["axis"] == 0 else Vector3(mid, 0.0, b["pos"])
	if b["axis"] == 1:
		holder.rotation_degrees.y = 90.0
	parent.add_child(holder)
	# 竖条镂空板（局部沿 Z，居中）
	var bars_mat := ShaderMaterial.new()
	bars_mat.shader = load("res://assets/shaders/mat_fence_bars.gdshader")
	bars_mat.set_shader_parameter("fence_length", length)
	var panel := BoxMesh.new()
	panel.size = Vector3(0.03, fh - 0.25, length)
	panel.material = bars_mat
	var panel_mi := MeshInstance3D.new()
	panel_mi.mesh = panel
	panel_mi.position = Vector3(0, (fh - 0.25) * 0.5 + 0.12, 0)
	holder.add_child(panel_mi)
	# 立柱（间距 ≤1.8m）
	var n_posts: int = maxi(2, int(ceil(length / 1.8)) + 1)
	for i in n_posts:
		var pz: float = -length * 0.5 + length * float(i) / float(n_posts - 1)
		_add_part(holder, _make_cyl(0.045, 0.045, fh + 0.1, 8), Vector3(0, (fh + 0.1) * 0.5, pz), "fence_metal")
	# 顶轨
	var rail := BoxMesh.new()
	rail.size = Vector3(0.05, 0.07, length)
	_add_part(holder, rail, Vector3(0, fh + 0.035, 0), "fence_metal")
	# 碰撞薄盒
	_add_prop_collider(holder, Vector3(0.12, fh + 0.1, length), Vector3(0, (fh + 0.1) * 0.5, 0))


## —— 背景楼群填充（2026-09-27 机主裁决：填满临街排楼背后的两侧空白虚空）——
## 声明式分区（Layout.BACKFILL_ZONES）+ 定种子随机落块；夜景剪影用，无立面套件省性能，
## 巷弄院落与 T 字横街自动避让（排除区外扩 0.8m 边距）

func _rects_overlap(ax0: float, az0: float, ax1: float, az1: float, r: Array) -> bool:
	return ax0 < r[2] and ax1 > r[0] and az0 < r[3] and az1 > r[1]


func _build_backdrop() -> void:
	var row := Node3D.new()
	row.name = "Backdrop"
	add_child(row)

	# 排除区：全部巷弄/院落 + T 字横街（含人行道与栅栏门位）+ 南延走廊
	# + 全部建筑 footprint + 围挡砖墙（2026-09-27 大排查：楼块不得穿插任何既定几何）
	var exclusions: Array = []
	for alley in Layout.ALLEYS:
		exclusions.append(alley["rect"])
	var c: Dictionary = Layout.CROSS
	exclusions.append([c["x_min"] - 1.2, c["z_min"] - 1.0, c["x_max"] + 1.2, c["walk_south_z"] + 0.8])
	exclusions.append([-7.2, 29.0, 7.2, Layout.SOUTH_EXT["z_max"] + 1.0])  # 南延走廊
	for b in Layout.BUILDINGS:
		exclusions.append([b["x"] - b["w"] * 0.5 - 0.8, b["z"] - b["d"] * 0.5 - 0.8,
			b["x"] + b["w"] * 0.5 + 0.8, b["z"] + b["d"] * 0.5 + 0.8])
	for gate in Layout.BARRIERS:  # 栅栏门/力场发射柱 footprint
		exclusions.append([gate["x"] - gate["w"] * 0.5 - 0.5, gate["z"] - gate["d"] * 0.5 - 0.5,
			gate["x"] + gate["w"] * 0.5 + 0.5, gate["z"] + gate["d"] * 0.5 + 0.5])
	for wb in _barriers:
		if wb["kind"] != "wall":
			continue
		if wb["axis"] == 0:
			exclusions.append([wb["pos"] - 0.6, wb["from"] - 0.3, wb["pos"] + 0.6, wb["to"] + 0.3])
		else:
			exclusions.append([wb["from"] - 0.3, wb["pos"] - 0.6, wb["to"] + 0.3, wb["pos"] + 0.6])

	var palettes := ["plaster_cream", "plaster_sand", "plaster_white", "plaster_pink", "brick"]
	var rng := RandomNumberGenerator.new()
	for zi in Layout.BACKFILL_ZONES.size():
		var zone: Dictionary = Layout.BACKFILL_ZONES[zi]
		# 分区地面石板覆盖（消地面虚空；顶面 0.03 低于巷弄地面 0.07 不共面）
		var gr: Array = zone.get("ground_rect", zone["rect"])
		_add_box(row, "ZoneGround_%d" % zi,
			Vector3((gr[0] + gr[2]) * 0.5, -0.02, (gr[1] + gr[3]) * 0.5),
			Vector3(absf(gr[2] - gr[0]), 0.1, absf(gr[3] - gr[1])), "paving")
		rng.seed = GameConfig.STREET_DRESS_SEED + 31000 + zi * 104729
		var r: Array = zone["rect"]
		var block: Array = zone["block"]
		var floors_range: Array = zone["floors"]
		var gap: float = zone.get("gap", 2.5)
		var density: float = zone.get("density", 1.0)
		var j: float = GameConfig.STREET_TINT_JITTER

		var x: float = r[0]
		while x < r[2]:
			var w: float = rng.randf_range(block[0], block[1])
			var z: float = r[1]
			while z < r[3]:
				var d: float = rng.randf_range(block[0], block[1])
				var cx: float = x + w * 0.5
				var cz: float = z + d * 0.5
				var place: bool = rng.randf() <= density \
					and cx + w * 0.5 <= float(r[2]) + 0.01 and cz + d * 0.5 <= float(r[3]) + 0.01
				if place:
					for ex in exclusions:
						if _rects_overlap(cx - w * 0.5 - 0.8, cz - d * 0.5 - 0.8,
								cx + w * 0.5 + 0.8, cz + d * 0.5 + 0.8, ex):
							place = false
							break
				if place:
					var h: float = float(rng.randi_range(int(floors_range[0]), int(floors_range[1]))) \
						* Layout.STREET["floor_h"]
					var tint := Color(1.0 - j + rng.randf() * j * 2.0,
						1.0 - j + rng.randf() * j * 2.0, 1.0 - j + rng.randf() * j * 2.0)
					_add_box(row, "Backfill_%d_%d_%d" % [zi, int(x), int(z)],
						Vector3(cx, h * 0.5, cz), Vector3(w, h, d),
						palettes[rng.randi_range(0, palettes.size() - 1)], tint)
				z += d + gap
			x += w + gap
