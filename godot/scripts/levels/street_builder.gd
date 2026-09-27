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
}

var _materials := {}

## P1 程序化 shader 调色板映射: key → [shader路径, world_scale, seed]
## 尺度分档纪律（文档10 §1-P1）：建筑面 2.5m 周期，金属件 1.2m 更密
const SHADER_MAP := {
	"asphalt": ["res://assets/shaders/mat_asphalt.gdshader", 2.5, 47.0],
	"kerb": ["res://assets/shaders/mat_concrete.gdshader", 2.5, 11.0],
	"rust_metal": ["res://assets/shaders/mat_rust_metal.gdshader", 1.2, 23.0],
}


func _ready() -> void:
	_build_ground()
	_build_buildings()
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
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = PALETTE.get(key, Color(0.5, 0.5, 0.5))
			mat.roughness = 0.9
			_materials[key] = mat
	return _materials[key]


## 在 parent 下生成一个带碰撞的盒体块。center 为盒中心，size 为全尺寸。
func _add_box(parent: Node3D, name: String, center: Vector3, size: Vector3, palette_key: String) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = center

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _get_material(palette_key)
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

	# 外围大地面（街区之外的延展地皮，避免看到天空地线）
	_add_box(ground, "OuterGround", Vector3(0, -0.08, z_mid),
		Vector3(120.0, 0.1, z_len + 80.0), "dirt")
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


func _build_buildings() -> void:
	var s: Dictionary = Layout.STREET
	var row := Node3D.new()
	row.name = "Buildings"
	add_child(row)

	for b in Layout.BUILDINGS:
		var h: float = b["floors"] * s["floor_h"]
		_add_box(row, "Bldg_%s" % b["id"],
			Vector3(b["x"], h * 0.5, b["z"]),
			Vector3(b["w"], h, b["d"]), b["palette"])
