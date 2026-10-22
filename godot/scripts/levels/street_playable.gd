extends Node3D
## street_playable.gd — 街景可玩验收场景（实机第一人称 + N 键夜视）
## 复用 street_test 地图/昼夜驱动/驻军，照 main.tscn 模式总装 Player/HUD/AudioManager。
## 仅清掉开发用 OverviewCamera(fly_camera)，避免与玩家相机争 current。
## 注：OverviewCamera 只被 street_builder 的 --shot 截图路径引用，本场景不走该路径，可安全移除。

func _ready() -> void:
	var cam := get_node_or_null("StreetTest/OverviewCamera")
	if cam:
		cam.queue_free()
	# 取证钩子：--vm-shot <输出路径> [reload] —— 窗口模式跑真实场景（autoload/脚本
	# 全量生效，比自定义 SceneTree 探针保真），20 帧稳定后截图退出；带 reload 时
	# 先触发步枪换弹再在动画中段（约 0.7s）抓拍弹匣脱落姿态。正常游玩路径零变化。
	var args := OS.get_cmdline_user_args()
	if args.has("--vm-shot"):
		_vm_shot(args)


func _vm_shot(args: PackedStringArray) -> void:
	var out_path := "user://vm_shot.png"
	var idx := args.find("--vm-shot")
	if idx + 1 < args.size():
		out_path = args[idx + 1]
	for i in 20:
		await get_tree().process_frame
	if args.has("pistol"):
		# 切到手枪（2 号键位等效；直写状态+广播，与 player_controller._switch_weapon 同序列）
		GameState.current_weapon = &"pistol"
		Events.weapon_switched.emit(&"pistol")
		for i in 10:
			await get_tree().process_frame
	if args.has("ads"):
		# 按住开镜等效：置位后等 20 帧让 ADS_LERP_TIME 插值走满（挂载归中+FOV+准星层）
		GameState.is_aiming = true
		Events.player_aim_changed.emit(true)
		for i in 20:
			await get_tree().process_frame
	if args.has("reload"):
		var rifle := get_node_or_null("Player/Camera3D/WeaponMount/Rifle")
		if rifle != null and rifle.has_method("_play_reload_anim"):
			rifle.call("_play_reload_anim")  # 直触动画面数，绕过满弹匣的 _start_reload 守卫
		for i in 42:
			await get_tree().process_frame
		var mag: Node3D = rifle.get_node_or_null("ViewModel/EM68A/em68a_magazine")
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
		var w := get_node_or_null("Player/Camera3D/WeaponMount/Rifle")
		if args.has("pistol"):
			w = get_node_or_null("Player/Camera3D/WeaponMount/Pistol")
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
		GameState.fire_modes[&"rifle"] = &"grenade"
		Events.fire_mode_changed.emit(&"rifle", &"grenade")
		var camg := get_node_or_null("Player/Camera3D") as Camera3D
		var playerg := get_node_or_null("Player")
		if camg != null and playerg != null:
			camg.rotation.x = 0.25
			playerg.set("_pitch", 0.25)
		for i in 5:
			await get_tree().process_frame
		var wg := get_node_or_null("Player/Camera3D/WeaponMount/Rifle")
		if wg != null and wg.has_method("_fire"):
			wg.call("_fire")
			for i in 6:
				await get_tree().process_frame
				var proj := get_node_or_null("RPGProjectile")
				if proj != null:
					print("VM_SHOT grenade t+", i, " pos=", (proj as Node3D).global_position)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("VM_SHOT saved=", out_path)
	get_tree().quit()
