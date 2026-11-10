extends SceneTree

const OUTPUT := "res://tmp_shots/black_pistol_arms"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/player/black_pistol_preview.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var shots := 0
	for item in [["idle", 0.0], ["fire", 0.5], ["reload", 0.25], ["reload", 0.50], ["reload", 0.75], ["reload_empty", 0.50]]:
		scene.adapter.reset()
		var clip: String = item[0]
		var length: float = scene.adapter.animation.get_animation(clip).length
		if clip in ["reload", "reload_empty"]:
			scene.adapter.play_reload(length, clip == "reload_empty")
		elif clip == "fire":
			scene.adapter.play_fire()
		scene.adapter.animation.seek(length * float(item[1]), true)
		scene.adapter.update(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(OUTPUT + "/gen5_%s_%03d.png" % [clip, int(float(item[1]) * 100)])
		if result != OK:
			push_error("native pistol preview could not save screenshot")
			quit(1)
			return
		shots += 1
	print("BLACK_PISTOL_VIEWS COMPLETED shots=", shots)
	quit()
