## 两把 EM 手枪在真实靶场玩家相机下的原生手臂/ADS/拆匣取证。
extends SceneTree

const OUTPUT := "res://tmp_shots/black_pistol_integration"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("pistol integration screenshots require native rendering")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var state = root.get_node("GameState")
	state.reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var player = scene.get_node("Player")
	var output := OUTPUT
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty() and arguments[0] in ["before_grip", "after_grip"]:
		output += "/" + arguments[0]
		# 诊断补光仅用于几何前后对照，保留生产玩家相机、FOV、网格和手臂姿态。
		var fill := OmniLight3D.new()
		scene.add_child(fill)
		fill.global_position = player._camera.global_position + player._camera.global_basis * Vector3(0.10, 0.10, 0.05)
		fill.light_energy = 4.0
		fill.omni_range = 2.0
	for node in scene.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(output)
	var shots := 0
	for weapon_id in [&"pistol", &"magnum"]:
		player._switch_weapon(weapon_id)
		var weapon = player.get_node("Camera3D/WeaponMount/" + ("Pistol" if weapon_id == &"pistol" else "Magnum"))
		if weapon._native_arms == null:
			push_error("pistol integration adapter missing: %s" % weapon_id)
			quit(1)
			return
		for item in [["idle", 0.0, false], ["idle", 0.0, true], ["fire", 0.5, false], ["reload", 0.25, false], ["reload", 0.5, false], ["reload", 0.75, false], ["reload_empty", 0.5, false]]:
			weapon._is_reloading = false
			weapon._reset_reload_visuals()
			player._set_aiming(bool(item[2]))
			for frame in 30:
				player._process(1.0 / 60.0)
				weapon._process(0.0)
			var clip: String = item[0]
			if clip == "fire":
				weapon._native_arms.play_fire()
			elif clip in ["reload", "reload_empty"]:
				state.set(weapon.mag_state_property, 0 if clip == "reload_empty" else 2)
				weapon._is_reloading = true
				weapon._play_reload_anim()
			var duration: float = weapon._arms_animation.get_animation(clip).length
			weapon._arms_animation.seek(duration * float(item[1]), true)
			weapon._process(0.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var label := "%s_%s_%03d_%s" % [weapon_id, clip, int(float(item[1]) * 100), "ads" if bool(item[2]) else "hip"]
			if root.get_texture().get_image().save_png(output + "/" + label + ".png") != OK:
				push_error("cannot save pistol integration screenshot: " + label)
				quit(1)
				return
			shots += 1
	print("BLACK_PISTOL_INTEGRATION_VIEWS COMPLETED shots=", shots)
	scene.queue_free()
	await process_frame
	quit(0)
