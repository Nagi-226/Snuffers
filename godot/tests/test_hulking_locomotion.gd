## Production hulking host: joint trajectories, anatomical facing and impact timing.
extends SceneTree

const SAMPLE_COUNT := 64
const CHAINS := [["hips", "thigh_l", "shin_l", "foot_l"], ["hips", "thigh_r", "shin_r", "foot_r"], ["chest", "upper_arm_l", "forearm_l", "hand_l"], ["chest", "upper_arm_r", "forearm_r", "hand_r"]]

var _assertions := 0
var _failures := 0
var _world: Node3D
var _host
var _target: CharacterBody3D
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _state
var _config
var _hits := 0
var _smashes := 0
var _impact_clip_time := -1.0
var _impact_hand_y := INF
var _peak_hand_y := -INF
var _skin_meshes: Array[Dictionary] = []
var _skin_regions := {"left": [], "right": [], "claw": [], "pelvis": [], "chest": [], "head": []}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("hulking locomotion timed out")
		quit(1))
	_state = root.get_node("GameState")
	_config = root.get_node("GameConfig")
	_state.reset()
	_world = Node3D.new()
	root.add_child(_world)
	_target = CharacterBody3D.new()
	_target.add_to_group(&"player")
	_world.add_child(_target)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100, 0.2, 100)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	_world.add_child(floor_body)
	_host = (load("res://scenes/enemies/hulking_host.tscn") as PackedScene).instantiate()
	_world.add_child(_host)
	_host.set_physics_process(false)
	var skeletons: Array[Node] = _host.get_node("BodyMesh").find_children("*", "Skeleton3D", true, false)
	_assert(skeletons.size() == 1 and _host._animation_player != null, "production enemy has one bound skeleton and an animation player")
	if skeletons.size() != 1 or _host._animation_player == null:
		_finish()
		return
	_skeleton = skeletons[0] as Skeleton3D
	_animation = _host._animation_player
	await physics_frame
	await process_frame
	_check_chains()
	await _collect_skin()
	await _check_walk()
	await _check_skin_walk()
	await _check_facing()
	await _check_attack()
	await _check_skin_attack()
	await _check_skin_envelope()
	await _check_skin_death()
	await _check_live_impact()
	_check_death()
	_world.queue_free()
	await process_frame
	await process_frame
	_finish()


func _check_chains() -> void:
	for chain in CHAINS:
		for i in range(1, chain.size()):
			var parent_bone := _skeleton.find_bone(chain[i - 1])
			var child_bone := _skeleton.find_bone(chain[i])
			_assert(parent_bone >= 0 and child_bone >= 0, "real joint exists: %s -> %s" % [chain[i - 1], chain[i]])
			if parent_bone < 0 or child_bone < 0:
				continue
			var ancestor := _skeleton.get_bone_parent(child_bone)
			while ancestor >= 0 and ancestor != parent_bone:
				ancestor = _skeleton.get_bone_parent(ancestor)
			_assert(ancestor == parent_bone, "%s follows its %s joint rather than rotating independently" % [chain[i], chain[i - 1]])
	var head := _skeleton.find_bone("head")
	if head >= 0:
		var height := 0.0
		for child in _host.get_node("BodyMesh").find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh.mesh != null:
				height = maxf(height, (mesh.global_basis * Vector3(0, mesh.mesh.get_aabb().size.y, 0)).length())
		var head_height: float = (_skeleton.global_transform * _skeleton.get_bone_global_rest(head).origin).y - _host.global_position.y
		_assert(height > 1.5 and head_height > height * 0.55, "head joint reaches the upper portion of the actual tall mesh")


