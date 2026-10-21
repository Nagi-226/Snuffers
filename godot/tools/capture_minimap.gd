extends SceneTree
## 俯视地形底图离线渲染（HUD 圆形小地图配套，2026-10-21 蜂后工具）
## 用法: godot --path godot -s res://tools/capture_minimap.gd
## （窗口模式跑一次真实渲染即退出；产物提交入库，运行时不做 3D 捕获）
## 输出: assets/ui/minimap_street.png（2048² 俯视正交图）+ minimap_street.json（世界→像素标定）
##
## 处理要点：
## - 隐藏敌人驻军 / 远景天际线（环带幕布会撑爆取景范围且不属于可玩地形）
## - 关雾（俯视 250m 穿透雾层会把画面洗白）、提亮环境光（夜景 schematic 化，ASI 风格）
## - 冻结场景 process（防昼夜驱动复原雾/应急灯闪烁引入不确定性）

const SCENE := "res://scenes/levels/street_test.tscn"
const OUT_TEX := "res://assets/ui/minimap_street.png"
const OUT_CALIB := "res://assets/ui/minimap_street.json"
const IMG_SIZE := 2048
const CAM_HEIGHT := 250.0
const PADDING := 6.0
## 参与取景范围统计的顶层组（可玩地形；Skyline/Backdrop 排除）
const BOUNDS_GROUPS := ["Ground", "Buildings", "Barriers", "Props"]
## 渲染时整体隐藏的顶层节点名前缀
const HIDE_TOP := ["Skyline", "Backdrop"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 隐藏敌人驻军（走 G2 契约组）与远景层
	for n in get_nodes_in_group(&"enemy"):
		if n is Node3D:
			(n as Node3D).visible = false
	for top in scene.get_children():
		for prefix in HIDE_TOP:
			if top.name.begins_with(prefix):
				if top is Node3D:
					(top as Node3D).visible = false

	# 关雾 + 提亮环境光（夜景 schematic 化）
	for n in scene.find_children("*", "WorldEnvironment", true, false):
		var env := (n as WorldEnvironment).environment
		if env == null:
			continue
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.9, 1.0)
		env.ambient_light_energy = 1.1

	# 取景范围：可玩地形组的可见网格 AABB 合集
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for grp in BOUNDS_GROUPS:
		var row := scene.get_node_or_null(grp)
		if row == null:
			continue
		for mi in row.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not m.visible:
				continue
			var aabb := m.get_aabb()
			var gt := m.global_transform
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var p8 := gt * (aabb.position + aabb.size * Vector3(
							(sx + 1.0) * 0.5, (sy + 1.0) * 0.5, (sz + 1.0) * 0.5))
						mn = mn.min(p8)
						mx = mx.max(p8)
	if mn.x > mx.x:
		printerr("CAPTURE_MINIMAP: no bounds collected")
		quit(1)
		return

	var cx := (mn.x + mx.x) * 0.5
	var cz := (mn.z + mx.z) * 0.5
	var half := maxf(mx.x - mn.x, mx.z - mn.z) * 0.5 + PADDING
	print("CAPTURE_MINIMAP bounds x[%.1f..%.1f] z[%.1f..%.1f] half=%.1f" % [
		mn.x, mx.x, mn.z, mx.z, half])

	# 冻结场景脚本（防昼夜驱动/任务导演在渲染间隙改环境）
	scene.process_mode = Node.PROCESS_MODE_DISABLED

	# SubViewport 精确控制 2048² 输出（共享主世界 3D）
	var sub := SubViewport.new()
	sub.size = Vector2i(IMG_SIZE, IMG_SIZE)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = half * 2.0
	cam.far = CAM_HEIGHT + 200.0
	cam.position = Vector3(cx, CAM_HEIGHT, cz)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # 正俯视：画面上=世界-Z，右=+X
	sub.add_child(cam)
	cam.current = true

	for i in 12:
		await process_frame

	var img := sub.get_texture().get_image()
	img.save_png(OUT_TEX)
	var calib := {
		"min_x": cx - half, "max_x": cx + half,
		"min_z": cz - half, "max_z": cz + half,
		"img": IMG_SIZE,
	}
	var f := FileAccess.open(OUT_CALIB, FileAccess.WRITE)
	f.store_string(JSON.stringify(calib, "  "))
	f.close()
	print("CAPTURE_MINIMAP saved=", OUT_TEX, " calib=", OUT_CALIB)
	quit()
