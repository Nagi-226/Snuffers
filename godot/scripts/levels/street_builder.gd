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
		# 可选摆位: --shot <输出路径> <camx> <camy> <camz> <lookx> <looky> <lookz>
		if idx + 7 < args.size():
			cam.position = Vector3(args[idx + 2].to_float(), args[idx + 3].to_float(), args[idx + 4].to_float())
			cam.look_at(Vector3(args[idx + 5].to_float(), args[idx + 6].to_float(), args[idx + 7].to_float()))
			await get_tree().process_frame
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
## rot_z_deg / rot_x_deg ≠ 0 时绕对应轴旋转（楼梯坡道等斜面用）
func _add_box(parent: Node3D, name: String, center: Vector3, size: Vector3, palette_key: String,
		tint := Color(1, 1, 1), rot_z_deg := 0.0, rot_x_deg := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = center
	if rot_z_deg != 0.0:
		body.rotation_degrees.z = rot_z_deg
	if rot_x_deg != 0.0:
		body.rotation_degrees.x = rot_x_deg

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
	# 横街北侧人行道（x=±6.5 以外段，衔接两翼铺装；四向力场裁决配套）
	var nw_d: float = c["z_min"] - c["walk_north_z"]
	var nw_half: float = (c["x_max"] - s["kerb"]) * 0.5
	var nw_x: float = s["kerb"] + nw_half
	_add_box(ground, "CrossSidewalk_NW", Vector3(-nw_x, s["walk_h"] * 0.5, c["z_min"] - nw_d * 0.5),
		Vector3(nw_half * 2.0, s["walk_h"], nw_d), "kerb")
	_add_box(ground, "CrossSidewalk_NE", Vector3(nw_x, s["walk_h"] * 0.5, c["z_min"] - nw_d * 0.5),
		Vector3(nw_half * 2.0, s["walk_h"], nw_d), "kerb")
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
		if b.get("enterable", false):
			# 可进入建筑试点：实心盒改为壳体（外墙+楼板+楼梯+隔断），内部可探索
			_build_enterable_shell(row, b, s["floor_h"], tint)
			_dress_facade(row, b, s["floor_h"], rng, false, Vector3.ZERO, true)
		else:
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
		# 次立面：非主立面凡 5m 邻接带触及可玩覆盖带（街/巷/院落）→ 补门窗
		# （2026-09-27 全图排查：可到之处可见的侧面不许是光板墙）
		if absf(b["x"]) > 0.1:
			_dress_secondary_faces(row, b, s["floor_h"], rng)
	_build_wires(rng)


# —— 可进入建筑试点（2026-09-27 机主立项：E1 壳体化，一楼门厅+东房 / 楼梯 / 二楼南房）——
const SHELL_WALL_T: float = 0.3   ## 外壳墙厚（与立面套件内退 0.3 对齐，套件不内凸）
const SHELL_DOOR_W: float = 1.4   ## 临街门洞宽
const SHELL_DOOR_H: float = 2.3   ## 临街门洞高
const SHELL_PART_T: float = 0.12  ## 室内隔断厚
# 真阳台构造（尺寸对齐 build_facade_kit.py §4 阳台单元，机主 2026-09-30 裁决内外打通）
const SHELL_BALCONY_DOOR_W: float = 0.9   ## 阳台门洞宽（= 套件 BD_W）
const SHELL_BALCONY_DOOR_H: float = 2.1   ## 阳台门洞高（= 套件 BD_H）
const SHELL_BALCONY_DEPTH: float = 0.9    ## 阳台外挑深度
const SHELL_BALCONY_SLAB_W: float = 2.2   ## 阳台板/栏杆宽
const SHELL_BALCONY_SLAB_T: float = 0.14  ## 阳台板厚（顶面高出楼板，门槛坡道衔接）
const SHELL_BALCONY_RAIL_H: float = 1.05  ## 栏杆扶手高


## 可进入楼的地面层障碍 rect 集（密封洪水填充用）：外墙段（让开门洞）+ 一层隔断 + 楼梯 footprint
func _enterable_obstacles(b: Dictionary) -> Array:
	var x0: float = b["x"] - b["w"] * 0.5
	var x1: float = b["x"] + b["w"] * 0.5
	var z0: float = b["z"] - b["d"] * 0.5
	var z1: float = b["z"] + b["d"] * 0.5
	var dz0: float = b["z"] - SHELL_DOOR_W * 0.5
	var dz1: float = b["z"] + SHELL_DOOR_W * 0.5
	# 临街墙：东排楼（x>0）在西侧 x0，西排楼在东侧 x1
	var sw0: float = x0 if b["x"] > 0.0 else x1 - SHELL_WALL_T
	var sw1: float = x0 + SHELL_WALL_T if b["x"] > 0.0 else x1
	var bw0: float = x1 - SHELL_WALL_T if b["x"] > 0.0 else x0
	var bw1: float = x1 if b["x"] > 0.0 else x0 + SHELL_WALL_T
	# 一层隔断 x=px：门洞 z ∈ b.z+1.0..b.z+2.2
	var px: float = b["x"] - 0.5 if b["x"] > 0.0 else b["x"] + 0.5
	# 楼梯 footprint（L 型 v2：一段+平台贴西墙 z0+0.3..z0+4.1，二段沿北墙向东）
	var l1r: Array = [x0 + 0.3, z0 + SHELL_WALL_T, x0 + 1.5, z0 + 4.1]
	var l2r: Array = [x0 + 1.45, z0 + SHELL_WALL_T, x0 + 4.3, z0 + SHELL_WALL_T + 1.2]
	if b["x"] < 0.0:
		l1r = [2.0 * b["x"] - l1r[2], l1r[1], 2.0 * b["x"] - l1r[0], l1r[3]]
		l2r = [2.0 * b["x"] - l2r[2], l2r[1], 2.0 * b["x"] - l2r[0], l2r[3]]
	return [
		[sw0, z0, sw1, dz0], [sw0, dz1, sw1, z1],          # 临街墙两段（门洞留空）
		[bw0, z0, bw1, z1],                                # 背街墙
		[x0, z0, x1, z0 + SHELL_WALL_T],                   # 北墙
		[x0, z1 - SHELL_WALL_T, x1, z1],                   # 南墙
		[px - SHELL_PART_T * 0.5, z0 + SHELL_WALL_T, px + SHELL_PART_T * 0.5, b["z"] + 1.0],
		[px - SHELL_PART_T * 0.5, b["z"] + 2.2, px + SHELL_PART_T * 0.5, z1 - SHELL_WALL_T],
		l1r, l2r,
	]


## 可进入楼壳体：外墙（临街面留真门洞）+ 室内地坪 + 中层楼板（楼梯开口）+ 坡道楼梯
## + 一层/二层隔断 + 顶板 + 门框 + 闪烁应急灯（照明 B 方案：机主 2026-09-27 裁决）
func _build_enterable_shell(row: Node3D, b: Dictionary, floor_h: float, tint: Color) -> void:
	var x0: float = b["x"] - b["w"] * 0.5
	var x1: float = b["x"] + b["w"] * 0.5
	var z0: float = b["z"] - b["d"] * 0.5
	var z1: float = b["z"] + b["d"] * 0.5
	var h_total: float = b["floors"] * floor_h
	var dz0: float = b["z"] - SHELL_DOOR_W * 0.5
	var dz1: float = b["z"] + SHELL_DOOR_W * 0.5
	# 二楼阳台门洞中线（与 _dress_facade 中间开间对齐：f==1 && i==n/2，仅排楼主立面沿 Z 情形）
	var n_bays: int = maxi(1, int(floor(b["d"] / KIT_BAY)))
	var bz_c: float = b["z"] - n_bays * KIT_BAY * 0.5 + (n_bays / 2 + 0.5) * KIT_BAY
	var pal: String = b["palette"]
	var east_side: bool = b["x"] > 0.0  # 东排楼门开在西墙
	var sw_x: float = (x0 + SHELL_WALL_T * 0.5) if east_side else (x1 - SHELL_WALL_T * 0.5)
	var bw_x: float = (x1 - SHELL_WALL_T * 0.5) if east_side else (x0 + SHELL_WALL_T * 0.5)
	var in_x0: float = x0 + SHELL_WALL_T
	var in_x1: float = x1 - SHELL_WALL_T
	var in_z0: float = z0 + SHELL_WALL_T
	var in_z1: float = z1 - SHELL_WALL_T

	# 临街墙（洞口减法）：一层临街门洞；层数 ≥2 时二层开真阳台门洞（通往外挑阳台）
	var sw_openings: Array = [[dz0, dz1, 0.0, SHELL_DOOR_H]]
	if b["floors"] >= 2:
		sw_openings.append([bz_c - SHELL_BALCONY_DOOR_W * 0.5, bz_c + SHELL_BALCONY_DOOR_W * 0.5,
			floor_h, floor_h + SHELL_BALCONY_DOOR_H])
	_build_wall_with_openings(row, "Bldg_%s_SW" % b["id"], sw_x, z0, z1, h_total, sw_openings, pal, tint)
	# 背街墙 / 北墙 / 南墙
	_add_box(row, "Bldg_%s_BW" % b["id"], Vector3(bw_x, h_total * 0.5, b["z"]),
		Vector3(SHELL_WALL_T, h_total, b["d"]), pal, tint)
	_add_box(row, "Bldg_%s_NW" % b["id"], Vector3(b["x"], h_total * 0.5, z0 + SHELL_WALL_T * 0.5),
		Vector3(b["w"], h_total, SHELL_WALL_T), pal, tint)
	_add_box(row, "Bldg_%s_FW" % b["id"], Vector3(b["x"], h_total * 0.5, z1 - SHELL_WALL_T * 0.5),
		Vector3(b["w"], h_total, SHELL_WALL_T), pal, tint)
	# 门框（门洞两侧门垛 + 门楣，深灰金属）
	var jamb_x: float = (x0 + 0.18) if east_side else (x1 - 0.18)
	_add_box(row, "Bldg_%s_JAMB_A" % b["id"], Vector3(jamb_x, SHELL_DOOR_H * 0.5, dz0 - 0.06),
		Vector3(0.36, SHELL_DOOR_H, 0.12), "metal_dark")
	_add_box(row, "Bldg_%s_JAMB_B" % b["id"], Vector3(jamb_x, SHELL_DOOR_H * 0.5, dz1 + 0.06),
		Vector3(0.36, SHELL_DOOR_H, 0.12), "metal_dark")
	_add_box(row, "Bldg_%s_LINTEL" % b["id"], Vector3(jamb_x, SHELL_DOOR_H + 0.06, b["z"]),
		Vector3(0.36, 0.12, SHELL_DOOR_W + 0.24), "metal_dark")
	# 二楼真阳台（内外打通：门洞已在临街墙开好，此处建外挑板+门槛坡道+门框+栏杆）
	if b["floors"] >= 2:
		_build_balcony(row, b, floor_h, tint, bz_c)
	# 室内地坪（与人行道顶面 0.145 齐平，过门无台阶）
	_add_box(row, "Bldg_%s_FLOOR" % b["id"], Vector3(b["x"], 0.105, b["z"]),
		Vector3(b["w"], 0.08, b["d"]), "kerb", Color(0.55, 0.55, 0.55))
	# 顶板
	_add_box(row, "Bldg_%s_ROOF" % b["id"], Vector3(b["x"], h_total + 0.12, b["z"]),
		Vector3(b["w"], 0.24, b["d"]), pal, tint)

	# 中层楼板（顶面与 floor_h 齐平；楼梯开口 = L 型梯段正上方）
	# L 型 90° 转角楼梯 v2（2026-09-27 机主草图裁决）：一段贴【西墙】（门北侧）向北爬 1.4m
	# → 西北角转角平台 → 二段向东转 90° 沿北墙爬 1.455m 接上二楼板；栏杆式扶手，顶部无挡板
	var sgn: float = 1.0 if east_side else -1.0
	var mx := func(v: float) -> float: return b["x"] + (v - b["x"]) * sgn
	# 以下 x 均为东排基准坐标（西排楼经 mx 镜像）；z 不变（爬升方向朝北 -Z）
	var stx0: float = in_x0 + 0.05          # 梯段一西缘（贴西墙）
	var stx1: float = stx0 + 1.1            # 梯段一东缘
	var f1z0: float = b["z"] - 0.95         # 梯段一底（门洞北缘外 0.25m，不挡门）
	var f1z1: float = f1z0 - 3.0            # 梯段一顶
	var lz0: float = in_z0 + 0.05           # 平台南缘（贴北墙）
	var f2x1: float = stx1 + 2.8            # 梯段二东端
	var y_mid: float = 0.145 + 1.4
	# 楼板开口：A = 梯段一+平台上方；B = 梯段二上方
	var oax1: float = stx1 + 0.1
	var oaz1: float = f1z1 + 1.85
	var obx1: float = stx1 + 2.95
	var obz1: float = lz0 + 1.15
	_add_box(row, "Bldg_%s_SLAB_A" % b["id"],
		Vector3(b["x"], floor_h - 0.12, (oaz1 + in_z1) * 0.5),
		Vector3(in_x1 - in_x0, 0.24, in_z1 - oaz1), pal, tint)
	_add_box(row, "Bldg_%s_SLAB_B" % b["id"],
		Vector3((mx.call(oax1) + mx.call(in_x1)) * 0.5, floor_h - 0.12, (obz1 + oaz1) * 0.5),
		Vector3(absf(mx.call(in_x1) - mx.call(oax1)), 0.24, oaz1 - obz1), pal, tint)
	_add_box(row, "Bldg_%s_SLAB_C" % b["id"],
		Vector3((mx.call(obx1) + mx.call(in_x1)) * 0.5, floor_h - 0.12, (in_z0 + obz1) * 0.5),
		Vector3(absf(mx.call(in_x1) - mx.call(obx1)), 0.24, obz1 - in_z0), pal, tint)

	# 梯段一坡道（碰撞斜面，贴西墙向北爬升，绕 X 轴；北端 -Z 抬升 → rot_x 正号）
	var f1_len: float = sqrt(3.0 * 3.0 + 1.4 * 1.4)
	var f1_ang: float = rad_to_deg(atan2(1.4, 3.0))
	var f1_c := Vector3(mx.call((stx0 + stx1) * 0.5), (0.145 + y_mid) * 0.5 - 0.05, (f1z0 + f1z1) * 0.5)
	_add_box(row, "Bldg_%s_RAMP1" % b["id"], f1_c, Vector3(1.1, 0.1, f1_len),
		"kerb", Color(0.5, 0.5, 0.5), 0.0, f1_ang)
	# 转角平台（西北角）
	_add_box(row, "Bldg_%s_LANDING" % b["id"],
		Vector3(mx.call((stx0 + stx1) * 0.5), y_mid - 0.27, (lz0 + f1z1) * 0.5),
		Vector3(1.1, 0.54, f1z1 - lz0), "kerb", Color(0.55, 0.55, 0.55))
	# 梯段二坡道（沿北墙向东爬升，绕 Z 轴）
	var f2_len: float = sqrt(2.8 * 2.8 + 1.455 * 1.455)
	var f2_ang: float = rad_to_deg(atan2(1.455, 2.8)) * sgn
	var f2_c := Vector3(mx.call((stx1 + f2x1) * 0.5), (y_mid + floor_h) * 0.5 - 0.05, lz0 + 0.55)
	_add_box(row, "Bldg_%s_RAMP2" % b["id"], f2_c, Vector3(f2_len, 0.1, 1.1),
		"kerb", Color(0.5, 0.5, 0.5), f2_ang)
	# 踏步视觉（两段各 6 级）
	for i in 6:
		var sz1: float = f1z0 - (float(i) + 0.5) * 0.5
		var sy1: float = 0.145 + (float(i) + 1.0) * (1.4 / 6.0)
		_add_box(row, "Bldg_%s_S1_%d" % [b["id"], i], Vector3(mx.call((stx0 + stx1) * 0.5), sy1 - 0.09, sz1),
			Vector3(1.1, 0.18, 0.52), "kerb", Color(0.62, 0.62, 0.62))
		var sx2: float = stx1 + (float(i) + 0.5) * (2.8 / 6.0)
		var sy2: float = y_mid + (float(i) + 1.0) * (1.455 / 6.0)
		_add_box(row, "Bldg_%s_S2_%d" % [b["id"], i], Vector3(mx.call(sx2), sy2 - 0.09, lz0 + 0.55),
			Vector3(0.49, 0.18, 1.1), "kerb", Color(0.62, 0.62, 0.62))
	# 栏杆式扶手（立柱 + 细扶手杆，通透不挡视线）：
	# 梯段一东缘（临空侧）/ 二楼板 B 西缘与板 A 北缘（临楼梯井侧）
	var rail := func(x_e: float, y_surf: float, z: float) -> void:
		_add_box(row, "Bldg_%s_POST" % b["id"], Vector3(mx.call(x_e), y_surf + 0.45, z),
			Vector3(0.05, 0.9, 0.05), "metal_dark")
	for i in 4:
		var pz1: float = f1z1 + 0.3 + float(i) * 0.65
		rail.call(stx1 + 0.03, 0.145 + 1.4 * (f1z0 - pz1) / 3.0, pz1)
	_add_box(row, "Bldg_%s_HR1" % b["id"], Vector3(mx.call(stx1 + 0.03), f1_c.y + 0.95, f1_c.z),
		Vector3(0.05, 0.05, f1_len), "metal_dark", Color(1, 1, 1), 0.0, f1_ang)
	for i in 3:
		rail.call(oax1, floor_h, obz1 + 0.25 + float(i) * 0.45)
	_add_box(row, "Bldg_%s_HR2" % b["id"], Vector3(mx.call(oax1), floor_h + 0.95, (obz1 + oaz1) * 0.5),
		Vector3(0.05, 0.05, oaz1 - obz1), "metal_dark")
	for i in 3:
		rail.call(in_x0 + 0.25 + float(i) * 0.4, floor_h, oaz1 + 0.02)
	_add_box(row, "Bldg_%s_HR3" % b["id"], Vector3(mx.call((in_x0 + oax1) * 0.5), floor_h + 0.95, oaz1 + 0.02),
		Vector3(oax1 - in_x0, 0.05, 0.05), "metal_dark")

	# 一层隔断（x=px，门洞 z ∈ b.z+1.0..b.z+2.2）：门厅 | 东房
	var px: float = b["x"] - 0.5 if east_side else b["x"] + 0.5
	_add_box(row, "Bldg_%s_PART_F1A" % b["id"], Vector3(px, 1.57, (in_z0 + b["z"] + 1.0) * 0.5),
		Vector3(SHELL_PART_T, floor_h - 0.145, b["z"] + 1.0 - in_z0), "plaster_white", tint)
	_add_box(row, "Bldg_%s_PART_F1B" % b["id"], Vector3(px, 1.57, (b["z"] + 2.2 + in_z1) * 0.5),
		Vector3(SHELL_PART_T, floor_h - 0.145, in_z1 - b["z"] - 2.2), "plaster_white", tint)
	# 二层隔断（z=b.z+0.5，门洞 x 居中 1.2m）：楼梯间 | 南房
	var pz: float = b["z"] + 0.5
	var g0: float = b["x"] - 0.6
	var g1: float = b["x"] + 0.6
	_add_box(row, "Bldg_%s_PART_F2A" % b["id"], Vector3((in_x0 + g0) * 0.5, (floor_h + h_total) * 0.5, pz),
		Vector3(g0 - in_x0, h_total - floor_h, SHELL_PART_T), "plaster_white", tint)
	_add_box(row, "Bldg_%s_PART_F2B" % b["id"], Vector3((g1 + in_x1) * 0.5, (floor_h + h_total) * 0.5, pz),
		Vector3(in_x1 - g1, h_total - floor_h, SHELL_PART_T), "plaster_white", tint)

	# 闪烁应急灯 ×2（照明 B 方案）：一层门厅顶 + 二楼楼梯口顶（引导上楼）
	var script: Script = load("res://scripts/levels/emergency_light.gd")
	var hall_x: float = (in_x0 + px) * 0.5 if east_side else (px + in_x1) * 0.5
	var l1 := OmniLight3D.new()
	l1.name = "Bldg_%s_EmLightF1" % b["id"]
	l1.position = Vector3(hall_x, floor_h - 0.35, b["z"])
	l1.set_script(script)
	row.add_child(l1)
	var l2 := OmniLight3D.new()
	l2.name = "Bldg_%s_EmLightF2" % b["id"]
	l2.position = Vector3(mx.call(obx1 + 1.6), h_total - 0.45, lz0 + 0.55)  # 二楼楼梯到达口上方
	l2.set_script(script)
	row.add_child(l2)

	_furnish_enterable(row, b)


## 临街墙洞口减法（沿 Z 墙体，法线 ±X）：z 向按洞边切条，每条 y 向填洞间实体段。
## 洞口元素 [z_lo, z_hi, y_lo, y_hi]；一层临街门洞与二层阳台门洞共用此构造。
func _build_wall_with_openings(parent: Node3D, base_name: String, cx: float,
		z_lo: float, z_hi: float, h: float, openings: Array, pal: String, tint: Color) -> void:
	var cuts: Array = [z_lo, z_hi]
	for op in openings:
		cuts.append(clampf(op[0], z_lo, z_hi))
		cuts.append(clampf(op[1], z_lo, z_hi))
	cuts.sort()
	var zs: Array = []
	for c in cuts:
		if zs.is_empty() or c > zs[-1] + 0.001:
			zs.append(c)
	var idx := 0
	for s in zs.size() - 1:
		var a: float = zs[s]
		var c2: float = zs[s + 1]
		if c2 - a < 0.01:
			continue
		var holes: Array = []
		for op in openings:
			if op[0] < c2 - 0.001 and op[1] > a + 0.001:
				holes.append([op[2], op[3]])
		holes.sort()
		var y := 0.0
		for hole in holes:
			if hole[0] > y + 0.001:
				_add_box(parent, "%s_%d" % [base_name, idx],
					Vector3(cx, (y + hole[0]) * 0.5, (a + c2) * 0.5),
					Vector3(SHELL_WALL_T, hole[0] - y, c2 - a), pal, tint)
				idx += 1
			y = maxf(y, hole[1])
		if y < h - 0.001:
			_add_box(parent, "%s_%d" % [base_name, idx],
				Vector3(cx, (y + h) * 0.5, (a + c2) * 0.5),
				Vector3(SHELL_WALL_T, h - y, c2 - a), pal, tint)
			idx += 1


## 真阳台构造（可进入楼专用，替代装饰套件 kit_balcony——套件玻璃门嵌在墙里内外不通）：
## 外挑板（自带碰撞，顶面高出楼板 0.14）+ 门槛坡道（楼板 → 板面高差衔接，胶囊底跨不上 14cm 直台阶）
## + 门框 + 铁栏杆（可见件）+ 隐形防坠栏板（杆间缝隙只挡视线不挡人，需整面薄碰撞）
func _build_balcony(row: Node3D, b: Dictionary, floor_h: float, tint: Color, bz_c: float) -> void:
	var east_side: bool = b["x"] > 0.0
	var o: float = -1.0 if east_side else 1.0  # 外挑方向（东排楼朝 -X，西排楼朝 +X）
	var face_x: float = (b["x"] - b["w"] * 0.5) if east_side else (b["x"] + b["w"] * 0.5)
	var y0: float = floor_h  # 二楼楼板顶面
	var bz0: float = bz_c - SHELL_BALCONY_DOOR_W * 0.5
	var bz1: float = bz_c + SHELL_BALCONY_DOOR_W * 0.5

	# 外挑板：0.25 嵌入墙体咬合，外挑 0.9
	_add_box(row, "Bldg_%s_BAL_SLAB" % b["id"],
		Vector3(face_x + o * 0.325, y0 + SHELL_BALCONY_SLAB_T * 0.5, bz_c),
		Vector3(SHELL_BALCONY_DEPTH + 0.25, SHELL_BALCONY_SLAB_T, SHELL_BALCONY_SLAB_W),
		"plaster_white", tint)
	# 门槛坡道（金属压条）：从室内楼板 3.0 爬到板面 3.14，跨墙厚 + 内外各一小段
	var ramp_run: float = SHELL_WALL_T + 0.25
	var ramp_ang: float = rad_to_deg(atan2(SHELL_BALCONY_SLAB_T, ramp_run))
	_add_box(row, "Bldg_%s_BAL_RAMP" % b["id"],
		Vector3(face_x - o * 0.125, y0 + SHELL_BALCONY_SLAB_T * 0.5 - 0.03, bz_c),
		Vector3(sqrt(ramp_run * ramp_run + SHELL_BALCONY_SLAB_T * SHELL_BALCONY_SLAB_T) + 0.02,
			0.06, SHELL_BALCONY_DOOR_W), "metal_dark", Color(1, 1, 1), o * ramp_ang)
	# 门框（与一层门同语言：深灰金属门垛 + 门楣）
	var bj_x: float = face_x - o * 0.18
	_add_box(row, "Bldg_%s_BAL_JAMB_A" % b["id"], Vector3(bj_x, y0 + SHELL_BALCONY_DOOR_H * 0.5, bz0 - 0.06),
		Vector3(0.36, SHELL_BALCONY_DOOR_H, 0.12), "metal_dark")
	_add_box(row, "Bldg_%s_BAL_JAMB_B" % b["id"], Vector3(bj_x, y0 + SHELL_BALCONY_DOOR_H * 0.5, bz1 + 0.06),
		Vector3(0.36, SHELL_BALCONY_DOOR_H, 0.12), "metal_dark")
	_add_box(row, "Bldg_%s_BAL_LINTEL" % b["id"], Vector3(bj_x, y0 + SHELL_BALCONY_DOOR_H + 0.06, bz_c),
		Vector3(0.36, 0.12, SHELL_BALCONY_DOOR_W + 0.24), "metal_dark")
	# 铁栏杆（与套件同位：前缘扶手 + 9 竖杆 + 两侧扶手）
	var rail_x: float = face_x + o * 0.755
	_add_box(row, "Bldg_%s_BAL_RAIL_TOP" % b["id"], Vector3(rail_x, y0 + SHELL_BALCONY_RAIL_H, bz_c),
		Vector3(0.05, 0.05, SHELL_BALCONY_SLAB_W), "metal_dark")
	for i in 9:
		var pz: float = bz_c - 1.05 + float(i) * (2.1 / 8.0)
		_add_box(row, "Bldg_%s_BAL_POST_%d" % [b["id"], i], Vector3(rail_x, y0 + 0.55, pz),
			Vector3(0.03, 0.95, 0.03), "metal_dark")
	for side in [-1.0, 1.0]:
		_add_box(row, "Bldg_%s_BAL_RAIL_S" % b["id"],
			Vector3(face_x + o * 0.325, y0 + SHELL_BALCONY_RAIL_H, bz_c + side * 1.08),
			Vector3(SHELL_BALCONY_DEPTH, 0.05, 0.05), "metal_dark")
	# 隐形防坠栏板：杆间 0.23m 缝隙与扶手下方挡不住胶囊（半径 0.4），整面薄碰撞防坠落
	_add_collider(row, "Bldg_%s_BAL_GUARD_F" % b["id"],
		Vector3(rail_x, y0 + 0.6, bz_c), Vector3(0.06, 1.2, SHELL_BALCONY_SLAB_W))
	for side in [-1.0, 1.0]:
		_add_collider(row, "Bldg_%s_BAL_GUARD_S" % b["id"],
			Vector3(face_x + o * 0.425, y0 + 0.6, bz_c + side * 1.07),
			Vector3(0.85, 1.2, 0.06))


## 隐形碰撞盒（无网格）：只挡人不挡视线的场合（阳台防坠栏板等）
func _add_collider(parent: Node3D, name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


# —— 室内家具陈设（2026-09-30 机主立项：E1 内饰试点，Blender 烘焙 fur_* 套件）——
## type → [glb 目标高, 碰撞盒 size, 碰撞盒中心]（碰撞盒为模型本地朝向，随 prop 旋转）
const FUR_SPEC := {
	"table": [0.75, Vector3(1.2, 0.75, 0.75), Vector3(0, 0.375, 0)],
	"chair": [0.90, Vector3(0.45, 0.9, 0.45), Vector3(0, 0.45, 0)],
	"bed": [0.85, Vector3(0.95, 0.6, 2.05), Vector3(0, 0.3, 0)],
	"wardrobe": [2.0, Vector3(1.25, 2.0, 0.6), Vector3(0, 1.0, 0)],
	"sofa": [0.85, Vector3(1.6, 0.85, 0.8), Vector3(0, 0.425, 0)],
	"tv_stand": [1.04, Vector3(1.2, 1.05, 0.45), Vector3(0, 0.52, 0)],
	"shelf": [1.8, Vector3(0.8, 1.8, 0.32), Vector3(0, 0.9, 0)],
	"nightstand": [0.48, Vector3(0.45, 0.5, 0.42), Vector3(0, 0.25, 0)],
}


## 按 Layout.FURNITURE 数据表给可进入楼摆家具（复用 _prop_model：AABB 归一缩放+落地+碰撞盒）
func _furnish_enterable(row: Node3D, b: Dictionary) -> void:
	var idx := 0
	for f in Layout.FURNITURE:
		if f["bldg"] != b["id"]:
			continue
		var spec: Array = FUR_SPEC[f["type"]]
		var prop := Node3D.new()
		prop.name = "Fur_%s_%s_%d" % [b["id"], f["type"], idx]
		prop.position = Vector3(f["x"], f["y"], f["z"])
		prop.rotation_degrees.y = f.get("rot_y", 0.0)
		row.add_child(prop)
		if not _prop_model(prop, "res://assets/models/fur_%s.glb" % f["type"],
				spec[0], spec[1], spec[2]):
			push_warning("street_builder: missing furniture model fur_%s.glb" % f["type"])
		idx += 1


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


## 次立面扫描：排楼的非主立面，外推 5m 条带与任一可玩覆盖带（街/巷/院落）相交 →
## 该面临可达区，补门窗。主立面方向（显式 face 或临街向）跳过，避免重复装配
func _dress_secondary_faces(parent: Node3D, b: Dictionary, floor_h: float, rng: RandomNumberGenerator) -> void:
	var primary: Vector3
	var facing: String = b.get("face", "")
	if facing == "n":
		primary = Vector3(0, 0, -1)
	elif facing == "s":
		primary = Vector3(0, 0, 1)
	elif b["x"] < 0.0:
		primary = Vector3(1, 0, 0)
	else:
		primary = Vector3(-1, 0, 0)
	var cover := _coverage_rects()
	var candidates := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for o in candidates:
		if o == primary:
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
		for cr in cover:
			if _rects_overlap(rect[0], rect[1], rect[2], rect[3], cr):
				_dress_facade(parent, b, floor_h, rng, true, o)
				break


## 临街立面逐开间装配（panel space：件原点在地板线、前墙面，墙身向内侧延伸）
## 一层：中间开间恒为卷帘门商铺，其余开间按 SHOPFRONT_RATIO 改商铺/留窗（城中村底商）；
## 二层中间开间为阳台，上层窗户按 AC_UNIT_RATIO 挂空调外机；开间边线稀疏落排水管
func _dress_facade(parent: Node3D, b: Dictionary, floor_h: float, rng: RandomNumberGenerator,
		alley_mode := false, override_outward := Vector3.ZERO, enterable := false) -> void:
	var outward: Vector3
	var wall_len: float
	var facing: String = b.get("face", "")
	if override_outward != Vector3.ZERO:  # 巷弄立面：显式指定朝向
		outward = override_outward
		wall_len = b["d"] if outward.x != 0.0 else b["w"]
	elif facing == "n":  # 横街南排/东西走廊南排：面朝北（-Z），临街轴为 X
		outward = Vector3(0, 0, -1)
		wall_len = b["w"]
	elif facing == "s":  # 东西走廊北排：面朝南（+Z）
		outward = Vector3(0, 0, 1)
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
			if enterable and f == 0 and i == n / 2:
				continue  # 可进入楼：一层中间开间留真门洞（壳体已开洞+门框，不挂商铺套件）
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
				if enterable:
					continue  # 可进入楼二楼中间开间：壳体自建真阳台（门洞打通），不挂玻璃门装饰套件
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


## —— 周界密封（2026-09-27 全图大排查重写）——
## 不再只扫巷弄开敞边：对「可玩覆盖带」做洪水填充密封——障碍（建筑/力场/已生成围挡）
## 按玩家半径膨胀栅格化，从街心 BFS；凡可达格跨越覆盖带边界进入非覆盖区 = 漏封缺口，
## 在边界线上自动生成铁栅栏 + 外推 wall_depth 红砖墙，迭代至全密封。
## 楼间缝隙/巷楼 1m 窄缝等旧扫描漏掉的缺口全部自动捕获。
## _barriers 元素: {"kind": "fence"/"wall", "axis": 0=沿Z|1=沿X, "pos", "from", "to"}
var _barriers := []

const SEAL_CELL := 0.25
const SEAL_X0 := -48.0
const SEAL_Z0 := -100.0
const SEAL_GW := 384   # x -48..48
const SEAL_GH := 824   # z -100..106
const SEAL_PR := 0.35  # 玩家半径膨胀


func _seal_idx(px: float, pz: float) -> int:
	var ix := int(floor((px - SEAL_X0) / SEAL_CELL))
	var iz := int(floor((pz - SEAL_Z0) / SEAL_CELL))
	if ix < 0 or ix >= SEAL_GW or iz < 0 or iz >= SEAL_GH:
		return -1
	return iz * SEAL_GW + ix


## 把障碍 rect（含玩家半径膨胀）栅格化进 blocked
func _seal_raster(blocked: PackedByteArray, rects: Array) -> void:
	for r in rects:
		var ix0 := int(floor((r[0] - SEAL_PR - SEAL_X0) / SEAL_CELL))
		var ix1 := int(floor((r[2] + SEAL_PR - SEAL_X0) / SEAL_CELL))
		var iz0 := int(floor((r[1] - SEAL_PR - SEAL_Z0) / SEAL_CELL))
		var iz1 := int(floor((r[3] + SEAL_PR - SEAL_Z0) / SEAL_CELL))
		for iz in range(maxi(iz0, 0), mini(iz1, SEAL_GH - 1) + 1):
			for ix in range(maxi(ix0, 0), mini(ix1, SEAL_GW - 1) + 1):
				blocked[iz * SEAL_GW + ix] = 1


func _compute_barriers() -> void:
	_barriers.clear()
	var cover := _coverage_rects()
	var style: Dictionary = Layout.BARRIER_STYLE
	var depth: float = style["wall_depth"]

	# 障碍 rect 集：建筑 + 力场/发射柱（h>0.3 的才挡人；警示轨 0.18m 不算）
	# 可进入楼：footprint 替换为壳体墙段/隔断/楼梯障碍，室内可走（门洞留通道）
	var obstacles: Array = []
	for b in Layout.BUILDINGS:
		if b.get("enterable", false):
			obstacles.append_array(_enterable_obstacles(b))
		else:
			obstacles.append([b["x"] - b["w"] * 0.5, b["z"] - b["d"] * 0.5,
				b["x"] + b["w"] * 0.5, b["z"] + b["d"] * 0.5])
	for g in Layout.BARRIERS:
		if g["h"] > 0.3:
			obstacles.append([g["x"] - g["w"] * 0.5, g["z"] - g["d"] * 0.5,
				g["x"] + g["w"] * 0.5, g["z"] + g["d"] * 0.5])

	# 覆盖带栅格（O(1) 查询）
	var cov := PackedByteArray()
	cov.resize(SEAL_GW * SEAL_GH)
	for r in cover:
		var ix0 := int(floor((r[0] - SEAL_X0) / SEAL_CELL))
		var ix1 := int(floor((r[2] - 0.001 - SEAL_X0) / SEAL_CELL))
		var iz0 := int(floor((r[1] - SEAL_Z0) / SEAL_CELL))
		var iz1 := int(floor((r[3] - 0.001 - SEAL_Z0) / SEAL_CELL))
		for iz in range(maxi(iz0, 0), mini(iz1, SEAL_GH - 1) + 1):
			for ix in range(maxi(ix0, 0), mini(ix1, SEAL_GW - 1) + 1):
				cov[iz * SEAL_GW + ix] = 1

	# 迭代密封：每轮 BFS 找越界通道 → 生成栅栏+墙 → 栅栏入障碍集 → 复验
	for iter in 8:
		var blocked := PackedByteArray()
		blocked.resize(SEAL_GW * SEAL_GH)
		_seal_raster(blocked, obstacles)
		# BFS 从街心
		var reach := PackedByteArray()
		reach.resize(SEAL_GW * SEAL_GH)
		var start := _seal_idx(0.0, 20.0)
		var stack: Array = [start]
		reach[start] = 1
		while not stack.is_empty():
			var idx: int = stack.pop_back()
			var ix: int = idx % SEAL_GW
			var iz: int = idx / SEAL_GW
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = ix + d[0]
				var nz: int = iz + d[1]
				if nx < 0 or nx >= SEAL_GW or nz < 0 or nz >= SEAL_GH:
					continue
				var ni: int = nz * SEAL_GW + nx
				if blocked[ni] == 0 and reach[ni] == 0:
					reach[ni] = 1
					stack.append(ni)
		# 找越界通道：覆盖带内可达格 ↔ 带外可达非障碍格 的相邻边
		# key = [axis, line_quant, out_sign] → value = 沿线坐标列表
		var crossings := {}
		for iz in SEAL_GH:
			for ix in SEAL_GW:
				var idx: int = iz * SEAL_GW + ix
				if reach[idx] == 0 or cov[idx] == 0:
					continue
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = ix + d[0]
					var nz: int = iz + d[1]
					if nx < 0 or nx >= SEAL_GW or nz < 0 or nz >= SEAL_GH:
						continue
					var ni: int = nz * SEAL_GW + nx
					if reach[ni] == 0 or cov[ni] == 1 or blocked[ni] == 1:
						continue
					# 边线：d 为跨越方向；栅栏轴垂直于 d
					var line: float
					var along: float
					var axis: int
					if d[0] != 0:
						axis = 0  # 栅栏沿 Z
						line = SEAL_X0 + (float(maxi(ix, nx))) * SEAL_CELL
						along = SEAL_Z0 + (float(iz) + 0.5) * SEAL_CELL
					else:
						axis = 1  # 栅栏沿 X
						line = SEAL_Z0 + (float(maxi(iz, nz))) * SEAL_CELL
						along = SEAL_X0 + (float(ix) + 0.5) * SEAL_CELL
					var key := "%d_%.2f_%d" % [axis, line, d[0] + d[1]]
					if not crossings.has(key):
						crossings[key] = {"axis": axis, "line": line,
							"sign": float(d[0] + d[1]), "pts": []}
					crossings[key]["pts"].append(along)
		if crossings.is_empty():
			break
		# 每组连续点合并成栅栏段
		for key in crossings:
			var grp: Dictionary = crossings[key]
			var pts: Array = grp["pts"]
			pts.sort()
			var seg_start: float = pts[0]
			var prev: float = pts[0]
			var segs: Array = []
			for i in range(1, pts.size()):
				if pts[i] - prev > SEAL_CELL * 1.5:
					segs.append([seg_start, prev])
					seg_start = pts[i]
				prev = pts[i]
			segs.append([seg_start, prev])
			for sg in segs:
				# 端点外放 0.45m 咬进两侧障碍，杜绝拐角微缝
				var f0: float = sg[0] - SEAL_CELL * 0.5 - 0.45
				var f1: float = sg[1] + SEAL_CELL * 0.5 + 0.45
				_barriers.append({"kind": "fence", "axis": grp["axis"],
					"pos": grp["line"], "from": f0, "to": f1})
				# 栅栏碰撞入障碍集（薄板 0.12 厚），下轮 BFS 复验密封
				if grp["axis"] == 0:
					obstacles.append([grp["line"] - 0.06, f0, grp["line"] + 0.06, f1])
				else:
					obstacles.append([f0, grp["line"] - 0.06, f1, grp["line"] + 0.06])
				# 外推红砖墙：剪去建筑/覆盖带，端点外放 wall_extend
				var wpos: float = grp["line"] + grp["sign"] * depth
				var wext: float = style["wall_extend"]
				var ivs: Array = [[f0 - wext, f1 + wext]]
				ivs = _subtract_rects_along(ivs, grp["axis"], wpos, obstacles, 0.2)
				ivs = _subtract_rects_along(ivs, grp["axis"], wpos, cover, 0.2)
				for w in ivs:
					if w[1] - w[0] >= 1.5:
						_barriers.append({"kind": "wall", "axis": grp["axis"],
							"pos": wpos, "from": w[0], "to": w[1]})

	# —— 栅栏背挡补丁（2026-09-27 全图排查）：逐栅栏做 2D 射线视线扫描——
	# 栏外 8m 内若无实体遮挡且视线也没进入另一片可玩区 = 视线泄漏（窄缝通道/栏墙间隙），
	# 在栏外 1.2m 处补红砖背挡墙收口。铁栅栏透视，不算遮挡。
	var solids: Array = []
	for b in Layout.BUILDINGS:
		solids.append([b["x"] - b["w"] * 0.5, b["z"] - b["d"] * 0.5,
			b["x"] + b["w"] * 0.5, b["z"] + b["d"] * 0.5])
	for g in Layout.BARRIERS:
		if g["h"] > 0.3:
			solids.append([g["x"] - g["w"] * 0.5, g["z"] - g["d"] * 0.5,
				g["x"] + g["w"] * 0.5, g["z"] + g["d"] * 0.5])
	for wb in _barriers:
		if wb["kind"] != "wall":
			continue
		if wb["axis"] == 0:
			solids.append([wb["pos"] - 0.15, wb["from"], wb["pos"] + 0.15, wb["to"]])
		else:
			solids.append([wb["from"], wb["pos"] - 0.15, wb["to"], wb["pos"] + 0.15])
	for fb in _barriers:
		if fb["kind"] != "fence":
			continue
		# 判定外法向：栏线两侧 0.6m 各取中点，落在覆盖带内的一侧为内
		var fmid: float = (fb["from"] + fb["to"]) * 0.5
		var probe_in: Vector2
		if fb["axis"] == 0:
			probe_in = Vector2(fb["pos"] - 0.6, fmid)
		else:
			probe_in = Vector2(fmid, fb["pos"] - 0.6)
		var minus_in := false
		for cr in cover:
			if _pt_in_rect(probe_in, cr):
				minus_in = true
				break
		var out_sign := 1.0 if minus_in else -1.0
		var out_dir := Vector2(out_sign, 0.0) if fb["axis"] == 0 else Vector2(0.0, out_sign)
		# 沿栏 0.5m 采样，净空连续段合并
		var t: float = fb["from"] + 0.25
		var run_open := false
		var run_start := 0.0
		var clear_spans: Array = []
		while t < fb["to"]:
			var origin := Vector2(fb["pos"] + out_sign * 0.2, t) if fb["axis"] == 0 \
				else Vector2(t, fb["pos"] + out_sign * 0.2)
			var solid_d := INF
			for sr in solids:
				var d := _ray_rect_dist(origin, out_dir, 8.0, sr)
				if d >= 0.0 and d < solid_d:
					solid_d = d
			var cover_d := INF
			for cr in cover:
				var d := _ray_rect_dist(origin, out_dir, 8.0, cr)
				if d >= 0.0 and d < cover_d:
					cover_d = d
			var clear: bool = solid_d == INF and cover_d == INF
			if clear:
				if not run_open:
					run_open = true
					run_start = t
			elif run_open:
				clear_spans.append([run_start, t])
				run_open = false
			t += 0.5
		if run_open:
			clear_spans.append([run_start, fb["to"]])
		for span in clear_spans:
			if span[1] - span[0] < 0.5:
				continue
			# 背挡墙：栏外 1.2m，跨度两端加 1.0m 咬边，剪去建筑/覆盖带
			# （窄通道内可用长度可能不足 1m，min 放宽到 0.4——门垛式短墙收口）
			var bpos: float = fb["pos"] + out_sign * 1.2
			var bivs: Array = [[span[0] - 1.0, span[1] + 1.0]]
			bivs = _subtract_rects_along(bivs, fb["axis"], bpos, solids, 0.2)
			bivs = _subtract_rects_along(bivs, fb["axis"], bpos, cover, 0.05)
			for bw in bivs:
				if bw[1] - bw[0] >= 0.4:
					_barriers.append({"kind": "wall", "axis": fb["axis"],
						"pos": bpos, "from": bw[0], "to": bw[1]})
					if fb["axis"] == 0:
						solids.append([bpos - 0.15, bw[0], bpos + 0.15, bw[1]])
					else:
						solids.append([bw[0], bpos - 0.15, bw[1], bpos + 0.15])


## 2D 射线 vs rect（slab 法）：命中返回距离（0..max_d），未命中返回 -1
func _ray_rect_dist(o: Vector2, d: Vector2, max_d: float, r: Array) -> float:
	var tmin := 0.0
	var tmax := max_d
	for axis in 2:
		var p: float = o.x if axis == 0 else o.y
		var dv: float = d.x if axis == 0 else d.y
		var r0: float = r[0] if axis == 0 else r[1]
		var r1: float = r[2] if axis == 0 else r[3]
		if absf(dv) < 0.0001:
			if p < r0 or p > r1:
				return -1.0
		else:
			var t1 := (r0 - p) / dv
			var t2 := (r1 - p) / dv
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


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


func _pt_in_rect(p: Vector2, r: Array) -> bool:
	return p.x > r[0] and p.x < r[2] and p.y > r[1] and p.y < r[3]


## 覆盖带（玩家可站立/通行的连续铺装区）：主街带 + 南延走廊 + 横街带（含北侧人行道）+ 全部巷弄
func _coverage_rects() -> Array:
	var s: Dictionary = Layout.STREET
	var c: Dictionary = Layout.CROSS
	var rects: Array = [
		[-s["kerb"], s["z_min"], s["kerb"], s["z_max"]],
		[-s["kerb"], s["z_max"], s["kerb"], Layout.SOUTH_EXT["z_max"]],
		[c["x_min"], c["z_min"], c["x_max"], c["walk_south_z"]],
		[c["x_min"], c["walk_north_z"], c["x_max"], c["z_min"]],  # 横街北侧人行道
	]
	for a in Layout.ALLEYS:
		rects.append(a["rect"])
	# 可进入楼室内（玩家可站立区，密封洪水填充不在门洞处设栏）
	for b in Layout.BUILDINGS:
		if b.get("enterable", false):
			rects.append([b["x"] - b["w"] * 0.5 + SHELL_WALL_T, b["z"] - b["d"] * 0.5 + SHELL_WALL_T,
				b["x"] + b["w"] * 0.5 - SHELL_WALL_T, b["z"] + b["d"] * 0.5 - SHELL_WALL_T])
	return rects


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


## 背景楼夜窗材质（2026-09-27 二次裁决：可见的外侧建筑不许是无门窗长方体——
## 复用 skyline_windows 世界坐标窗格 shader，住宅化参数：低亮灯率、无裙楼商业、无霓虹）
var _block_mat: ShaderMaterial = null

func _get_block_material() -> ShaderMaterial:
	if _block_mat == null:
		_block_mat = ShaderMaterial.new()
		_block_mat.shader = load("res://assets/shaders/skyline_windows.gdshader")
		_block_mat.set_shader_parameter("window_size", Vector2(2.4, 3.0))
		_block_mat.set_shader_parameter("lit_ratio", 0.30)
		_block_mat.set_shader_parameter("dark_floor_ratio", 0.30)
		_block_mat.set_shader_parameter("podium_height", 0.0)
		_block_mat.set_shader_parameter("emission_strength", 1.8)
		_block_mat.set_shader_parameter("wall_color", Color(0.045, 0.045, 0.055))
	return _block_mat


## 背景楼块：盒体 + 夜窗 shader（逐楼 instance 参数注入种子/楼高/亮度），带碰撞
func _add_windowed_block(parent: Node3D, name: String, center: Vector3, size: Vector3,
		rng: RandomNumberGenerator) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = center
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _get_block_material()
	mesh_inst.mesh = box
	mesh_inst.set_instance_shader_parameter("seed_offset", rng.randf() * 97.0)
	mesh_inst.set_instance_shader_parameter("tower_height", size.y)
	mesh_inst.set_instance_shader_parameter("brightness", 0.8)
	body.add_child(mesh_inst)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)


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
		# 2026-09-27 全图排查：砖墙与铁栅栏都进排除区——
		# 栅栏后（栏墙之间 6m 带）不得落楼块，否则楼贴着镂空栅栏违和且挡墙位
		if wb["axis"] == 0:
			exclusions.append([wb["pos"] - 0.6, wb["from"] - 0.3, wb["pos"] + 0.6, wb["to"] + 0.3])
		else:
			exclusions.append([wb["from"] - 0.3, wb["pos"] - 0.6, wb["to"] + 0.3, wb["pos"] + 0.6])

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
					_add_windowed_block(row, "Backfill_%d_%d_%d" % [zi, int(x), int(z)],
						Vector3(cx, h * 0.5, cz), Vector3(w, h, d), rng)
				z += d + gap
			x += w + gap
