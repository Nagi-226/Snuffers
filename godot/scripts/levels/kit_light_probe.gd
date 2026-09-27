extends Node3D
## kit 材质光照最小复现：四块 kit_wall 分别旋转 0/90/180/270°，恒定环境光、无平行光
## 用法: godot --path . res://scenes/levels/kit_light_probe.tscn -- --shot <路径>

const KIT_WALL := preload("res://assets/models/kit_wall.glb")


func _ready() -> void:
	for i in 4:
		var inst: Node3D = KIT_WALL.instantiate()
		inst.position = Vector3((float(i) - 1.5) * 3.5, 0.0, 0.0)
		inst.rotation_degrees.y = float(i) * 90.0
		inst.name = "Wall_rot%d" % (i * 90)
		add_child(inst)

	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		var out_path := "user://kit_probe.png"
		var idx := args.find("--shot")
		if idx + 1 < args.size():
			out_path = args[idx + 1]
		for j in 15:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		print("KIT_PROBE saved err=%d" % img.save_png(out_path))
		get_tree().quit()
