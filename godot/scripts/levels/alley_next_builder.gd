## AlleyNextBuilder — 巷后院（下一场景占位，HL 式穿门加载的第一张续图；
## 2026-10-25 机主立项，正式版由 W4 换真实街区）。
## 程序化：混凝土地坪 + 三面砖围合 + 返回门（SceneLink → street_playable
## 巷口门内侧锚点）+ 夜空环境。玩家从主街穿铁栅栏门到达本院 +Z 端。
extends Node3D

const SCENE_GATE := preload("res://scripts/levels/scene_link.gd")


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
	link.set("target_scene", "res://scenes/levels/street_playable.tscn")
	link.set("target_anchor", "street_alley_gate")
	link.set("anchor_id", "alley_return")
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
