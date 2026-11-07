extends SceneTree

const IMG_SIZE := 2048
const OUT_TEX := "res://assets/ui/minimap_range.png"
const OUT_CALIB := "res://assets/ui/minimap_range.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	await process_frame
	for top in scene.get_children():
		if top.name in ["Player", "HUD", "AudioManager"]:
			if top is Node3D or top is CanvasLayer:
				top.visible = false
	scene.get_node("GreyboxArena/ExtractZone").visible = false
	for target in get_nodes_in_group(&"range_target"):
		(target as Node3D).visible = false
	for label in scene.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	for n in scene.find_children("*", "WorldEnvironment", true, false):
		var env := (n as WorldEnvironment).environment
		if env == null:
			continue
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.9, 1.0)
		env.ambient_light_energy = 1.1
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var sub := SubViewport.new()
	sub.size = Vector2i(IMG_SIZE, IMG_SIZE)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 132.0
	cam.far = 450.0
	cam.position = Vector3(0, 250, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	sub.add_child(cam)
	cam.current = true
	for frame in 12:
		await process_frame
	sub.get_texture().get_image().save_png(OUT_TEX)
	var calib := {"min_x": -100.0, "max_x": 100.0, "min_z": -66.0, "max_z": 66.0, "img": IMG_SIZE}
	var f := FileAccess.open(OUT_CALIB, FileAccess.WRITE)
	f.store_string(JSON.stringify(calib, "  "))
	f.close()
	print("RANGE_MINIMAP saved=", OUT_TEX)
	quit()
