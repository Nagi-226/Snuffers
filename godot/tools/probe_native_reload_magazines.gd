## Real range/player view of the fourteen detachable long-gun reload platforms.
extends SceneTree

const WEAPONS := [&"rifle", &"smg", &"lmg", &"dmr", &"shotgun", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1"]
const OUTPUT := "res://tmp_shots/native_reload_magazines"

var _shots := 0
var _rows: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("native magazine probe requires a rendered viewport")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var state = root.get_node("GameState")
	state.reset()
	var profiles: Dictionary = root.get_node("GameConfig").get_script().get_script_constant_map().MAGAZINE_RELOAD_PROFILES
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player = scene.get_node("Player")
	for node in scene.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for weapon_id in WEAPONS:
		player._switch_weapon(weapon_id)
		var weapon
		for child in player.get_node("Camera3D/WeaponMount").get_children():
			var data = child.get("weapon_data")
			if data != null and data.weapon_id == weapon_id:
				weapon = child
				break
		if weapon == null or weapon.get("_magazine") == null or weapon.get("_magazine_reload") == null:
			push_error("native probe missing real magazine platform: " + weapon_id)
			quit(1)
			return
		player._set_aiming(false)
		for frame in 30:
			player._process(1.0 / 60.0)
			weapon._process(0.0)
		await _shot(weapon_id, "hold", weapon)
		var configured_mag = weapon.get("mag_state_property")
		var mag_key: StringName = configured_mag if configured_mag != null else weapon_id + "_mag"
		var reserve_key: StringName = weapon.get("reserve_state_property")
		if reserve_key == &"":
			reserve_key = weapon_id + "_reserve"
		state.set(mag_key, 1)
		state.set(reserve_key, weapon.weapon_data.mag_size * 2)
		# Sample the production reload-start callback at fixed phases. Timed
		# completion and cancellation are exercised by the platform test.
		root.get_node("Events").weapon_reload_started.emit(weapon_id)
		var animation: AnimationPlayer = weapon.get("_arms_animation")
		animation.pause()
		var profile: Dictionary = profiles[weapon_id]
		var phases := {"contact": float(profile.contact_phase), "pulled": float(profile.pull_phase), "exchange": (float(profile.pull_phase) + float(profile.new_phase)) * 0.5, "incoming": float(profile.new_phase), "seated": float(profile.seat_phase)}
		for label in phases:
			animation.seek(float(phases[label]) * weapon.weapon_data.reload_time, true)
			weapon._process(0.0)
			await _shot(weapon_id, label, weapon)
		weapon._is_reloading = false
		weapon._reload_generation += 1
		weapon._reset_reload_visuals()
		player._set_aiming(true)
		for frame in 30:
			player._process(1.0 / 60.0)
			weapon._process(0.0)
		await _shot(weapon_id, "ads", weapon)
	var report := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	if report == null:
		push_error("cannot write native reload report")
		quit(1)
		return
	report.store_string(JSON.stringify(_rows, "\t"))
	report.close()
	print("NATIVE_RELOAD_MAGAZINES COMPLETED shots=", _shots, " platforms=", WEAPONS.size())
	scene.queue_free()
	await process_frame
	quit(0)


func _shot(weapon_id: StringName, label: String, weapon: Node3D) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/%s_%s.png" % [weapon_id, label]
	var result := root.get_texture().get_image().save_png(path)
	if result != OK:
		push_error("cannot save native reload screenshot: " + path)
		quit(1)
		return
	var magazine: Node3D = weapon.get("_magazine")
	_rows.append({"weapon": String(weapon_id), "stage": label, "path": path, "save_error": result, "magazine_visible": magazine.visible, "magazine_position": str(magazine.global_position)})
	_shots += 1
