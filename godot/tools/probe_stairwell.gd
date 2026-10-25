## 楼梯间几何探针：倒出可进入楼的踏步/坡道/平台/楼板/立柱/扶手节点位置，
## 解析①2F→3F 穿模护栏 ②狭窄处卡人的空气墙（碰撞盒清单）。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 20:
		await process_frame
	var rows: Array = []
	for n in level.find_children("*", "Node3D", true, false):
		var nm: String = n.name
		if nm.contains("POST__") or nm.contains("_HR") or nm.contains("_S1") or nm.contains("_S2") \
				or nm.contains("_RAMP") or nm.contains("_LANDING") or nm.contains("_SLAB"):
			var p: Vector3 = (n as Node3D).global_position
			rows.append("%s  pos=(%.2f,%.2f,%.2f)" % [nm, p.x, p.y, p.z])
	rows.sort()
	for r in rows:
		print("STAIR ", r)
	quit()
