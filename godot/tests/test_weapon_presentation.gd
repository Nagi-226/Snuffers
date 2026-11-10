extends SceneTree

const HandSkin = preload("res://tests/hand_skin_probe.gd")

var _failures := 0
var _source_fore_length := 0.0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _settle(player: Node, weapon: Node) -> void:
	for frame in 24:
		# Match runtime order: reset display depth, update weapon pose, then project.
		player._restore_viewmodel_depth()
		weapon._process(1.0 / 60.0)
		player._process(1.0 / 60.0)


func _check_smg_grip(weapon: Node, label: String) -> void:
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var hand: int = weapon._find_bone_by_prefix("Hand_R")
	var fore: int = weapon._find_bone_by_prefix("Forearm_R")
	_assert(hand >= 0 and fore >= 0, label + " has its native right hand and forearm")
	if hand < 0 or fore < 0:
		return
	var to_weapon: Transform3D = weapon._weapon_node.global_transform.affine_inverse() * skeleton.global_transform
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var palm: Vector3 = weapon._weapon_node.to_local(HandSkin.palm_world(weapon._arms_node, skeleton, "R"))
	# First ray hit on the native SMG's right trigger-grip surface.
	var contact := Vector3(0.0215154, -0.065, 0.13)
	_assert(palm.distance_to(contact) < 0.008, label + " right palm contacts the trigger grip within 8mm")
	var fore_pose := skeleton.get_bone_global_pose(fore)
	_assert(absf(fore_pose.origin.distance_to(hand_pose.origin) - _source_fore_length) < 0.001, label + " retains the original black-arm forearm length and wrist seam")
	var finger_direction := (palm - to_weapon * hand_pose.origin).normalized()
	_assert(finger_direction.dot(Vector3.FORWARD) > 0.85, label + " keeps the native gripping finger orientation")


func _run() -> void:
	var source = (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate()
	root.add_child(source)
	await process_frame
	var source_animation := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	source_animation.play(&"idle")
	source_animation.seek(0.0, true)
	source_animation.pause()
	var source_skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_source_fore_length = source_skeleton.get_bone_global_pose(source_skeleton.find_bone("R_elbow_027")).origin.distance_to(source_skeleton.get_bone_global_pose(source_skeleton.find_bone("R_wrist_028")).origin)
	source.queue_free()
	await process_frame
	root.size = Vector2i(1600, 900)
	var state = root.get_node("GameState")
	state.reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	# Direct pose tests must not receive native capture-warp mouse movement.
	player.set_process_unhandled_input(false)
	await process_frame
	var hud = scene.get_node("HUD")
	var ammo = hud._weapon_ammo
	for category: Dictionary in root.get_node("GameConfig").WEAPON_CATEGORIES:
		for id: StringName in category.weapons:
			player._switch_weapon(id)
			_assert(ammo.weapon_id == id and ammo.get("weapon_name") == hud._weapon_display_name(id), "%s switch shows its canonical weapon number and name above the icon" % id)
	for refresh in 20:
		hud._set_ammo_text(&"smg", 100, 3000)
	_assert(ammo.get_child_count() == 1 and ammo.get("weapon_name") == "EM-57S-1 雹·Ⅰ", "repeated ammo refreshes keep the SMG name and reuse one icon")
	player._switch_weapon(&"shotgun")
	player._set_aiming(false)
	var shotgun = player.get_node("Camera3D/WeaponMount/Shotgun")
	_settle(player, shotgun)
	var hip_mount: Transform3D = player._weapon_mount.transform
	var hip_camera: Transform3D = player._camera.transform
	var hip_weapon: Transform3D = shotgun._weapon_node.transform
	player._set_aiming(true)
	_settle(player, shotgun)
	var marker := shotgun.get_node("ViewModel/Weapon/OpticAim") as Marker3D
	var marker_local: Vector3 = player._camera.global_transform.affine_inverse() * marker.global_position
	_assert(absf(marker_local.x - 0.003) < 0.0005 and absf(marker_local.y) < 0.001, "EM-12G-1 shifts its ADS weapon right by 3mm without changing vertical alignment")
	# Native opening axis from open_generated_optic.py; the old marker is 2.55mm to its right.
	var bore := Vector3(0.00125, marker.position.y, marker.position.z)
	var bore_pixel: Vector2 = player._camera.unproject_position(shotgun._weapon_node.global_transform * bore)
	_assert(absf(bore_pixel.x - root.size.x * 0.5) < 2.0, "EM-12G-1 physical sight opening stays within 2px of the screen center")
	player._set_aiming(false)
	_settle(player, shotgun)
	_assert(player._weapon_mount.transform.is_equal_approx(hip_mount) and player._camera.transform.is_equal_approx(hip_camera) and shotgun._weapon_node.transform.is_equal_approx(hip_weapon), "EM-12G-1 restores its original hip weapon, camera and mount")
	player._switch_weapon(&"smg")
	var smg = player.get_node("Camera3D/WeaponMount/SMG")
	_settle(player, smg)
	_check_smg_grip(smg, "EM-57S1 hip")
	player._set_aiming(true)
	_settle(player, smg)
	player._set_aiming(false)
	_settle(player, smg)
	_check_smg_grip(smg, "EM-57S1 after ADS")
	state.smg_mag = 0
	smg._start_reload()
	await create_timer(smg.weapon_data.reload_time + 0.1).timeout
	_assert(ammo.get("weapon_name") == "EM-57S-1 雹·Ⅰ" and ammo.mag == 100 and ammo.reserve == 2900, "real SMG reload refreshes ammunition while retaining its weapon identity")
	_settle(player, smg)
	_check_smg_grip(smg, "EM-57S1 after reload")
	for pair: Array in [[&"rifle", "Rifle"], [&"lmg", "LMG"]]:
		player._switch_weapon(pair[0])
		var weapon = player.get_node("Camera3D/WeaponMount/" + pair[1])
		_settle(player, weapon)
		var skeleton: Skeleton3D = weapon._arms_skeleton
		var palm: Vector3 = weapon._weapon_node.to_local(HandSkin.palm_world(weapon._arms_node, skeleton, "R"))
		var grip: Vector3 = root.get_node("GameConfig").BLACK_LONG_GUN_PROFILES[pair[0]].right_grip
		_assert(palm.distance_to(grip) < 0.003, "%s native black palm contacts its measured trigger grip" % pair[0])
	scene.queue_free()
	await process_frame
	print("WEAPON_PRESENTATION failures=", _failures)
	quit(1 if _failures else 0)
