## 2026-10-25 敌人逃逸模拟（图4墙内敌人根因取证）：
## 玩家诱饵沿主街+各巷弄巡逻 ~6 分钟，逐 10s 快照全部敌人位置，
## 判定是否越出可玩覆盖带（进入楼后死巷/填充块迷宫 = 图4「墙里打不到的敌人」）。
extends SceneTree

var _cover: Array = []
var _t0: int = 0


func _in_band(p: Vector3) -> String:
	# 覆盖带内 → "IN"；E3 车库内部豁免；带外 <0.5m → "EDGE"；更远 → "OUT"
	for r in _cover:
		if p.x > r[0] and p.x < r[2] and p.z > r[1] and p.z < r[3]:
			return "IN"
	if p.x > 7.2 and p.x < 16.3 and p.z > -22.3 and p.z < -13.7:
		return "GARAGE"
	for r in _cover:
		if p.x > r[0] - 0.5 and p.x < r[2] + 0.5 and p.z > r[1] - 0.5 and p.z < r[3] + 0.5:
			return "EDGE"
	return "OUT"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	var builder: Node = level.get_node_or_null("StreetTest")
	if builder != null and builder.has_method("_coverage_rects"):
		_cover = builder.call("_coverage_rects")
	print("ESC cover_rects=", _cover.size())
	var player: Node3D = level.find_children("Player*", "Node3D", true, false).pop_front()
	if player == null:
		print("ESC no player found")
		quit()
		return
	print("ESC player=", player.name, " spawn=", player.global_position.round())
	# 诱饵路径：主街南下 → WB 巷折返 → 主街 → EA 巷+酒馆院 → EB 巷 → flank 巷 → 主街北上，循环
	var path: Array = [
		Vector3(0, 1.0, 20), Vector3(0, 1.0, -10), Vector3(-2, 1.0, -30),
		Vector3(-5, 1.0, -58), Vector3(-14, 1.0, -59), Vector3(-5, 1.0, -58),
		Vector3(-2, 1.0, -35), Vector3(0, 1.0, -55), Vector3(8, 1.0, -26),
		Vector3(16, 1.0, -28), Vector3(22, 1.0, -30), Vector3(16, 1.0, -28),
		Vector3(8, 1.0, -26), Vector3(0, 1.0, -40), Vector3(2, 1.0, -57),
		Vector3(12, 1.0, -56), Vector3(2, 1.0, -57), Vector3(0, 1.0, -20),
		Vector3(10, 1.0, 5), Vector3(19, 1.0, 5), Vector3(10, 1.0, 5),
		Vector3(0, 1.0, 5), Vector3(0, 1.0, 25),
	]
	var seg: int = 0
	var tick: int = 0
	var escaped: Dictionary = {}
	while tick < 3800:   # ~63s × 60fps 每路点段；总模拟 ≈ 6 分钟
		var from: Vector3 = player.global_position
		var to: Vector3 = path[seg]
		var d: Vector3 = to - from
		d.y = 0.0
		if d.length() < 1.0:
			seg = (seg + 1) % path.size()
			continue
		d = d.normalized()
		player.global_position = from + d * 4.5   # 诱饵 4.5m/s 沿路点走
		player.global_position.y = 1.0
		await process_frame
		tick += 1
		if tick % 600 == 0:   # ~10s 快照
			var line: String = "ESC t=%03ds" % (tick / 60)
			for e in level.get_tree().get_nodes_in_group(&"enemy"):
				var en := e as Node3D
				if en == null:
					continue
				var st: String = _in_band(en.global_position)
				line += " | %s:%s(%.0f,%.0f)" % [en.name, st, en.global_position.x, en.global_position.z]
				if st == "OUT" and not escaped.has(en.name):
					escaped[en.name] = true
					print("ESC_EARLY >>>> ", en.name, " OUT at ", en.global_position.round(), " t=", tick / 60, "s")
			print(line)
	print("=== ESC_SUMMARY ===")
	for k in escaped:
		print("ESC_ESCAPED ", k)
	if escaped.is_empty():
		print("ESC_ESCAPED none")
	quit()
