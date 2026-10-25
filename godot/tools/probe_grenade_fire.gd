## 榴弹真实开火复现：street 关卡 + 玩家步枪 _fire_grenade 全链路。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	var rifle: Node = level.get_node_or_null("Player/Camera3D/WeaponMount/Rifle")
	if rifle == null:
		print("FIRE_PROBE_FAIL no rifle")
		quit()
		return
	var enemy: Node = null
	for n in level.get_tree().get_nodes_in_group(&"enemy"):
		enemy = n
		break
	if enemy == null:
		print("FIRE_PROBE_FAIL no enemy")
		quit()
		return
	var cam: Node3D = level.get_node("Player/Camera3D")
	# 敌人摆到相机正前 8m 平地。
	(enemy as Node3D).global_position = cam.global_position + (-cam.global_basis.z.normalized() * 8.0)
	(enemy as Node3D).global_position.y = cam.global_position.y - 1.8 + 0.5
	await process_frame
	print("FIRE_PROBE runtime kill_radius=", rifle.weapon_data.explode_kill_radius,
		" kill_damage=", rifle.weapon_data.explode_kill_damage,
		" radius=", rifle.weapon_data.explode_radius)
	print("FIRE_PROBE hp_before=", enemy.get("health"))
	var events: Node = root.get_node("/root/Events")
	events.connect("rpg_exploded", func(at: Vector3) -> void:
		print("FIRE_PROBE exploded_at=", at, " dist_to_enemy=", snappedf(at.distance_to((enemy as Node3D).global_position), 2))
		# 复刻 _apply_area_damage 的球形查询，透视结算输入。
		var space := (level as Node3D).get_world_3d().direct_space_state
		var shape := SphereShape3D.new()
		shape.radius = 15.0
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis.IDENTITY, at)
		params.collide_with_areas = true
		var results: Array = space.intersect_shape(params, 32)
		print("FIRE_PROBE shape_results=", results.size())
		for r in results:
			var c: Object = r["collider"]
			var cname: String = (c.get("name") if c is Node else str(c))
			print("FIRE_PROBE   collider=", cname, " groups_in_enemy=", c is Node and (c as Node).is_in_group(&"enemy")))
	var ok: bool = rifle.call("_fire_grenade")
	print("FIRE_PROBE fired=", ok)
	var proj_pos := ""
	for i in 150:
		await process_frame
		for n in level.get_children():
			if String(n.name).contains("RPG"):
				var p: Vector3 = (n as Node3D).global_position
				proj_pos = "(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]
		if i % 15 == 0:
			print("FIRE_PROBE t=", snappedf(i / 60.0, 2), " proj=", proj_pos)
		if not is_instance_valid(enemy) or float(enemy.get("health")) <= 0.0:
			break
	print("FIRE_PROBE hp_after=", enemy.get("health") if is_instance_valid(enemy) else "FREED(死亡)")
	quit()
