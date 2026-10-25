## PBR 材质生成器（开发取证/资产管线）：从 assets/textures/pbr/<id>/ 三图
## （color/normal/rough）生成三平面世界空间 StandardMaterial3D .tres——
## 程序化几何无 UV 依赖，与 P1 程序 shader 的 world_scale 同思路。
extends SceneTree

const SETS: Array = [
	["plaster004", 2.5],        # 立面抹灰 A（尺度分档纪律：建筑面 2.5m 周期）
	["plaster006", 2.5],        # 立面抹灰 B
	["paintedplaster002", 2.0], # 内饰漆面抹灰
	["bricks003", 1.0],         # 砖墙（1K 图 ≈ 1m 砖量）
	["woodfloor002", 2.0],      # 室内木地板备用
	["concrete034", 1.5],       # 混凝土
]


func _init() -> void:
	for s: Array in SETS:
		var id: String = s[0]
		var sc: float = s[1]
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/pbr/%s/%s_color.jpg" % [id, id])
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/pbr/%s/%s_normal.jpg" % [id, id])
		m.roughness_texture = load("res://assets/textures/pbr/%s/%s_rough.jpg" % [id, id])
		m.roughness = 1.0
		m.uv1_triplanar_enabled = true
		m.uv1_scale = Vector3(sc, sc, sc)
		var err := ResourceSaver.save(m, "res://assets/textures/pbr/%s/%s.tres" % [id, id])
		print("MAT_GEN ", id, " err=", err)
	quit()
