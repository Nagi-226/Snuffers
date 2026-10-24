extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

var _failures: int = 0
var _autoload_nodes: Array = []
var _reload_counts: Dictionary = {"rifle": 0, "pistol": 0}
var _reload_offsets: Dictionary = {}


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
	var events = _autoload_nodes[0]
	events.weapon_reloaded.connect(_on_weapon_reloaded)
	await _check_weapon("rifle", "res://scenes/weapons/rifle.tscn", "ViewModel/ArmsEM68A", 2.0, 12, 60, 0.18)
	await _check_weapon("pistol", "res://scenes/weapons/pistol.tscn", "ViewModel/ArmsEM57P", 1.6, 6, 30, 0.18)
	_assert(_reload_offsets["rifle"].distance_to(_reload_offsets["pistol"]) > 0.005, "rifle and pistol use different left-hand paths")
	events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	_free_autoloads()
	print("test_weapon_reload: " + str(_failures) + " assertion(s) failed")
	quit(1 if _failures > 0 else 0)


func _check_weapon(weapon_id: String, scene_path: String, arms_path: NodePath, duration: float, mag: int, reserve: int, contact_limit: float) -> void:
	var game_state = _autoload_nodes[2]
	game_state.reset()
	game_state.current_weapon = weapon_id as StringName
	game_state.set(weapon_id + "_mag", mag)
	game_state.set(weapon_id + "_reserve", reserve)
	var weapon := (load(scene_path) as PackedScene).instantiate()
	root.add_child(weapon)
	var players := weapon.get_node(arms_path).find_children("*", "AnimationPlayer", true, false)
	_assert(players.size() == 1, weapon_id + " arms has one animation player")
	if players.is_empty():
		weapon.queue_free()
		await process_frame
		return
	var player := players[0] as AnimationPlayer
	var skeletons := weapon.get_node(arms_path).find_children("*", "Skeleton3D", true, false)
	var initial_pose: Array[Transform3D] = []
	if not skeletons.is_empty():
		var initial_skeleton := skeletons[0] as Skeleton3D
		for bone in initial_skeleton.get_bone_count():
			initial_pose.append(initial_skeleton.get_bone_global_pose(bone))
	_assert(player.has_animation(&"reload"), weapon_id + " has reload clip")
	if not player.has_animation(&"reload"):
		weapon.queue_free()
		await process_frame
		return
	_assert(absf(player.get_animation(&"reload").length - duration) < 0.001, weapon_id + " reload duration: " + str(player.get_animation(&"reload").length))

	weapon._start_reload()
	weapon._start_reload()
	_assert(player.current_animation == "reload", weapon_id + " reload starts arm animation")
	var sleeves := weapon.get_node(arms_path).find_children("sleeve_ext_*", "Node3D", true, false)
	_assert(sleeves.size() > 0, weapon_id + " has sleeve extenders")
	for sleeve in sleeves:
		_assert(not sleeve.visible, weapon_id + " sleeve extenders hidden during reload")
	_assert(skeletons.size() == 1, weapon_id + " arms has skeleton")
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		player.advance(0.0)
		var max_offset := 0.0
		var max_rotation_error := 0.0
		for bone in skeleton.get_bone_count():
			max_offset = maxf(max_offset, initial_pose[bone].origin.distance_to(skeleton.get_bone_global_pose(bone).origin))
			var initial_rotation := initial_pose[bone].basis.get_rotation_quaternion()
			var first_rotation := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
			max_rotation_error = maxf(max_rotation_error, 1.0 - absf(initial_rotation.dot(first_rotation)))
		print("POSE_CONTINUITY ", weapon_id, " max_offset=", max_offset)
		_assert(max_offset < 0.001, weapon_id + " first frame preserves grip position")
		_assert(max_rotation_error < 0.0001, weapon_id + " first frame preserves grip rotation")
		var hand := skeleton.find_bone("hand.L_03")
		_assert(hand >= 0, weapon_id + " has left hand bone")
		_assert(skeleton.find_bone("magazine_motion") >= 0, weapon_id + " has baked magazine motion")
		if hand >= 0:
			player.advance(duration * 0.25)
			weapon._process(0.0)
			_assert(weapon._magazine.position.distance_to(weapon._mag_home) > 0.005, weapon_id + " magazine follows baked motion")
			_assert(weapon._magazine.position.distance_to(weapon._mag_home) < 0.35, weapon_id + " magazine motion stays near viewmodel")
			var hand_position := skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
			print("RELOAD_CONTACT ", weapon_id, " distance=", hand_position.distance_to(weapon._magazine.global_position),
				" hand=", hand_position, " magazine=", weapon._magazine.global_position)
			var early := skeleton.get_bone_global_pose(hand).origin
			player.advance(duration * 0.25)
			weapon._process(0.0)
			hand_position = skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
			print("RELOAD_CONTACT_MID ", weapon_id, " distance=", hand_position.distance_to(weapon._magazine.global_position))
			_assert(hand_position.distance_to(weapon._magazine.global_position) < contact_limit, weapon_id + " left hand reaches magazine in shared space")
			var middle := skeleton.get_bone_global_pose(hand).origin
			_assert(early.distance_to(middle) > 0.01, weapon_id + " left hand moves during reload")
			_reload_offsets[weapon_id] = middle - early
	await create_timer(duration + 0.1).timeout
	_assert(_reload_counts[weapon_id] == 1, weapon_id + " emits reloaded exactly once")
	_assert(game_state.get(weapon_id + "_mag") == weapon.weapon_data.mag_size, weapon_id + " refills magazine")
	_assert(game_state.get(weapon_id + "_reserve") == reserve - (weapon.weapon_data.mag_size - mag), weapon_id + " preserves reserve math")
	_assert(weapon._magazine != null and weapon._magazine.position.is_equal_approx(weapon._mag_home), weapon_id + " magazine returns home")
	_assert(weapon._magazine != null and weapon._magazine.basis.is_equal_approx(weapon._mag_home_basis), weapon_id + " magazine rotation restored")
	if not skeletons.is_empty():
		var final_offset := 0.0
		var final_rotation_error := 0.0
		var skeleton := skeletons[0] as Skeleton3D
		for bone in skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(bone)
			final_offset = maxf(final_offset, initial_pose[bone].origin.distance_to(pose.origin))
			final_rotation_error = maxf(final_rotation_error,
				1.0 - absf(initial_pose[bone].basis.get_rotation_quaternion().dot(pose.basis.get_rotation_quaternion())))
		_assert(final_offset < 0.001, weapon_id + " grip position restored")
		_assert(final_rotation_error < 0.0001, weapon_id + " grip rotation restored")
	for sleeve in sleeves:
		_assert(sleeve.visible, weapon_id + " sleeve extenders restored after reload")
	game_state.set(weapon_id + "_mag", mag)
	game_state.set(weapon_id + "_reserve", reserve)
	weapon._start_reload()
	await create_timer(0.25).timeout
	game_state.current_weapon = &"rpg"
	_autoload_nodes[0].weapon_switched.emit(&"rpg")
	await process_frame
	game_state.current_weapon = weapon_id as StringName
	_autoload_nodes[0].weapon_switched.emit(weapon_id as StringName)
	await process_frame
	_assert(not weapon._is_reloading, weapon_id + " weapon switch cancels reload state")
	_assert(player.current_animation != "reload", weapon_id + " weapon switch cancels reload animation")
	await create_timer(duration).timeout
	_assert(_reload_counts[weapon_id] == 1, weapon_id + " cancelled reload does not emit completion")
	_assert(game_state.get(weapon_id + "_mag") == mag, weapon_id + " cancelled reload preserves ammunition")
	_assert(game_state.get(weapon_id + "_reserve") == reserve, weapon_id + " cancelled reload preserves reserve")
	weapon.queue_free()
	await process_frame


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	_reload_counts[weapon_id] += 1


func _recreate_autoloads() -> void:
	for entry in AUTOLOADS:
		_autoload_nodes.append(root.get_node(entry[0]))


func _free_autoloads() -> void:
	_autoload_nodes.clear()
