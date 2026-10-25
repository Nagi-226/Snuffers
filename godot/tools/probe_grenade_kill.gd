## 榴弹杀伤复现探针（开发取证）：加载关卡 → 找一个寄生体 → 在其旁 2m 直接
## 引爆 rpg_projectile（走 rifle.tres 契约数据）→ 断言血量变化。零视觉依赖。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 20:
		await process_frame
	# 找一个寄生体（enemy 组）。
	var enemy: Node = null
	for n in root.get_tree().get_nodes_in_group(&"enemy"):
		enemy = n
		break
	if enemy == null:
		print("GRENADE_PROBE_FAIL no enemy found")
		quit()
		return
	print("GRENADE_PROBE enemy=", enemy.name, " hp_before=", enemy.get("health"))
	# 用步枪契约数据构造投射物，贴身 2m 引爆（真实结算路径）。
	var data: Resource = load("res://scenes/weapons/rifle.tres")
	var proj: Node3D = load("res://scenes/weapons/rpg_projectile.tscn").instantiate()
	level.add_child(proj)
	proj.global_position = (enemy as Node3D).global_position + Vector3(2.0, 0.5, 0.0)
	print("GRENADE_PROBE data kill_radius=", data.get("explode_kill_radius"),
		" kill_damage=", data.get("explode_kill_damage"),
		" radius=", data.get("explode_radius"),
		" damage=", data.get("explode_damage"))
	# 走真实路径：setup（发射方等价）后立刻引爆。
	proj.call("setup", Vector3.UP, [], data)
	proj.call("_explode", proj.global_position)
	await process_frame
	await process_frame
	print("GRENADE_PROBE hp_after=", enemy.get("health"), " alive=", is_instance_valid(enemy))
	quit()