func _check_walk() -> void:
	_assert(_animation.has_animation(&"walk"), "production locomotion exposes its real walk clip")
	if not _animation.has_animation(&"walk"):
		return
	var duration := _animation.get_animation(&"walk").length
	_assert(duration > 0.2, "walk has a measurable full stride")
	var samples: Array[Dictionary] = []
	for step in SAMPLE_COUNT + 1:
		var time := duration * float(step) / SAMPLE_COUNT
		await _pose(&"walk", time)
		samples.append({"time": time, "left": _joint_in_host("foot_l"), "right": _joint_in_host("foot_r")})
	for side in ["left", "right"]:
		var forward_min := INF
		var forward_max := -INF
		var lateral_min := INF
		var lateral_max := -INF
		var low := INF
		var high := -INF
		for sample in samples:
			var point: Vector3 = sample[side]
			forward_min = minf(forward_min, -point.z)
			forward_max = maxf(forward_max, -point.z)
			lateral_min = minf(lateral_min, point.x)
			lateral_max = maxf(lateral_max, point.x)
			low = minf(low, point.y)
			high = maxf(high, point.y)
		var stride := forward_max - forward_min
		var slip := 0.0
		var stance_seconds := 0.0
		for i in range(samples.size() - 1):
			var first: Vector3 = samples[i][side]
			var second: Vector3 = samples[i + 1][side]
			if maxf(first.y, second.y) <= low + 0.025:
				var dt: float = samples[i + 1].time - samples[i].time
				slip += absf(-(second.z - first.z) + _config.HULKING_HOST_SPEED * dt)
				stance_seconds += dt
		var ground_speed := slip / maxf(stance_seconds, 0.001)
		print("HULKING_WALK side=", side, " stride=", stride, " lift=", high - low, " lateral=", lateral_max - lateral_min, " stance_seconds=", stance_seconds, " ground_slip_speed=", ground_speed)
		_assert(stride >= 0.25, "%s ankle advances and retracts by at least 25cm along locomotion" % side)
		_assert(high - low >= 0.06, "%s ankle visibly lifts at least 6cm before returning to stance" % side)
		_assert(lateral_max - lateral_min <= stride * 0.4 + 0.1, "%s step travels mainly forwards instead of sideways" % side)
		_assert(stance_seconds >= duration * 0.12 and ground_speed <= 0.45, "%s stance counteracts actual 1.8m/s translation instead of skating" % side)
	var left_lifted := false
	var right_lifted := false
	var left_low := INF
	var right_low := INF
	for sample in samples:
		left_low = minf(left_low, (sample.left as Vector3).y)
		right_low = minf(right_low, (sample.right as Vector3).y)
	for sample in samples:
		var left_height: float = (sample.left as Vector3).y - left_low
		var right_height: float = (sample.right as Vector3).y - right_low
		left_lifted = left_lifted or (left_height > 0.04 and right_height < 0.025)
		right_lifted = right_lifted or (right_height > 0.04 and left_height < 0.025)
	_assert(left_lifted and right_lifted, "left and right legs take separate swing and stance phases")
	var first_left: Vector3 = samples[0].left
	var last_left: Vector3 = samples[-1].left
	var first_right: Vector3 = samples[0].right
	var last_right: Vector3 = samples[-1].right
	_assert(first_left.distance_to(last_left) < 0.025 and first_right.distance_to(last_right) < 0.025, "stride closes without a foot teleport at the loop seam")


func _check_facing() -> void:
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		_host.global_position = Vector3(0, 0.02, 0)
		_target.global_position = direction * 10.0
		_state.player_position = _target.global_position
		_host.current_state = _host.State.ADVANCE
		await physics_frame
		_host._physics_process(1.0 / 60.0)
		var actual_velocity := Vector3(_host.velocity.x, 0, _host.velocity.z)
		_assert(actual_velocity.normalized().dot(direction) > 0.99, "physical pursuit follows target direction %s" % direction)
		for name in ["foot_l", "foot_r"]:
			var bone := _skeleton.find_bone(name)
			if bone < 0:
				continue
			# A foot bone points from its ankle toward the toe along local +Y.
			var toe_axis: Vector3 = _skeleton.global_basis * _skeleton.get_bone_global_rest(bone).basis.y
			toe_axis.y = 0.0
			print("HULKING_FACING direction=", direction, " side=", name, " toe_axis=", toe_axis.normalized())
			_assert(toe_axis.normalized().dot(direction) > 0.85, "%s anatomical forward faces the real pursuit direction %s" % [name, direction])
	_host.global_position = Vector3.ZERO
	_host.rotation = Vector3.ZERO
	_state.player_position = Vector3.ZERO


