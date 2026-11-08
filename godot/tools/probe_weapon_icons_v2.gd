extends SceneTree

const WeaponIcon = preload("res://scripts/ui/weapon_icon.gd")
const OUT_DIR := "tmp_shots/weapon_icons_v2"


func _init() -> void:
	call_deferred("_run")


func _shot(label: String) -> void:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, label])
	if error != OK:
		push_error("Cannot save icon preview: " + label)
		quit(1)
	print("WEAPON_ICON_SHOT ", label)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var state = root.get_node("GameState")
	state.reset()
	var grid := CanvasLayer.new()
	root.add_child(grid)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.034, 0.049)
	background.size = Vector2(1600, 900)
	grid.add_child(background)
	var names = load("res://scripts/ui/hud.gd").new()
	var index := 0
	for category: Dictionary in root.get_node("GameConfig").WEAPON_CATEGORIES:
		for id: StringName in category.weapons:
			var origin := Vector2(35 + (index % 4) * 395, 35 + (index / 4) * 215)
			var label := Label.new()
			label.text = names._weapon_display_name(id)
			label.position = origin
			label.add_theme_font_size_override("font_size", 17)
			grid.add_child(label)
			var enlarged := TextureRect.new()
			enlarged.texture = WeaponIcon.ICONS[id]
			enlarged.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			enlarged.size = Vector2(240, 116)
			enlarged.position = origin + Vector2(0, 30)
			grid.add_child(enlarged)
			var actual := WeaponIcon.new()
			actual.weapon_id = id
			actual.selected = true
			actual.position = origin + Vector2(0, 151)
			grid.add_child(actual)
			var dimmed := WeaponIcon.new()
			dimmed.weapon_id = id
			dimmed.position = origin + Vector2(142, 151)
			grid.add_child(dimmed)
			index += 1
	names.free()
	if "--baseline" in OS.get_cmdline_user_args():
		await _shot("baseline_grid")
		quit()
		return
	await _shot("new_grid")
	grid.queue_free()
	await process_frame
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var day_night = scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	player.global_position = Vector3(44, 0.1, 19)
	player.rotation.y = PI
	player._camera.rotation = Vector3.ZERO
	await create_timer(0.3).timeout
	if "--interactive" in OS.get_cmdline_user_args():
		player._switch_weapon(&"em86m")
		print("WEAPON_ICONS_PREVIEW_READY: EM-86M selected; 1-6 switches categories")
		return
	for category: Dictionary in root.get_node("GameConfig").WEAPON_CATEGORIES:
		for id: StringName in category.weapons:
			player._switch_weapon(id)
			await create_timer(0.08).timeout
			await _shot("hud_" + id)
	root.size = Vector2i(1280, 720)
	player._switch_weapon(&"em12g2")
	await _shot("hud_720_shotgun_category")
	player._switch_weapon(&"em86m")
	await _shot("hud_720_machinegun_category")
	print("WEAPON_ICONS_PREVIEW_COMPLETE: 16 weapons and both HUD locations")
	scene.queue_free()
	await process_frame
	quit()
