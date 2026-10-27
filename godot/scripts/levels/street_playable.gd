extends Node3D
## street_playable.gd — 街景可玩验收场景（实机第一人称 + N 键夜视）
## 复用 street_test 地图/昼夜驱动/驻军，照 main.tscn 模式总装 Player/HUD/AudioManager。
## 仅清掉开发用 OverviewCamera(fly_camera)，避免与玩家相机争 current。
## 注：OverviewCamera 只被 street_builder 的 --shot 截图路径引用，本场景不走该路径，可安全移除。

func _ready() -> void:
	var cam := get_node_or_null("StreetTest/OverviewCamera")
	if cam:
		cam.queue_free()
	# 取证钩子：--vm-shot <输出路径> [pistol|dmr|shotgun] [ads] [fill] [reload] [reload_seconds 秒]
	# 窗口模式跑真实场景；reload 走实际换弹信号，fill 仅提高取证环境光。正常游玩路径零变化。
	var args := OS.get_cmdline_user_args()
	if args.has("--vm-shot"):
		_vm_shot(args)


func _vm_shot(args: PackedStringArray) -> void:
	var out_path := "user://vm_shot.png"
	var idx := args.find("--vm-shot")
	if idx + 1 < args.size():
		out_path = args[idx + 1]
	var weapon_id := &"rifle"
	for candidate: StringName in [&"pistol", &"dmr", &"shotgun"]:
		if args.has(String(candidate)):
			weapon_id = candidate
	var node_name := "Rifle"
	match weapon_id:
		&"pistol": node_name = "Pistol"
		&"dmr": node_name = "DMR"
		&"shotgun": node_name = "Shotgun"
	var weapon_path := "Player/Camera3D/WeaponMount/" + node_name
	for i in 20:
		await get_tree().process_frame
	if args.has("fill"):
		for node in find_children("*", "WorldEnvironment", true, false):
			var env := (node as WorldEnvironment).environment
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.8, 0.85, 1.0)
			env.ambient_light_energy = 1.5
	if weapon_id != &"rifle":
		GameState.current_weapon = weapon_id
		Events.weapon_switched.emit(weapon_id)
		for i in 10:
			await get_tree().process_frame
	if args.has("ads"):
		# 按住开镜等效：置位后等 20 帧让 ADS_LERP_TIME 插值走满（挂载归中+FOV+准星层）
		GameState.is_aiming = true
		Events.player_aim_changed.emit(true)
		for i in 20:
			await get_tree().process_frame
	if args.has("reload"):
		var weapon := get_node_or_null(weapon_path)
		if weapon == null:
			push_error("vm-shot: requested weapon is missing")
			get_tree().quit(1)
			return
		GameState.set(weapon_id + "_mag", 0)
		weapon.call("_start_reload")
		var reload_frames := 42
		var reload_idx := args.find("reload_frames")
		if reload_idx >= 0 and reload_idx + 1 < args.size() and args[reload_idx + 1].is_valid_int():
			reload_frames = int(args[reload_idx + 1])
		var seconds_idx := args.find("reload_seconds")
		if seconds_idx >= 0 and seconds_idx + 1 < args.size() and args[seconds_idx + 1].is_valid_float():
			await get_tree().create_timer(float(args[seconds_idx + 1])).timeout
		else:
			for i in reload_frames:
				await get_tree().process_frame
		var mag := weapon.get("_magazine") as Node3D
		if mag != null:
			print("VM_SHOT mag pos=", mag.position, " rot=", mag.rotation_degrees)
	if args.has("fire"):
		# 弹道特效抓拍（2026-10-19）：压低枪口让弹着点落在前方路面，
		# 连射数发铺弹坑/火星，最后一发留在截图前 2 帧让枪口焰（0.05s≈3帧）入镜。
		var cam := get_node_or_null("Player/Camera3D") as Camera3D
		var player := get_node_or_null("Player")
		if cam != null and player != null:
			cam.rotation.x = -0.5
			player.set("_pitch", -0.5)  # 同步内部俯仰：开火后坐回调会按 _pitch 重置相机
		var w := get_node_or_null(weapon_path)
		if w != null and w.has_method("_fire"):
			for i in 6:
				w.call("_fire")
				for j in 4:
					await get_tree().process_frame
			w.call("_fire")
			for i in 2:
				await get_tree().process_frame
	if args.has("grenade"):
		# 榴档取证（2026-10-22）：置步枪射击模式为 &"grenade" 后走真实 _fire 分流——
		# 投射物 90m/s，抬枪口 0.25rad 让弹道留窗更久；逐帧打印投射物位置定位可见性。
		# boom 子模式（爆炸特效取证）：枪口微压 -0.10rad 让榴弹约 14m 外落街爆炸（近距大画面），
		# 等投射物消失（=已爆）后再过 N 帧（boom 后数字，默认 10）抓爆炸中段。
		GameState.fire_modes[&"rifle"] = &"grenade"
		Events.fire_mode_changed.emit(&"rifle", &"grenade")
		var boom := args.has("boom")
		var pitch: float = -0.10 if boom else 0.25
		var camg := get_node_or_null("Player/Camera3D") as Camera3D
		var playerg := get_node_or_null("Player")
		if camg != null and playerg != null:
			camg.rotation.x = pitch
			playerg.set("_pitch", pitch)
		for i in 5:
			await get_tree().process_frame
		var wg := get_node_or_null("Player/Camera3D/WeaponMount/Rifle")
		if wg != null and wg.has_method("_fire"):
			wg.call("_fire")
			if boom:
				var delay := 10
				var bidx := args.find("boom")
				if bidx + 1 < args.size() and args[bidx + 1].is_valid_int():
					delay = int(args[bidx + 1])
				var proj_seen := false
				for i in 180:
					await get_tree().process_frame
					if get_node_or_null("RPGProjectile") != null:
						proj_seen = true
					elif proj_seen:
						break
				for i in delay:
					await get_tree().process_frame
			else:
				for i in 6:
					await get_tree().process_frame
					var proj := get_node_or_null("RPGProjectile")
					if proj != null:
						print("VM_SHOT grenade t+", i, " pos=", (proj as Node3D).global_position)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("VM_SHOT saved=", out_path)
	if args.has("reload"):
		var weapon := get_node_or_null(weapon_path)
		if weapon != null and weapon.get("_is_reloading"):
			await get_tree().create_timer(weapon.weapon_data.reload_time).timeout
	get_tree().quit()
