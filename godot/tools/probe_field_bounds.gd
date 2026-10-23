## probe_field_bounds.gd — 驻军嵌墙 + 力场空气墙专项排查（2026-10-23 机主派单 1/2）
## 用法：godot --headless --path godot -s res://tools/probe_field_bounds.gd
## A. 全部 Host_* 寄生体落点做球形相交查询 → 嵌入建筑体/道具者报 EMBEDDED
## B. 四向力场（北 z=-95 / 南 z=+68 / 东西 x=±38.5）内側三排射线 →
##    首个命中不是 FIELD/PYLON 系 = 力场前方存在隐形空气墙，报命中体与距离
extends SceneTree

const HOST_R := 0.35 ## 寄生体胶囊半径近似（玩家 0.35 同口径）


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = (load("res://scenes/levels/street_test.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	# 等物理空间注册完毕
	for i in 10:
		await physics_frame

	var space := scene.get_world_3d().direct_space_state

	# ===== A. 驻军嵌墙检查 =====
	print("== A. Host 落点嵌墙检查（球半径 %.2f）==" % HOST_R)
	for node in scene.get_children():
		if not (node is Node3D and String(node.name).begins_with("Host")):
			continue
		var p := (node as Node3D).global_position + Vector3(0.0, 0.6, 0.0)
		var shape := SphereShape3D.new()
		shape.radius = HOST_R
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis.IDENTITY, p)
		params.exclude = [(node as CollisionObject3D).get_rid()] if node is CollisionObject3D else []
		var hits := space.intersect_shape(params, 8)
		if hits.is_empty():
			print("  OK   %s @ %s" % [node.name, (node as Node3D).global_position])
		else:
			for h: Dictionary in hits:
				var c: Object = h["collider"]
				print("  EMBEDDED %s @ %s → 穿入 %s" % [node.name, (node as Node3D).global_position, _cname(c)])

	# ===== B. 力场前方空气墙检查 =====
	print("== B. 四向力场前方空气墙检查（内侧射线，预期首中 = FIELD/PYLON @ 幕墙位）==")
	var dirs: Array = [
		["北场", Vector3(0, 1.2, -80), Vector3(0, 0, -1), -95.0, "z", []],
		["南场", Vector3(0, 1.2, 55), Vector3(0, 0, 1), 68.0, "z", []],
		["东场", Vector3(25, 1.2, 34.25), Vector3(1, 0, 0), 38.5, "x", []],
		["西场", Vector3(-25, 1.2, 34.25), Vector3(-1, 0, 0), -38.5, "x", []],
	]
	# 全宽加密扫描：南北场 x -6.5..6.5（路面+人行道全覆盖），东西场 z 28.6..39.9（柱间距全覆盖）
	var ns_offsets: Array = []
	for i in 14:
		ns_offsets.append(-6.5 + float(i))
	var ew_offsets: Array = []
	for i in 12:
		ew_offsets.append(28.6 + float(i))
	dirs[0][5] = ns_offsets
	dirs[1][5] = ns_offsets
	dirs[2][5] = ew_offsets
	dirs[3][5] = ew_offsets
	for d: Array in dirs:
		var label: String = d[0]
		var origin: Vector3 = d[1]
		var dir: Vector3 = d[2]
		var field_pos: float = d[3]
		var axis: String = d[4]
		for off: float in d[5]:
			var o := origin
			if axis == "z":
				o.x = off
			else:
				o.z = off
			var query := PhysicsRayQueryParameters3D.create(o, o + dir * 60.0)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				print("  %s off=%.2f: 60m 无命中（异常：幕墙未命中？）" % [label, off])
				continue
			var hp: Vector3 = hit["position"]
			var hit_plane: float = hp.z if axis == "z" else hp.x
			var dist_to_field := absf(hit_plane - field_pos)
			var cname := _cname(hit["collider"])
			var verdict := "OK(幕墙)" if dist_to_field < 0.6 else "⚠ 空气墙? 距幕墙 %.2fm" % dist_to_field
			print("  %s off=%+.2f: 首中 %s @ %.2f  %s" % [label, off, cname, hit_plane, verdict])
	# ===== B2. 玩家胶囊扫掠（模拟行走，比射线更贴近真实体感）=====
	# 2026-10-23 机主实拍报修：主街两处「没法继续往前走」→ 走廊拉长 + 车道加密全覆盖
	print("== B2. 胶囊扫掠（半径 0.35 高 1.8，模拟玩家走向幕墙）==")
	var ns_lanes: Array = []
	for i in 9:
		ns_lanes.append(-6.0 + float(i) * 1.5)
	var sweeps: Array = [
		["北场", Vector3(0, 0, -50), Vector3(0, 0, -50), -95.0, ns_lanes],
		["南场", Vector3(0, 0, 40), Vector3(0, 0, 35), 68.0, ns_lanes],
		["东场", Vector3(15, 0, 0), Vector3(30, 0, 0), 38.5, [31.0, 34.25, 37.5]],
		["西场", Vector3(-15, 0, 0), Vector3(-30, 0, 0), -38.5, [31.0, 34.25, 37.5]],
	]
	for s: Array in sweeps:
		var label: String = s[0]
		var base: Vector3 = s[1]
		var motion: Vector3 = s[2]
		for off: float in s[4]:
			var o := base
			if absf(motion.z) > 0.1:
				o.x = off
			else:
				o.z = off
			o.y = 1.0
			var cap := CapsuleShape3D.new()
			cap.radius = 0.35
			cap.height = 1.8
			var pq := PhysicsShapeQueryParameters3D.new()
			pq.shape = cap
			pq.transform = Transform3D(Basis.IDENTITY, o)
			pq.motion = motion
			var res := space.cast_motion(pq)
			var frac: float = res[0]
			var stop := o + motion * frac
			var plane: float = stop.z if absf(motion.z) > 0.1 else stop.x
			# 提前被挡时找出凶手：在停点再做个小球相交查询报名字
			var note := "幕墙面前"
			if absf(plane - s[3]) >= 1.0:
				var ball := SphereShape3D.new()
				ball.radius = 0.6
				var bq := PhysicsShapeQueryParameters3D.new()
				bq.shape = ball
				bq.transform = Transform3D(Basis.IDENTITY, stop + motion.normalized() * 0.5)
				var hits := space.intersect_shape(bq, 4)
				var names: Array[String] = []
				for h: Dictionary in hits:
					names.append(_cname(h["collider"]))
				note = "⚠ 提前被挡 → " + ", ".join(names)
			print("  %s off=%+.2f: 胶囊走到 %.2f（%s）" % [label, off, plane, note])
	quit()


## 碰撞体可读名：沿路向上找有名字的祖先（builder 的盒子都带 id 名）
func _cname(c: Object) -> String:
	var n := c as Node
	var chain: Array[String] = []
	while n != null and chain.size() < 4:
		chain.append(String(n.name))
		n = n.get_parent()
	return " < ".join(chain)
