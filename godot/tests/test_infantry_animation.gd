extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

var _failures: int = 0
var _autoload_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	_recreate_autoloads()
	paused = true
	_verify_real_death()
	var infantry := (load("res://scenes/enemies/infantry.tscn") as PackedScene).instantiate()
	var source_players := infantry.get_node("BodyMesh").find_children("*", "AnimationPlayer", true, false)
	_assert(source_players.size() == 1, "real GLB contains one animation player")
	if source_players.size() == 1:
		for clip_name in [&"idle", &"walk", &"run", &"attack", &"death"]:
			_assert((source_players[0] as AnimationPlayer).has_animation(clip_name), "real GLB has " + clip_name)
	for existing in infantry.get_node("BodyMesh").find_children("*", "AnimationPlayer", true, false):
		existing.free()
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip_name in [&"idle", &"walk", &"run", &"attack", &"death"]:
		var clip := Animation.new()
		clip.length = 1.0
		library.add_animation(clip_name, clip)
	player.add_animation_library(&"", library)
	infantry.get_node("BodyMesh").add_child(player)
	root.add_child(infantry)
	_assert(infantry._animation_player == player, "ready binds the injected animation player")

	infantry._set_state(infantry.State.PATROL)
	_assert(player.current_animation == "walk", "PATROL plays walk")
	infantry._set_state(infantry.State.ALERT)
	_assert(player.current_animation == "idle", "ALERT plays idle")
	infantry._set_state(infantry.State.TAKE_COVER)
	_assert(player.current_animation == "run", "TAKE_COVER plays run")
	infantry._set_state(infantry.State.PEEK)
	_assert(player.current_animation == "idle", "PEEK plays idle")
	infantry._set_state(infantry.State.ENGAGE)
	_assert(player.current_animation == "run", "ENGAGE plays run")
	for clip_name in [&"idle", &"walk", &"run"]:
		_assert(player.get_animation(clip_name).loop_mode == Animation.LOOP_LINEAR, clip_name + " loops")
	for clip_name in [&"attack", &"death"]:
		_assert(player.get_animation(clip_name).loop_mode == Animation.LOOP_NONE, clip_name + " does not loop")
	infantry._attack(1.0)
	_assert(player.current_animation == "attack", "spore attack plays attack")
	infantry._melee()
	_assert(player.current_animation == "attack", "melee plays attack")
	player.animation_finished.emit(&"attack")
	_assert(player.current_animation == "run", "finished attack restores state animation")

	infantry.take_damage(9999.0)
	_assert(player.current_animation == "death", "death plays death")
	_assert(not infantry.is_in_group(&"enemy"), "death leaves enemy group immediately")
	_assert(infantry.collision_layer == 0 and infantry.collision_mask == 0, "death disables body collision")
	var head_hitbox := infantry.get_node("HeadHitbox") as Area3D
	_assert(head_hitbox.collision_layer == 0 and head_hitbox.collision_mask == 0, "death disables head hitbox")
	_assert(not infantry.is_queued_for_deletion(), "death waits for animation before cleanup")
	player.animation_finished.emit(&"death")
	_assert(infantry.is_queued_for_deletion(), "death animation completion cleans up")

	root.remove_child(infantry)
	infantry.free()
	var fallback := (load("res://scenes/enemies/infantry.tscn") as PackedScene).instantiate()
	for existing in fallback.get_node("BodyMesh").find_children("*", "AnimationPlayer", true, false):
		existing.free()
	root.add_child(fallback)
	fallback.take_damage(9999.0)
	_assert(fallback.is_queued_for_deletion(), "missing animation player keeps immediate cleanup")
	root.remove_child(fallback)
	fallback.free()
	_free_autoloads()
	print("test_infantry_animation: " + str(_failures) + " assertion(s) failed")
	quit(1 if _failures > 0 else 0)


func _verify_real_death() -> void:
	var instance := (load("res://scenes/enemies/infantry.tscn") as PackedScene).instantiate()
	root.add_child(instance)
	var players := instance.get_node("BodyMesh").find_children("*", "AnimationPlayer", true, false)
	var skeletons := instance.get_node("BodyMesh").find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skeletons.is_empty():
		_assert(false, "real death requires animation player and skeleton")
	else:
		var player := players[0] as AnimationPlayer
		var skeleton := skeletons[0] as Skeleton3D
		var death := player.get_animation(&"death")
		var hips := skeleton.find_bone("mixamorig_Hips")
		_assert(death.get_track_count() > 0 and hips >= 0, "real death has bone tracks and hips")
		player.play(&"death")
		player.advance(0.0)
		var start_y := skeleton.get_bone_global_pose(hips).origin.y
		player.advance(death.length)
		var end_y := skeleton.get_bone_global_pose(hips).origin.y
		_assert(start_y - end_y > 0.25, "real death hips descend to the ground")
	root.remove_child(instance)
	instance.free()


func _recreate_autoloads() -> void:
	for entry in AUTOLOADS:
		var node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
		_autoload_nodes.append(node)


func _free_autoloads() -> void:
	for node in _autoload_nodes:
		root.remove_child(node)
		node.free()
	_autoload_nodes.clear()
