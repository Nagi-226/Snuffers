## 榴弹杀伤最小复现探针 v2：空场景单寄生体贴身引爆，隔离大关卡变量。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var enemy: Node3D = load("res://scenes/enemies/infantry.tscn").instantiate()
	world.add_child(enemy)
	await process_frame
	await process_frame
	print("GRENADE_PROBE hp_before=", enemy.get("health"))
	var data: Resource = load("res://scenes/weapons/rifle.tres")
	print("GRENADE_PROBE kill_radius=", data.get("explode_kill_radius"),
		" kill_damage=", data.get("explode_kill_damage"))
	var proj: Node3D = load("res://scenes/weapons/rpg_projectile.tscn").instantiate()
	world.add_child(proj)
	enemy.global_position = Vector3.ZERO
	proj.global_position = Vector3(2.0, 0.5, 0.0)
	proj.call("setup", Vector3.UP, [], data)
	proj.call("_explode", proj.global_position)
	await create_timer(0.1).timeout
	print("GRENADE_PROBE hp_after=", enemy.get("health"), " valid=", is_instance_valid(enemy))
	quit()
