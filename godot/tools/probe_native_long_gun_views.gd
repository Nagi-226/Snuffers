## Production Player camera and callbacks; diagnostic fill changes only lighting.
extends SceneTree

const OUTPUT := "res://tmp_shots/native_long_gun_views"
const WEAPONS := [&"rifle", &"dmr", &"shotgun", &"smg", &"lmg", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("native long gun views require rendering")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var state = root.get_node("GameState")
	state.reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var player = scene.get_node("Player")
	for id in WEAPONS:
		state.weapon_unlocked[id] = true
	var fill := OmniLight3D.new()
	scene.add_child(fill)
	fill.global_position = player._camera.global_position + player._camera.global_basis * Vector3(0.10, 0.10, 0.05)
	fill.light_energy = 4.0
	fill.omni_range = 2.0
	for node in scene.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var shots := 0
	for id in WEAPONS:
		player._switch_weapon(id)
		var weapon: Node3D
		for candidate in player.get_node("Camera3D/WeaponMount").get_children():
			if candidate.weapon_data.weapon_id == id:
				weapon = candidate
				break
		if weapon == null:
			push_error("production Player long gun missing: %s" % id)
			quit(1)
			return
		for sample in [["hip", -1.0, false], ["ads", -1.0, true], ["contact", 0.18, false], ["pull", 0.42, false], ["exchange", 0.50, false], ["insert", 0.70, false], ["seat", 0.82, false]]:
			weapon._is_reloading = false
			weapon._reset_reload_visuals()
			player._set_aiming(bool(sample[2]))
			for frame in 30:
				player._restore_viewmodel_depth()
				weapon._process(1.0 / 60.0)
				player._process(1.0 / 60.0)
			if float(sample[1]) >= 0.0:
				# Exercise the existing visual event callback without elapsed screenshot
				# rendering completing a gameplay timer between selected phases.
				root.get_node("Events").weapon_reload_started.emit(id)
				weapon._arms_animation.seek(weapon.weapon_data.reload_time * float(sample[1]), true)
				player._restore_viewmodel_depth()
				weapon._process(0.0)
				player._process(1.0 / 60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var label := "%s_%s" % [id, sample[0]]
			if root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") != OK:
				push_error("cannot save native long gun screenshot: " + label)
				quit(1)
				return
			shots += 1
		weapon._is_reloading = false
		weapon._reset_reload_visuals()
	print("NATIVE_LONG_GUN_VIEWS COMPLETED shots=", shots)
	scene.queue_free()
	await process_frame
	quit(0)
