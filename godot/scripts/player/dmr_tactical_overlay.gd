extends Control

var camera: Camera3D = null
var excluded_rids: Array[RID] = []
var _range_distance := INF
var _range_text := "RNG --- M"
var _targets: Array[Dictionary] = []
var _primary_target: Node3D = null
var _target_age: Dictionary = {}
var _refresh_left := 0.0


func _process(delta: float) -> void:
	if not visible or camera == null:
		return
	for target in _target_age:
		if is_instance_valid(target):
			_target_age[target] += delta
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_range()
		_refresh_targets()
		_refresh_left = GameConfig.DMR_SCOPE_REFRESH_INTERVAL
	queue_redraw()


func _refresh_range() -> void:
	if camera == null:
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * GameConfig.DMR_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = excluded_rids
	query.collide_with_areas = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_range_distance = INF
		_range_text = "RNG >%d M" % int(GameConfig.DMR_RANGE)
		return
	_range_distance = from.distance_to(hit.position)
	_range_text = "RNG %.1f M" % _range_distance


func _refresh_targets() -> void:
	_targets.clear()
	_primary_target = null
	if camera == null:
		return
	var candidates: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var target := node as Node3D
		if target == null or target.is_queued_for_deletion():
			continue
		var health: Variant = target.get("health")
		if health != null and float(health) <= 0.0:
			continue
		var collision := _target_collision(target)
		if collision == null:
			continue
		var center := collision.global_position
		if camera.is_position_behind(center) or camera.global_position.distance_to(center) > GameConfig.DMR_RANGE:
			continue
		var screen_center := camera.unproject_position(center)
		if screen_center.distance_to(size * 0.5) > _scope_radius():
			continue
		if not _target_visible(target, center):
			continue
		var rect := _projected_bounds(collision)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		candidates.append({"target": target, "rect": rect, "offset": rect.get_center().distance_to(size * 0.5)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.offset < b.offset)
	var current: Dictionary = {}
	for i in mini(candidates.size(), GameConfig.DMR_SCOPE_MAX_TARGETS):
		var candidate: Dictionary = candidates[i]
		var target := candidate.target as Node3D
		current[target] = true
		if not _target_age.has(target):
			_target_age[target] = 0.0
		_targets.append({"target": target, "rect": candidate.rect})
	for target in _target_age.keys():
		if not current.has(target):
			_target_age.erase(target)
	if not _targets.is_empty():
		_primary_target = _targets[0].target as Node3D


func _target_collision(target: Node3D) -> CollisionShape3D:
	var shapes := target.find_children("*", "CollisionShape3D", true, false)
	for shape in shapes:
		if shape is CollisionShape3D and shape.shape != null:
			return shape as CollisionShape3D
	return null


func _target_visible(target: Node3D, center: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, center)
	query.exclude = excluded_rids
	query.collide_with_areas = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var node := hit.collider as Node
	while node != null:
		if node == target:
			return true
		node = node.get_parent()
	return false


func _projected_bounds(collision: CollisionShape3D) -> Rect2:
	var extents := Vector3.ZERO
	if collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		extents = Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
	elif collision.shape is BoxShape3D:
		extents = (collision.shape as BoxShape3D).size * 0.5
	else:
		return Rect2()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				var point := collision.global_transform * Vector3(extents.x * x, extents.y * y, extents.z * z)
				if camera.is_position_behind(point):
					return Rect2()
				var projected := camera.unproject_position(point)
				minimum = minimum.min(projected)
				maximum = maximum.max(projected)
	return Rect2(minimum, maximum - minimum).grow(4.0)


func _scope_radius() -> float:
	return size.y * 0.43


func _mil_to_pixels(mil: float) -> float:
	if camera == null:
		return 0.0
	var pixels_per_radian := size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	return pixels_per_radian * mil * 0.001


func _draw() -> void:
	if camera == null:
		return
	var font := get_theme_default_font()
	var center := size * 0.5
	for entry in _targets:
		var target := entry.target as Node3D
		var primary := target == _primary_target
		var alpha := clampf(float(_target_age.get(target, 0.0)) / GameConfig.DMR_SCOPE_ACQUIRE_TIME, 0.0, 1.0)
		var color := Color(0.25, 0.82, 1.0, alpha * 0.95)
		_draw_target_frame(entry.rect as Rect2, color, primary)
		if primary:
			draw_string(font, entry.rect.position + Vector2(0, -7), "TRACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	var tick_color := Color(0.4, 0.95, 1.0, 0.85)
	for mil in GameConfig.DMR_SCOPE_MIL_STEPS:
		var offset := _mil_to_pixels(float(mil))
		var down := center + Vector2(0, offset)
		draw_line(down - Vector2(4, 0), down + Vector2(4, 0), tick_color, 1.2, true)
		draw_string(font, down + Vector2(9, 4), str(mil), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tick_color)
		for sign_value in [-1.0, 1.0]:
			var side := center + Vector2(offset * sign_value, 0)
			draw_line(side - Vector2(0, 4), side + Vector2(0, 4), tick_color, 1.2, true)
			draw_string(font, side + Vector2(-4, -8), str(mil), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tick_color)
	draw_string(font, center + Vector2(-12, _scope_radius() * 0.43), "MIL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tick_color)
	draw_string(font, center + Vector2(_scope_radius() * 0.38, _scope_radius() * 0.72), _range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, tick_color)


func _draw_target_frame(rect: Rect2, color: Color, primary: bool) -> void:
	var bracket := clampf(minf(rect.size.x, rect.size.y) * 0.25, 4.0, 15.0)
	var width := 2.0 if primary else 1.2
	var right := rect.end.x
	var bottom := rect.end.y
	for segment in [
		[rect.position, rect.position + Vector2(bracket, 0)],
		[rect.position, rect.position + Vector2(0, bracket)],
		[Vector2(right, rect.position.y), Vector2(right - bracket, rect.position.y)],
		[Vector2(right, rect.position.y), Vector2(right, rect.position.y + bracket)],
		[Vector2(rect.position.x, bottom), Vector2(rect.position.x + bracket, bottom)],
		[Vector2(rect.position.x, bottom), Vector2(rect.position.x, bottom - bracket)],
		[rect.end, rect.end - Vector2(bracket, 0)],
		[rect.end, rect.end - Vector2(0, bracket)],
	]:
		draw_line(segment[0], segment[1], color, width, true)
