## 2026-10-25 六项整改对图取证：单次启动多机位截屏（12 视图一次跑完）。
## 用途：把机主图4（墙里敌人槽口视图）/图5（双卷帘门+雨棚临街楼）匹配到坐标。
extends SceneTree

const OUT_DIR := "C:/Users/FJL03/AppData/Local/Temp/snuff_shots/"

const VIEWS := [
	["E4_fac", Vector3(2, 1.7, -36), Vector3(11.5, 2.2, -36)],
	["E5_fac", Vector3(2, 1.7, -49), Vector3(11.5, 2.2, -49)],
	["E6_fac", Vector3(2, 1.7, -66), Vector3(11.5, 2.2, -66)],
	["E7_fac", Vector3(2, 1.7, -79), Vector3(11.5, 2.2, -79)],
	["W3_fac", Vector3(-2, 1.7, -2), Vector3(-11.5, 2.2, -2)],
	["W5_fac", Vector3(-2, 1.7, -38.5), Vector3(-11.5, 2.2, -38.5)],
	["W6_fac", Vector3(-2, 1.7, -51), Vector3(-11.5, 2.2, -51)],
	["W7_fac", Vector3(-2, 1.7, -69), Vector3(-11.5, 2.2, -69)],
	["slot_E4E5", Vector3(4, 1.6, -43), Vector3(16, 1.6, -43)],
	["slot_E6E7", Vector3(4, 1.6, -72.5), Vector3(16, 1.6, -72.5)],
	["slot_E7E8", Vector3(4, 1.6, -85.5), Vector3(16, 1.6, -85.5)],
	["slot_E2E3", Vector3(4, 1.6, -11), Vector3(16, 1.6, -11)],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_test.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	var cam: Camera3D = level.get_node("OverviewCamera") as Camera3D
	for v in VIEWS:
		cam.position = v[1]
		cam.look_at(v[2])
		for i in 3:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var err := img.save_png(OUT_DIR + String(v[0]) + ".png")
		print("SHOT ", v[0], " err=", err)
	quit()