func _check_attack() -> void:
	_assert(_animation.has_animation(&"attack"), "production right-arm attack clip exists")
	if not _animation.has_animation(&"attack"):
		return
	var duration := _animation.get_animation(&"attack").length
	var start_hand := Vector3.ZERO
	var impact_hand := Vector3.ZERO
	var peak_time := 0.0
	var fastest_down := 0.0
	var fastest_time := 0.0
	var prior_hand := Vector3.ZERO
	var prior_time := 0.0
	for step in 49:
		var time: float = _config.HULKING_HOST_WINDUP * 1.25 * float(step) / 48.0
		await _pose(&"attack", minf(time, duration))
		var hand := _joint_in_host("hand_r")
		if step == 0:
			start_hand = hand
		if hand.y > _peak_hand_y:
			_peak_hand_y = hand.y
			peak_time = time
		if step > 0:
			var speed := (prior_hand.y - hand.y) / (time - prior_time)
			if speed > fastest_down:
				fastest_down = speed
				fastest_time = (time + prior_time) * 0.5
		prior_hand = hand
		prior_time = time
	await _pose(&"attack", _config.HULKING_HOST_WINDUP)
	impact_hand = _joint_in_host("hand_r")
	print("HULKING_ATTACK start=", start_hand, " peak_y=", _peak_hand_y, " peak_time=", peak_time, " impact=", impact_hand, " fastest_down=", fastest_down, " fastest_time=", fastest_time)
	_assert(_peak_hand_y - start_hand.y >= 0.35, "right hand rises visibly at least 35cm in anticipation")
	_assert(peak_time < _config.HULKING_HOST_WINDUP and _peak_hand_y - impact_hand.y >= 0.35, "right hand descends at least 35cm into the actual damage window")
	_assert(fastest_down > 1.0 and absf(fastest_time - _config.HULKING_HOST_WINDUP) < 0.2, "downward strike is fast and occurs around the existing impact time")
	await _pose(&"attack", minf(duration, _config.HULKING_HOST_WINDUP + _config.HULKING_HOST_RECOVER))
	_assert(_joint_in_host("hand_r").distance_to(start_hand) <= 0.2, "hand recovers near its initial pose before locomotion resumes")


func _check_live_impact() -> void:
	_host.global_position = Vector3(0, 0.02, -2.5)
	_host.rotation = Vector3.ZERO
	_target.global_position = Vector3.ZERO
	_state.player_position = Vector3.ZERO
	_host.current_state = _host.State.ADVANCE
	_host._attack_cooldown = 0.0
	_host._state_timer = 0.0
	root.get_node("Events").player_damaged.connect(_on_damage)
	root.get_node("Events").enemy_fired.connect(_on_fired)
	_host.set_physics_process(true)
	await create_timer(_config.HULKING_HOST_WINDUP * 0.7).timeout
	_assert(_hits == 0 and _smashes == 0, "actual pursuit enters anticipation without early damage or sound")
	await create_timer(_config.HULKING_HOST_WINDUP * 0.3 + 0.12).timeout
	_assert(_hits == 1 and _smashes == 1, "actual smash emits exactly one damage and impact sound")
	_assert(absf(_impact_clip_time - _config.HULKING_HOST_WINDUP) < 0.08, "actual impact event agrees with animation time rather than a restarted or stopped clip")
	_assert(_peak_hand_y - _impact_hand_y > 0.25, "actual impact frame has the hand down from its anticipation apex")
	await create_timer(_config.HULKING_HOST_RECOVER + 0.03).timeout
	_assert(_hits == 1 and _smashes == 1, "recovery does not duplicate a single strike")
	_host.set_physics_process(false)
	root.get_node("Events").player_damaged.disconnect(_on_damage)
	root.get_node("Events").enemy_fired.disconnect(_on_fired)


