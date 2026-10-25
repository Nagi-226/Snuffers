## 榴弹探针二分：step 由 argv 控制（1=仅加载 2=+setup 3=+explode）。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var step := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = int(a.split("=")[1])
	var world := Node3D.new()
	root.add_child(world)
	var enemy: Node3D = load("res://scenes/enemies/infantry.tscn").instantiate()
	world.add_child(enemy)
	await process_frame
	await process_frame
	print("BISECT step=", step, " enemy_hp=", enemy.get("health"))
	if step < 2:
		quit()
		return
	var proj: Node3D = load("res://scenes/weapons/rpg_projectile.tscn").instantiate()
	world.add_child(proj)
	enemy.global_position = Vector3.ZERO
	proj.global_position = Vector3(2.0, 0.5, 0.0)
	var data: WeaponData = load("res://scenes/weapons/rifle.tres")
	print("BISECT data=", data, " kill_radius=", data.explode_kill_radius, " kill_damage=", data.explode_kill_damage)
	if step < 3:
		quit()
		return
	proj.call("setup", Vector3.UP, [] as Array[RID], data)
	print("BISECT setup_done")
	proj.call("_explode", proj.global_position)
	print("BISECT explode_returned")
	await create_timer(0.1).timeout
	print("BISECT hp_after=", enemy.get("health"), " valid=", is_instance_valid(enemy))
	quit()
