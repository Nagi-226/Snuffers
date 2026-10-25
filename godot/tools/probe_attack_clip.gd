## 巨宿主攻击剪辑时长探针（开发取证）：
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/enemies/infantry.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		var ap := player as AnimationPlayer
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				if String(anim_name).to_lower().contains("attack"):
					print("ATTACK_CLIP name=", anim_name, " length=", anim.length)
	quit()
