## AlleyNextBuilder — 篮球场西端门后的钥匙院（HL 式穿门加载的第一张续图；
## 2026-10-25 机主二轮裁决：入口从 v1 错位的 E2 墙外移到球场院落西端围挡，
## 并扩充为可探索院落——不再是空院子：工具棚（钥匙在工作台上）+ 晾衣角
## + 板条箱堆 + 废料管道 + 电池/医疗补给。正式版由 W4 换真实街区。
## 程序化：混凝土地坪 + 三面砖围合 + 南端返回门（SceneLink → street_playable
## 球场门内侧锚点）+ 夜空环境。玩家从球场门穿入，落在院南端朝北探索。
extends Node3D

const SCENE_GATE := preload("res://scripts/levels/scene_link.gd")
const PICKUP_SCENE_PATH := "res://scenes/levels/pickup.tscn"

## 场景参数（同脚本双用：alley_next=钥匙院 / district_b=下一街区 stub）。
@export var key_spawn := true                       ## 钥匙院摆钥匙拾取
@export var return_scene := "res://scenes/levels/street_playable.tscn"
@export var return_target_anchor := "street_court_gate"
@export var self_anchor := "alley_return"


func _ready() -> void:
	_world_env()
	# —— 地坪 + 围合（26×20 院；北端工具棚、东侧晾衣角、西向箱堆）——
	_box("Ground", Vector3(0, -0.1, 0), Vector3(26, 0.2, 20), Color(0.32, 0.32, 0.33))
	_box("Wall_N", Vector3(0, 1.5, -10), Vector3(26, 3.0, 0.25), Color(0.42, 0.3, 0.24))
	_box("Wall_W", Vector3(-13, 1.5, 0), Vector3(0.25, 3.0, 20), Color(0.42, 0.3, 0.24))
	_box("Wall_E", Vector3(13, 1.5, 0), Vector3(0.25, 3.0, 20), Color(0.42, 0.3, 0.24))
	_box("Wall_S_W", Vector3(-7.1, 1.5, 10), Vector3(11.8, 3.0, 0.25), Color(0.42, 0.3, 0.24))
	_box("Wall_S_E", Vector3(7.1, 1.5, 10), Vector3(11.8, 3.0, 0.25), Color(0.42, 0.3, 0.24))
	# —— 工具棚（北端：背靠北墙，两面侧墙 + 平顶，南侧敞开）——
	_box("Shed_Wall_W", Vector3(-3.5, 1.4, -7.25), Vector3(0.25, 2.8, 5.5), Color(0.38, 0.36, 0.33))
	_box("Shed_Wall_E", Vector3(3.5, 1.4, -7.25), Vector3(0.25, 2.8, 5.5), Color(0.38, 0.36, 0.33))
	_box("Shed_Roof", Vector3(0, 2.75, -7.25), Vector3(7.5, 0.14, 6.0), Color(0.25, 0.24, 0.26))
	_box("Shed_Bench", Vector3(0, 0.45, -8.8), Vector3(2.4, 0.9, 0.8), Color(0.3, 0.24, 0.16))
	_mi("Shed_Shelf", Vector3(0, 1.7, -9.75), Vector3(3.0, 0.08, 0.5), Color(0.3, 0.24, 0.16))
	# —— 晾衣角（东墙边：双杆 + 横杆 + 挂布）——
	_mi_pole("Pole_N", Vector3(9.0, 1.2, -6.0))
	_mi_pole("Pole_S", Vector3(9.0, 1.2, -1.0))
	_mi("LaundryBar", Vector3(9.0, 2.3, -3.5), Vector3(0.06, 0.06, 5.0), Color(0.16, 0.16, 0.17))
	for i in 3:
		_mi("Cloth_%d" % i, Vector3(9.0, 1.86, -5.4 + i * 1.5), Vector3(0.02, 0.75, 0.62),
			Color(0.36, 0.4, 0.46) if i % 2 == 0 else Color(0.44, 0.4, 0.34))
	_box("NookCrate", Vector3(11.0, 0.45, -6.5), Vector3(0.9, 0.9, 0.9), Color(0.3, 0.24, 0.16))
	# —— 西向板条箱堆 + 废料管道（院子主区的探索道具）——
	_box("CrateStack_A", Vector3(-9.5, 0.5, -2.0), Vector3(1.4, 1.0, 1.4), Color(0.35, 0.28, 0.18))
	_box("CrateStack_B", Vector3(-9.5, 1.4, -2.0), Vector3(1.1, 0.8, 1.1), Color(0.3, 0.24, 0.16))
	_box("Crate_C", Vector3(-8.0, 0.5, -3.2), Vector3(1.2, 1.0, 1.2), Color(0.35, 0.28, 0.18))
	_box("Crate_D", Vector3(-7.0, 0.5, 0.5), Vector3(1.0, 1.0, 1.0), Color(0.32, 0.26, 0.17))
	_box("Dumpster", Vector3(5.0, 0.65, 3.5), Vector3(2.2, 1.3, 1.2), Color(0.2, 0.3, 0.22))
	_box("DumpsterLid", Vector3(5.0, 1.36, 3.5), Vector3(2.3, 0.1, 1.3), Color(0.16, 0.24, 0.18))
	_box("Pallet", Vector3(0, 0.07, 2.0), Vector3(1.2, 0.14, 1.2), Color(0.33, 0.27, 0.18))
	_box("PalletCrate", Vector3(0, 0.62, 2.0), Vector3(0.9, 0.9, 0.9), Color(0.35, 0.28, 0.18))
	_mi("Pipe_A", Vector3(-2.0, 0.15, 4.6), Vector3(4.0, 0.3, 0.3), Color(0.35, 0.33, 0.3))
	_mi("Pipe_B", Vector3(-2.0, 0.15, 5.05), Vector3(4.0, 0.24, 0.24), Color(0.4, 0.36, 0.3))
	# —— 返回门（南端，球场方向）：双柱 + 发光顶条 + SceneLink 触发 → 主街球场门 ——
	_box("ReturnPost_W", Vector3(-1.1, 1.05, 9.6), Vector3(0.14, 2.1, 0.14), Color(0.1, 0.1, 0.11))
	_box("ReturnPost_E", Vector3(1.1, 1.05, 9.6), Vector3(0.14, 2.1, 0.14), Color(0.1, 0.1, 0.11))
	var glow := _box("ReturnGlow", Vector3(0, 2.16, 9.6), Vector3(2.3, 0.05, 0.05), Color(0.05, 0.12, 0.25))
	var mat := glow.mesh.duplicate() as BoxMesh
	var gm := StandardMaterial3D.new()
	gm.emission_enabled = true
	gm.emission = Color(0.35, 0.7, 1.0)
	gm.emission_energy_multiplier = 2.2
	gm.albedo_color = Color(0.05, 0.12, 0.25)
	mat.material = gm
	glow.mesh = mat
	var link := Node3D.new()
	link.name = "Link_AlleyReturn"
	link.set_script(SCENE_GATE)
	link.position = Vector3(0, 0, 9.0)
	var area := Area3D.new()
	area.name = "TriggerArea"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.4, 1.2)
	shape.shape = box
	area.add_child(shape)
	link.add_child(area)   # 触发区先挂子节点，再入树（@onready 时序）
	add_child(link)
	link.set("target_scene", return_scene)
	link.set("target_anchor", return_target_anchor)
	link.set("anchor_id", self_anchor)
	link.set("spawn_offset", Vector3(0, 0.2, -1.5))
	# —— 补给（电池组=箱堆顶 / 医疗注射=晾衣角箱上）——
	if ResourceLoader.exists(PICKUP_SCENE_PATH):
		var pk_scene: PackedScene = load(PICKUP_SCENE_PATH)
		var bat: Node3D = pk_scene.instantiate()
		bat.name = "Pickup_battery"
		bat.position = Vector3(-9.5, 2.05, -2.0)
		bat.set(&"kind", &"battery")
		add_child(bat)
		var med: Node3D = pk_scene.instantiate()
		med.name = "Pickup_medkit"
		med.position = Vector3(11.0, 1.15, -6.5)
		med.set(&"kind", &"medkit")
		add_child(med)
	# —— 照明（入口 / 院子中心 / 棚内）——
	for l in [[Vector3(0, 3.2, 8.0), 10.0, 1.1], [Vector3(0, 3.6, 0.0), 13.0, 1.3],
			[Vector3(0, 2.4, -7.5), 4.5, 1.0]]:
		var lamp := OmniLight3D.new()
		lamp.position = l[0]
		lamp.light_color = Color(0.7, 0.8, 1.0)
		lamp.light_energy = l[2]
		lamp.omni_range = l[1]
		add_child(lamp)
	if key_spawn:
		_spawn_gate_key()


