## probe_explosion_fx.gd — 爆炸特效分层隔离取证（2026-10-22，根因排错用）
## 窗口模式：godot --path godot -s res://tools/probe_explosion_fx.gd -- <out_dir> <mode>
## mode: full / no_smoke / smoke_only / no_sparks —— 逐层排查方形边缘来源。
## 暗场 + 相机 25m 平视原点，触发一次 rpg_exploded，t≈1.0s 时截图。
extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nodes: Array = []
	for pair: Array in AUTOLOADS:
		var n = (load(pair[1]) as Script).new()
		n.name = pair[0]
		root.add_child(n)
		nodes.append(n)

	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	var mode: String = args[1] if args.size() > 1 else "full"
	var target_t: float = float(args[2]) if args.size() > 2 else 1.0

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.05)
	# fog 子模式：复刻街景浓雾（FOG_DENSITY 0.130），验证雾是否洗掉 ADD 火球
	if mode.ends_with("_fog"):
		e.fog_enabled = true
		e.fog_density = 0.13
		e.fog_light_color = Color(0.55, 0.58, 0.62)
	env.environment = e
	root.add_child(env)
	# 地面参照板（验证焦痕/冲击环贴地姿态）
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(60.0, 60.0)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.1, 0.1, 0.12)
	ground.material_override = gmat
	root.add_child(ground)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 25.0)
	cam.rotation_degrees.x = -3.0
	cam.current = true
	root.add_child(cam)

	var fx = (load("res://scripts/weapons/explosion_fx.gd") as Script).new()
	root.add_child(fx)
	await process_frame
	# 触发爆炸（池轮转 cursor=0 → 用的正是 inst0）
	var inst0: Dictionary = fx._instances[0]
	var t0 := Time.get_ticks_msec()
	root.get_node("Events").rpg_exploded.emit(Vector3(0.0, 0.5, 0.0))
	# 以特效模块自身时钟为准等到 t>=target_t（帧率不定，数帧不可靠）；
	# 驱动函数每帧会重置 visible，故隔离覆盖也要每帧重贴
	while inst0["t"] < target_t:
		await process_frame
		if mode == "no_smoke":
			for q: MeshInstance3D in inst0["smoke_quads"]:
				q.visible = false
		elif mode == "smoke_only":
			for q: MeshInstance3D in inst0["fire_quads"]:
				q.visible = false
			(inst0["light"] as OmniLight3D).visible = false
			(inst0["ring"] as MeshInstance3D).visible = false
			(inst0["sparks"] as GPUParticles3D).visible = false
		elif mode == "no_sparks":
			(inst0["sparks"] as GPUParticles3D).visible = false
		elif mode == "sparks_only":
			for q: MeshInstance3D in inst0["smoke_quads"]:
				q.visible = false
			for q: MeshInstance3D in inst0["fire_quads"]:
				q.visible = false
			(inst0["light"] as OmniLight3D).visible = false
			(inst0["ring"] as MeshInstance3D).visible = false
	print("PROBE fx_t=", inst0["t"], " wall_ms=", Time.get_ticks_msec() - t0)
	var img := root.get_texture().get_image()
	var path: String = out_dir.path_join("fx_probe_%s_t%s.png" % [mode, args[2] if args.size() > 2 else "1.0"])
	img.save_png(path)
	print("PROBE saved=", path)
	quit()