func _check_death() -> void:
	_host.take_damage(_config.HULKING_HOST_HP + 1.0)
	_assert(_host._dead and not _host.is_in_group(&"enemy"), "death removes the hostile actor immediately")
	_assert(_host.collision_layer == 0 and _host.collision_mask == 0, "death disables collision while retaining animation")
	_assert(_animation.current_animation == &"death", "death still plays its production clip")
	_animation.animation_finished.emit(&"death")
	_assert(_host.is_queued_for_deletion(), "death completion cleans up the actor")


func _pose(clip: StringName, time: float) -> void:
	_animation.play(clip, 0.0)
	_animation.advance(0.0)
	_animation.seek(time, true)
	_animation.pause()
	await process_frame


func _joint_in_host(name: String) -> Vector3:
	var bone := _skeleton.find_bone(name)
	if bone < 0:
		return Vector3.ZERO
	return _host.global_transform.affine_inverse() * (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin)


func _collect_skin() -> void:
	await _pose(&"idle", 0.0)
	var body := _host.get_node("BodyMesh") as Node3D
	var anatomy_frame: Transform3D = body.global_transform.affine_inverse() * _host.global_transform
	var valid := true
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.skin == null:
			continue
		var skin := instance.skin
		var bind_bones: Array[int] = []
		for bind in skin.get_bind_count():
			var name := skin.get_bind_name(bind)
			var bone := _skeleton.find_bone(name) if name != &"" else skin.get_bind_bone(bind)
			valid = valid and bone >= 0 and bone < _skeleton.get_bone_count()
			bind_bones.append(bone)
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var shape_valid := not vertices.is_empty() and joints.size() == weights.size() and joints.size() % vertices.size() == 0 and not indices.is_empty()
			valid = valid and shape_valid
			if not shape_valid:
				continue
			var entry := {"skin": skin, "bind_bones": bind_bones, "vertices": vertices, "joints": joints, "weights": weights, "indices": indices, "width": joints.size() / vertices.size()}
			var frames := _skin_frames(entry)
			var rest_points := PackedVector3Array()
			var mesh_index := _skin_meshes.size()
			for vertex in vertices.size():
				var weight_sum := 0.0
				for influence in int(entry.width):
					var offset: int = vertex * int(entry.width) + influence
					valid = valid and joints[offset] >= 0 and joints[offset] < skin.get_bind_count() and is_finite(weights[offset]) and weights[offset] >= 0.0
					weight_sum += weights[offset]
				valid = valid and absf(weight_sum - 1.0) < 0.001
				var point := _skin_point(entry, vertex, frames)
				rest_points.append(point)
				var anatomical: Vector3 = anatomy_frame * point
				var sample := {"mesh": mesh_index, "vertex": vertex}
				# Select the actual low feet and projecting giant claw by geometry,
				# independently of repaired bone names, weight assignment or reports.
				if anatomical.y < 0.25 and anatomical.x < -0.10:
					_skin_regions.left.append(sample)
				if anatomical.y < 0.25 and anatomical.x > 0.10 and anatomical.z > -0.55:
					_skin_regions.right.append(sample)
				if anatomical.y < 0.55 and anatomical.x > 0.05 and anatomical.z < -0.65:
					_skin_regions.claw.append(sample)
				# Central trunk and head regions exclude the elongated right arm.
				# Selecting in the rest mesh keeps corpse checks independent of
				# whatever bones or weights the death implementation assigns.
				if anatomical.y >= 0.85 and anatomical.y <= 1.12 and absf(anatomical.x + 0.04) < 0.24 and anatomical.z > -0.10 and anatomical.z < 0.80:
					_skin_regions.pelvis.append(sample)
				if anatomical.y >= 1.35 and anatomical.y <= 1.75 and absf(anatomical.x + 0.04) < 0.26 and anatomical.z > -0.15 and anatomical.z < 0.80:
					_skin_regions.chest.append(sample)
				if anatomical.y >= 1.90 and anatomical.x < 0.06 and anatomical.x > -0.42 and anatomical.z < 0.10:
					_skin_regions.head.append(sample)
			entry.rest_points = rest_points
			_skin_meshes.append(entry)
	_assert(valid and not _skin_meshes.is_empty(), "actual production meshes expose valid normalized vertex skin weights and inverse bindings")
	for region: String in _skin_regions:
		print("HULKING_SKIN_REGION ", region, " vertices=", _skin_regions[region].size())
		_assert(_skin_regions[region].size() >= 50, "%s anatomy contains at least 50 actual mesh vertices" % region)


