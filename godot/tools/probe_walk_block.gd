## probe_walk_block.gd — 真人玩家行走阻断复现（2026-10-23 机主实拍报修：两处走不动）
## 用法：godot --headless --path godot -s res://tools/probe_walk_block.gd
## 实例化真实 street_playable（含真玩家控制器），注入 W 键物理按键事件直行 4 秒，
## 逐秒报玩家坐标；提前停下的在停点球形查询报出碰撞体名字。
extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

## [标签, 起点, 朝向yaw(0=北/-Z, PI=南), 预期终点轴值, 轴名]
const TESTS: Array = [
	["主街北行→北力场", Vector3(0.0, 1.1, -60.0), 0.0, -94.0, "z"],
	["南延南行→南力场", Vector3(0.0, 1.1, 42.0), PI, 67.5, "z"],
	["横街东行→东力场", Vector3(10.0, 1.1, 33.2), -PI * 0.5, 38.0, "x"],
	["横街西行→西力场", Vector3(-10.0, 1.1, 33.2), PI * 0.5, -38.0, "x"],
]


func _init() -> void:
	call_deferred("_run")


func _key(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _run() -> void:
	for pair: Array in AUTOLOADS:
		var n = (load(pair[1]) as Script).new()
		n.name = pair[0]
		root.add_child(n)
	var scene: Node = (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 20:
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var space = scene.get_world_3d().direct_space_state
	if player == null:
		print("PROBE player NOT FOUND")
		quit()
		return
	player.set_process_input(false)  # 防鼠标捕获干扰；移动走物理帧轮询不受影响
	# 寄生体全部挪到远处并冻结（本探针验证地形/边界，不验证交战；它们追人会挡路干扰读数）
	for node in scene.get_children():
		if String(node.name).begins_with("Host"):
			(node as Node3D).global_position = Vector3(90.0, 1.0, 90.0)
			(node as Node).set_physics_process(false)
	for t: Array in TESTS:
		player.global_position = t[1]
		player.rotation.y = t[2]
		player.velocity = Vector3.ZERO
		for i in 30:
			await physics_frame  # 落地站稳
		var start: Vector3 = player.global_position
		_key(true)
		for sec in 8:
			for i in 60:
				await physics_frame
			if sec % 2 == 1:
				print("  [%s] t+%ds pos=%s" % [t[0], sec + 1, player.global_position])
		_key(false)
		var reached: float = player.global_position.z if t[4] == "z" else player.global_position.x
		var target: float = t[3]
		if absf(reached - target) < 3.0:
			print("== %s: 正常走到幕墙前 %.2f ✅" % [t[0], reached])
		else:
			# 提前停：在车头方向 0.6m 处查碰撞体
			var fwd := -player.global_transform.basis.z
			var ball := SphereShape3D.new()
			ball.radius = 0.5
			var bq := PhysicsShapeQueryParameters3D.new()
			bq.shape = ball
			bq.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(0, 0.2, 0) + fwd * 0.6)
			bq.exclude = [player.get_rid()]
			var names: Array[String] = []
			for h: Dictionary in space.intersect_shape(bq, 6):
				names.append(String((h["collider"] as Node).name))
			print("== %s: 提前停在 %.2f（起点 %.2f）⚠ 前方碰撞体: %s" % [t[0], reached,
				start.z if t[4] == "z" else start.x, ", ".join(names)])
	quit()