## 坚固门钥匙（2026-10-25 机主任务链：本院工具棚工作台上寻得钥匙 → 回主街
## 从 E1/E2 楼间巷子走到尽头的重型铁门进下一街区）。发光小钥匙浮于台面，触碰拾取。
func _spawn_gate_key() -> void:
	var pickup := Area3D.new()
	pickup.name = "GateKeyPickup"
	pickup.position = Vector3(0, 1.4, -8.8)
	add_child(pickup)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	pickup.add_child(shape)
	var key := Node3D.new()
	key.name = "Key"
	pickup.add_child(key)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.05
	torus.outer_radius = 0.1
	ring.mesh = torus
	ring.position = Vector3(0, 0.1, 0)
	ring.rotation_degrees.x = 90.0
	key.add_child(ring)
	var shaft := MeshInstance3D.new()
	var teeth := BoxMesh.new()
	teeth.size = Vector3(0.04, 0.22, 0.04)
	shaft.mesh = teeth
	key.add_child(shaft)
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 2.0
	mat.albedo_color = Color(0.9, 0.75, 0.3)
	ring.material_override = mat
	shaft.material_override = mat
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.3)
	glow.light_energy = 1.4
	glow.omni_range = 3.0
	pickup.add_child(glow)
	if GameState.gate_key_have:
		pickup.queue_free()
		return
	pickup.body_entered.connect(func(body: Node3D) -> void:
		if not body.is_in_group(&"player") or GameState.gate_key_have:
			return
		GameState.gate_key_have = true
		Events.message_posted.emit("取得坚固铁栅栏门的钥匙——回主街，E1/E2 楼间巷子走到尽头开门")
		pickup.queue_free())


func _world_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.12, 0.18)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.05)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _box(nm: String, center: Vector3, size: Vector3, albedo: Color) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.9
	bm.material = m
	mi.mesh = bm
	body.add_child(mi)
	return mi


## 纯视觉件（薄板/横杆/挂布等，不参与碰撞）
func _mi(nm: String, pos: Vector3, size: Vector3, albedo: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.9
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	add_child(mi)


## 晾衣杆（细圆柱，视觉件）
func _mi_pole(nm: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 2.4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.16, 0.17)
	m.roughness = 0.8
	cyl.material = m
	mi.mesh = cyl
	mi.position = pos
	add_child(mi)
