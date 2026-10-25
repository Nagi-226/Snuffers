## AlleyNextBuilder — 巷后院（下一场景占位，HL 式穿门加载的第一张续图；
## 2026-10-25 机主立项，正式版由 W4 换真实街区）。
## 程序化：混凝土地坪 + 三面砖围合 + 返回门（SceneLink → street_playable
## 巷口门内侧锚点）+ 夜空环境。玩家从主街穿铁栅栏门到达本院 +Z 端。
extends Node3D

const SCENE_GATE := preload("res://scripts/levels/scene_link.gd")

## 场景参数（同脚本双用：alley_next=钥匙院 / district_b=下一街区 stub）。
@export var key_spawn := true                       ## 钥匙院摆钥匙拾取
@export var return_scene := "res://scenes/levels/street_playable.tscn"
@export var return_target_anchor := "street_alley_gate"
@export var self_anchor := "alley_return"


func _ready() -> void:
	_world_env()
	_box("Ground", Vector3(0, -0.1, 0), Vector3(18, 0.2, 18), Color(0.32, 0.32, 0.33))
	_box("Wall_N", Vector3(0, 1.5, -8.5), Vector3(18, 3.0, 0.25), Color(0.42, 0.3, 0.24))
	_box("Wall_W", Vector3(-8.5, 1.5, 0), Vector3(0.25, 3.0, 18), Color(0.42, 0.3, 0.24))
	_box("Wall_E", Vector3(8.5, 1.5, 0), Vector3(0.25, 3.0, 18), Color(0.42, 0.3, 0.24))
	_box("Crates", Vector3(-5.5, 0.5, -5.5), Vector3(1.6, 1.0, 1.6), Color(0.35, 0.3, 0.2))
	_box("Pillar", Vector3(5.0, 1.6, -5.0), Vector3(0.6, 3.2, 0.6), Color(0.4, 0.4, 0.42))
	# 返回门（南端）：双柱 + 发光顶条 + SceneLink 触发 → 主街巷口
	_box("ReturnPost_W", Vector3(-1.1, 1.05, 8.2), Vector3(0.14, 2.1, 0.14), Color(0.1, 0.1, 0.11))
	_box("ReturnPost_E", Vector3(1.1, 1.05, 8.2), Vector3(0.14, 2.1, 0.14), Color(0.1, 0.1, 0.11))
	var glow := _box("ReturnGlow", Vector3(0, 2.16, 8.2), Vector3(2.3, 0.05, 0.05), Color(0.05, 0.12, 0.25))
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
	link.position = Vector3(0, 0, 8.0)
	link.rotation_degrees.y = 180.0
	add_child(link)
	link.set("target_scene", return_scene)
	link.set("target_anchor", return_target_anchor)
	link.set("anchor_id", self_anchor)
	link.set("spawn_offset", Vector3(0, 0.2, -1.5))
	var area := Area3D.new()
	area.name = "TriggerArea"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.4, 1.2)
	shape.shape = box
	area.add_child(shape)
	link.add_child(area)
	# 院内照明（夜战可读性）
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.4, 0)
	lamp.light_color = Color(0.7, 0.8, 1.0)
	lamp.light_energy = 1.2
	lamp.omni_range = 12.0
	add_child(lamp)
	if key_spawn:
		_spawn_gate_key()


## 坚固门钥匙（2026-10-25 机主任务链：本院找到钥匙 → 回主街开 E1/E2 巷子
## 尽头的重型铁门进下一街区）。发光小钥匙浮于木箱上，触碰拾取。
func _spawn_gate_key() -> void:
	var crate := _box("KeyCrate", Vector3(-5.5, 0.5, 5.0), Vector3(1.0, 1.0, 1.0), Color(0.3, 0.24, 0.16))
	var pickup := Area3D.new()
	pickup.name = "GateKeyPickup"
	pickup.position = Vector3(-5.5, 1.35, 5.0)
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
		Events.message_posted.emit("取得坚固铁栅栏门的钥匙——回主街 E1/E2 巷子尽头开门")
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
