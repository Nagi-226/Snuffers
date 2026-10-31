extends SceneTree

const OUT_TEX := "res://assets/ui/minimap_district_b.png"
const OUT_CALIB := "res://assets/ui/minimap_district_b.json"
const IMG_SIZE := 2048
const HALF_EXTENT := 236.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	await process_frame
	for node in scene.get_children():
		if node is Node3D or node is CanvasLayer:
			node.visible = node.name not in [&"Player", &"HUD", &"NightVisionOverlay"]
	for enemy in get_nodes_in_group(&"enemy"):
		(enemy as Node3D).visible = false
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).begins_with("Roof") or node.get_parent().name == &"WarehouseRoof":
			(node as MeshInstance3D).visible = false
	for node in scene.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.9, 1.0)
		env.ambient_light_energy = 1.3
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var sub := SubViewport.new()
	sub.size = Vector2i(IMG_SIZE, IMG_SIZE)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = HALF_EXTENT * 2.0
	camera.far = 700.0
	camera.position = Vector3(0, 400, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	sub.add_child(camera)
	camera.current = true
	for i in 12:
		await process_frame
	var image := sub.get_texture().get_image()
	image.save_png(OUT_TEX)
	var calib := {
		"min_x": -HALF_EXTENT, "max_x": HALF_EXTENT,
		"min_z": -HALF_EXTENT, "max_z": HALF_EXTENT,
		"img": IMG_SIZE,
	}
	var file := FileAccess.open(OUT_CALIB, FileAccess.WRITE)
	file.store_string(JSON.stringify(calib, "  "))
	file.close()
	print("DISTRICT_MINIMAP saved=", OUT_TEX, " calib=", OUT_CALIB)
	quit()
