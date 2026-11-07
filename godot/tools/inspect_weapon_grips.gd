extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in ["res://scenes/weapons/rifle.tscn", "res://scenes/weapons/pistol.tscn", "res://scenes/weapons/smg.tscn", "res://scenes/weapons/lmg.tscn", "res://scenes/weapons/magnum.tscn"]:
		var weapon := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(weapon)
		await process_frame
		await process_frame
		var vm := weapon.get_node("ViewModel") as Node3D
		var inv := vm.global_transform.affine_inverse()
		print("GRIP ", path)
		var magazine = weapon.get("_magazine") as Node3D
		if magazine != null:
			print("  MAGAZINE_ACTUAL local=", inv * magazine.global_position)
			print("  MAGAZINE_TRANSFORM ", magazine.transform)
		for child in vm.get_children():
			if child is Node3D:
				print("  NODE ", child.name, " local=", inv * (child as Node3D).global_position)
		var skeletons := weapon.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton := skeletons[0] as Skeleton3D
			for prefix in ["Hand_L", "Hand_R", "Pmag", "PBody", "ACRRifle"]:
				for bone in skeleton.get_bone_count():
					var bone_name := skeleton.get_bone_name(bone)
					if bone_name.begins_with(prefix):
						var pose := skeleton.get_bone_global_pose(bone)
						print("  BONE ", bone_name, " local=", inv * (skeleton.global_transform * pose).origin)
		weapon.queue_free()
		await process_frame
	quit()
