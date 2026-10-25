## 敌人跨场景持久化验证（2026-10-25 机主指令：走前剩谁回来还是谁）：
## P1 初次加载计数 → P2 杀2敌(Host_ST1/Host_GY1)+搬移Host_ST2+掉血 → P3 离场快照
## → P4 释放场景、置 arrive_anchor、重新加载（真实到达链路：link._ready 触发延迟恢复）
## → P5 断言：总数-2、死者无尸、Host_ST2 在搬移位且血量保留、快照名单全数在树
## 用法：godot --headless -s tools/probe_enemy_persist.gd --path .
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _enemy_names(lv: Node) -> Dictionary:
	var out := {}
	for e in lv.get_tree().get_nodes_in_group(&"enemy"):
		out[String((e as Node).name)] = e
	return out


func _run() -> void:
	# —— P1 初次加载 ——
	var lv: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(lv)
	for i in 30:
		await process_frame
	var names0 := _enemy_names(lv).keys()
	var n0: int = names0.size()
	print("P1_FIRST_LOAD enemies=", n0, " sample=", names0.slice(0, 4))
	# —— P2 按真实动线先施压：杀2敌 + 搬移1敌 + 掉血 ——
	var killed: int = 0
	for victim in ["Host_ST1", "Host_GY1"]:
		var e: Node = _enemy_names(lv).get(victim)
		if e != null:
			e.call("take_damage", 9999.0, false)
			killed += 1
	for i in 5:
		await process_frame  # queue_free 落树
	var st2: Node = _enemy_names(lv).get("Host_ST2")
	st2.global_position = Vector3(5.0, 0.3, -40.0)
	st2.set("health", 0.37)
	print("P2_PRESS killed=", killed, " st2_moved=", st2.global_position,
		" st2_hp=", st2.get("health"))
	# —— P3 离场快照（_on_body_entered 里的同一方法；返回值=快照数组）——
	# ⚠️ 探针严禁编译期引用 SceneLink 类/静态（-s 语境 autoload 未注册会毒化
	# 编译缓存→场景里 link 挂不上脚本），全部走 link 实例 call。
	var link: Node = null
	for n in lv.find_children("Link_BGate_E", "Node3D", true, false):
		link = n
	var snap: Array = link.call("_capture_enemies")
	print("P3_SNAPSHOT records=", snap.size(), " (期望=", n0 - killed, ")",
		" has_ST2=", snap.any(func(r): return r["name"] == "Host_ST2"),
		" has_dead_ST1=", snap.any(func(r): return r["name"] == "Host_ST1"))
	# —— P4 释放场景 → 重新加载 → 手动触发到达恢复（同 _ready 到达分支的延迟调用）——
	lv.queue_free()
	for i in 5:
		await process_frame
	var lv2: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(lv2)
	for i in 15:
		await process_frame
	var link2: Node = null
	for n in lv2.find_children("Link_BGate_E", "Node3D", true, false):
		link2 = n
	link2.call("_restore_enemies")
	for i in 10:
		await process_frame  # queue_free 落树
	# —— P5 断言 ——
	var names1 := _enemy_names(lv2)
	print("P5_RETURN enemies=", names1.size(), " (期望=", n0 - killed, ")",
		" ST1_alive=", names1.has("Host_ST1"), "(期望false)",
		" GY1_alive=", names1.has("Host_GY1"), "(期望false)",
		" ST2_alive=", names1.has("Host_ST2"), "(期望true)")
	if names1.has("Host_ST2"):
		var s2: Node3D = names1["Host_ST2"]
		print("P5_ST2 pos=", s2.global_position.round(), " (期望 (5,0.3,-40))",
			" hp=", snappedf(s2.get("health"), 0.01), " (期望0.37)")
	# 巡逻锚点重验证：ST2 巡逻圆心应=归位点（私有变量探针直读）
	var pc: Variant = names1["Host_ST2"].get("_patrol_center") if names1.has("Host_ST2") else null
	print("P5_ST2 patrol_center=", (pc as Vector3).round() if pc != null else "-",
		" (期望≈归位点=非出生点 (-1.5,0.3,-62) 一带)")
	var ok: bool = names1.size() == n0 - killed and not names1.has("Host_ST1") \
		and not names1.has("Host_GY1") and names1.has("Host_ST2") \
		and (names1["Host_ST2"] as Node3D).global_position.distance_to(Vector3(5, 0.3, -40)) < 0.5 \
		and absf((names1["Host_ST2"] as Node).get("health") - 0.37) < 0.01
	print("PERSIST_", "PASS" if ok else "FAIL")
	quit()
