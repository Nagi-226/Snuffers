## L1 startup smoke: let deferred ready work finish, then free the scene before quitting.
extends SceneTree


func _init() -> void:
	# Dummy audio retires stopped playback on its real-time mix thread, then the main thread.
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("scene boot smoke requires one scene path")
		quit(1)
		return
	var packed := load(arguments[0]) as PackedScene
	if packed == null:
		push_error("scene boot smoke could not load " + arguments[0])
		quit(1)
		return
	var scene := packed.instantiate()
	if scene == null:
		push_error("scene boot smoke could not instantiate " + arguments[0])
		quit(1)
		return
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene.queue_free()
	await process_frame
	await process_frame
	print("SCENE_BOOT_COMPLETED ", arguments[0])
	quit(0)