func _skin_frames(entry: Dictionary) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var skin: Skin = entry.skin
	var frame: Transform3D = _host.global_transform.affine_inverse() * _skeleton.global_transform
	for bind in skin.get_bind_count():
		var bone: int = entry.bind_bones[bind]
		result.append(frame * _skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	return result


func _skin_point(entry: Dictionary, vertex: int, frames: Array[Transform3D]) -> Vector3:
	var result := Vector3.ZERO
	var width: int = entry.width
	var point: Vector3 = entry.vertices[vertex]
	for influence in width:
		var offset := vertex * width + influence
		var weight: float = entry.weights[offset]
		if weight > 0.0:
			result += (frames[entry.joints[offset]] * point) * weight
	return result


func _skin_centroid(region: String) -> Vector3:
	var all_frames: Array = []
	for entry in _skin_meshes:
		all_frames.append(_skin_frames(entry))
	var result := Vector3.ZERO
	for sample: Dictionary in _skin_regions[region]:
		result += _skin_point(_skin_meshes[sample.mesh], sample.vertex, all_frames[sample.mesh])
	return result / maxf(float(_skin_regions[region].size()), 1.0)


func _check_skin_walk() -> void:
	var duration := _animation.get_animation(&"walk").length
	var samples: Array[Dictionary] = []
	for step in 33:
		await _pose(&"walk", duration * float(step) / 32.0)
		samples.append({"left": _skin_centroid("left"), "right": _skin_centroid("right")})
	for side: String in ["left", "right"]:
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for sample in samples:
			var point: Vector3 = sample[side]
			low = low.min(point)
			high = high.max(point)
		var extent := high - low
		print("HULKING_SKIN_WALK ", side, " stride=", extent.z, " lift=", extent.y, " lateral=", extent.x)
		_assert(extent.z >= 0.25 and extent.x <= extent.z * 0.4 + 0.10, "%s actual foot mesh advances at least 25cm mainly forwards" % side)
		_assert(extent.y >= 0.06, "%s actual foot mesh lifts at least 6cm" % side)
		_assert((samples[0][side] as Vector3).distance_to(samples[-1][side]) <= 0.025, "%s actual foot mesh closes the loop without teleporting" % side)
	var left_low := INF
	var right_low := INF
	for sample in samples:
		left_low = minf(left_low, (sample.left as Vector3).y)
		right_low = minf(right_low, (sample.right as Vector3).y)
	var left_swing := false
	var right_swing := false
	for sample in samples:
		var left_height: float = (sample.left as Vector3).y - left_low
		var right_height: float = (sample.right as Vector3).y - right_low
		left_swing = left_swing or (left_height >= 0.04 and right_height <= 0.025)
		right_swing = right_swing or (right_height >= 0.04 and left_height <= 0.025)
	_assert(left_swing and right_swing, "actual left and right foot meshes alternate swing and planted phases")


func _check_skin_attack() -> void:
	await _pose(&"attack", 0.0)
	var start := _skin_centroid("claw")
	var peak := start.y
	for step in 33:
		await _pose(&"attack", _config.HULKING_HOST_WINDUP * float(step) / 32.0)
		peak = maxf(peak, _skin_centroid("claw").y)
	await _pose(&"attack", _config.HULKING_HOST_WINDUP)
	var impact := _skin_centroid("claw")
	await _pose(&"attack", _config.HULKING_HOST_WINDUP + _config.HULKING_HOST_RECOVER)
	var recovered := _skin_centroid("claw")
	print("HULKING_SKIN_ATTACK start=", start, " peak=", peak, " impact=", impact, " recovered=", recovered)
	_assert(peak - start.y >= 0.35 and peak - impact.y >= 0.35, "actual giant claw mesh rises and drops at least 35cm into the damage window")
	_assert(start.distance_to(recovered) <= 0.20, "actual giant claw mesh returns near its initial position after recovery")


func _check_skin_envelope() -> void:
	var finite := true
	var worst_stretch := 1.0
	for clip: StringName in [&"idle", &"walk", &"attack", &"death"]:
		var minimum_y := INF
		var duration := _animation.get_animation(clip).length
		for step in 9:
			await _pose(clip, duration * float(step) / 8.0)
			for entry in _skin_meshes:
				var frames := _skin_frames(entry)
				var points := PackedVector3Array()
				for vertex in entry.vertices.size():
					var point := _skin_point(entry, vertex, frames)
					finite = finite and point.is_finite() and point.length() < 5.0
					minimum_y = minf(minimum_y, point.y)
					points.append(point)
				var indices: PackedInt32Array = entry.indices
				var rests: PackedVector3Array = entry.rest_points
				for triangle in range(0, indices.size(), 3):
					for edge in 3:
						var a := indices[triangle + edge]
						var b := indices[triangle + (edge + 1) % 3]
						var rest_length := rests[a].distance_to(rests[b])
						# Ignore numerical seam slivers but retain short visible edges.
						if rest_length >= 0.003:
							worst_stretch = maxf(worst_stretch, points[a].distance_to(points[b]) / rest_length)
		print("HULKING_SKIN_ENVELOPE clip=", clip, " minimum_y=", minimum_y)
		_assert(minimum_y >= (-0.08 if clip == &"death" else -0.035), "%s actual full mesh stays above the floor within contact tolerance" % clip)
	print("HULKING_SKIN_STABILITY max_edge_stretch=", worst_stretch)
	_assert(finite, "all sampled skin vertices remain finite and within a five-metre actor envelope")
	_assert(worst_stretch <= 4.0, "actual connected skin edges do not stretch beyond four times their resting length")


func _check_skin_death() -> void:
	await _pose(&"death", 0.0)
	var start_chest := _skin_centroid("chest")
	var start_head := _skin_centroid("head")
	var duration := _animation.get_animation(&"death").length
	for fraction: float in [0.90, 0.995]:
		await _pose(&"death", duration * fraction)
		var pelvis := _skin_centroid("pelvis")
		var chest := _skin_centroid("chest")
		var head := _skin_centroid("head")
		var torso_low := INF
		for mesh_index in _skin_meshes.size():
			var entry: Dictionary = _skin_meshes[mesh_index]
			var frames := _skin_frames(entry)
			for region: String in ["pelvis", "chest"]:
				for sample: Dictionary in _skin_regions[region]:
					if sample.mesh == mesh_index:
						torso_low = minf(torso_low, _skin_point(entry, sample.vertex, frames).y)
		print("HULKING_SKIN_DEATH fraction=", fraction, " pelvis=", pelvis, " chest=", chest, " head=", head, " torso_low=", torso_low)
		_assert(pelvis.y <= 0.60 and chest.y <= 0.60 and head.y <= 0.65, "death %.3f keeps actual hip/chest/head mass near the ground instead of perched on the long claw" % fraction)
		_assert(torso_low <= 0.18, "death %.3f brings the actual torso surface within 18cm of the floor" % fraction)
		_assert(start_chest.y - chest.y >= 0.65 and start_head.y - head.y >= 0.75, "death %.3f lowers the actual chest and head substantially from the living pose" % fraction)
		var trunk_axis := chest - pelvis
		_assert(trunk_axis.length() > 0.20 and absf(trunk_axis.normalized().y) <= 0.40, "death %.3f leaves the actual trunk lying predominantly horizontally" % fraction)


func _on_damage(_part: StringName, _amount: float) -> void:
	_hits += 1


func _on_fired(kind: StringName, _position: Vector3) -> void:
	if kind == &"hulking_smash":
		_smashes += 1
		_impact_clip_time = _animation.current_animation_position
		_impact_hand_y = _joint_in_host("hand_r").y


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("HULKING_LOCOMOTION assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)
