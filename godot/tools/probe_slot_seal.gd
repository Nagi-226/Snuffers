## 2026-10-25 窄槽封堵物理终验：敌人胶囊（r0.35/h1.7）扫过全部楼缝槽口线，
## 任何一格未被静态体挡住 = 寄生体可钻入楼后死区 = FAIL。
## 附：门B加强筋修复复拍。
extends SceneTree

const OUT := "C:/Users/FJL03/AppData/Local/Temp/snuff_shots/"

## 槽口清单：[name, line_x, z_from, z_to]（axis=0 沿 Z 的封堵线）
const SLOTS := [
	["slot_E6E7_1m", 6.5, -73.6, -71.4],
	["slot_E7E8_1m", 6.5, -86.6, -84.4],
	["slot_W5W6_1m", -6.5, -45.6, -43.4],
	["slot_E2E3_2m", 6.5, -12.2, -9.8],
	["slot_E4E5_2m", 6.5, -44.2, -41.8],
	["slot_W7W8_2m", -6.5, -77.2, -74.8],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	var ps := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	ps.shape = cap
	ps.collision_mask = 0xFFFF
	var all_ok := true
	for slot in SLOTS:
		var unblocked: int = 0
		var checked: int = 0
		var z: float = slot[2]
		while z < slot[3]:
			ps.transform = Transform3D(Basis(), Vector3(slot[1], 0.9, z))
			var hits: Array = level.get_world_3d().direct_space_state.intersect_shape(ps, 16)
			var has_static := false
			for hit in hits:
				var col := hit["collider"] as Node
				if col is StaticBody3D:
					has_static = true
					break
			checked += 1
			if not has_static:
				unblocked += 1
				print("SEAL_LEAK ", slot[0], " z=", snappedf(z, 0.1))
			z += 0.1
		var ok: bool = unblocked == 0
		if not ok:
			all_ok = false
		print("SEAL ", slot[0], " checked=", checked, " unblocked=", unblocked, " => ", "SEALED" if ok else "LEAK")
	print("SEAL_ALL ", "PASS" if all_ok else "FAIL")
	# 门B复拍（加强筋可见性）
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.make_current()
	cam.position = Vector3(18, 1.7, 5)
	cam.look_at(Vector3(22.2, 1.6, 5))
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + "gateB_braces_v2.png")
	print("SEAL_SHOT gateB_braces_v2 saved")
	quit()
