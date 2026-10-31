extends Control

var _texture: Texture2D = null
var _calib_min := Vector2.ZERO
var _calib_max := Vector2.ONE
var _enemies: Array[Dictionary] = []
var _pickups: Array[Dictionary] = []
var _objectives: Array[Dictionary] = []
var _refresh_left := 0.0


func _ready() -> void:
	_texture = load(GameConfig.DISTRICT_MINIMAP_MAP_TEXTURE) as Texture2D
	var file := FileAccess.open(GameConfig.DISTRICT_MINIMAP_MAP_CALIB, FileAccess.READ)
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			_calib_min = Vector2(data.min_x, data.min_z)
			_calib_max = Vector2(data.max_x, data.max_z)
		file.close()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_on_size_changed()
	get_viewport().size_changed.connect(_on_size_changed)
	_refresh_markers()


func _on_size_changed() -> void:
	set_deferred("size", get_viewport().get_visible_rect().size)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_markers()
		_refresh_left = 0.1
	queue_redraw()


func _refresh_markers() -> void:
	_enemies.clear()
	_pickups.clear()
	for node in get_tree().get_nodes_in_group(&"enemy"):
		if node is Node3D and node.visible and not node.is_queued_for_deletion():
			_enemies.append({"node": node, "position": node.global_position, "kind": node.get("enemy_kind")})
	for node in get_tree().get_nodes_in_group(&"pickup"):
		if node is Node3D and not node.is_queued_for_deletion():
			_pickups.append({"node": node, "position": node.global_position, "kind": node.get("kind")})
	_refresh_objectives()


func _refresh_objectives() -> void:
	_objectives.clear()
	var scene := _scene_root()
	if not GameState.weapon_unlocked.get(&"dmr", false):
		_add_objective(scene, &"Equipment_dmr", "EM-68D")
	if not GameState.weapon_unlocked.get(&"shotgun", false):
		_add_objective(scene, &"Equipment_shotgun", "EM-12G-1")
	if _objectives.is_empty():
		_add_objective(scene, &"Link_DistrictBReturn", "返回主街")


func _add_objective(scene: Node, node_name: StringName, label: String) -> void:
	var node := scene.get_node_or_null(NodePath(String(node_name))) as Node3D
	if node != null and not node.is_queued_for_deletion():
		_objectives.append({"node": node, "position": node.global_position, "label": label})


func _scene_root() -> Node:
	var node := get_parent()
	while node != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node


func _map_rect() -> Rect2:
	var side := minf(size.x * 0.82, size.y * 0.86)
	return Rect2((size - Vector2(side, side)) * 0.5 + Vector2(0, 16), Vector2(side, side))


func world_to_map(world: Vector3) -> Vector2:
	var rect := _map_rect()
	var uv := Vector2(
		(world.x - _calib_min.x) / (_calib_max.x - _calib_min.x),
		(world.z - _calib_min.y) / (_calib_max.y - _calib_min.y))
	return rect.position + uv * rect.size


func _draw() -> void:
	if _texture == null:
		return
	var font := get_theme_default_font()
	var rect := _map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.012, 0.02, 0.96))
	draw_texture_rect(_texture, rect, false)
	draw_rect(rect, Color(0.35, 0.8, 0.95, 0.8), false, 2.0)
	draw_string(font, rect.position + Vector2(0, -12), "区域战术图 // EDAA 转运仓库", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.55, 0.88, 1.0))
	draw_string(font, rect.position + Vector2(rect.size.x - 90, -12), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.95, 0.65))
	for enemy in _enemies:
		var point := world_to_map(enemy.position)
		if not rect.has_point(point):
			continue
		var hulking: bool = enemy.kind == &"hulking_host"
		draw_circle(point, 4.0 if hulking else 2.5, Color(1.0, 0.35, 0.18) if hulking else Color(1.0, 0.22, 0.18))
	for pickup in _pickups:
		var point := world_to_map(pickup.position)
		if rect.has_point(point):
			draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), Color(0.35, 0.95, 0.55))
	for objective in _objectives:
		var point := world_to_map(objective.position)
		if rect.has_point(point):
			var color := Color(1.0, 0.82, 0.25)
			_draw_diamond(point, 7.0, color)
			draw_string(font, point + Vector2(10, 5), objective.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	var player_point := world_to_map(GameState.player_position)
	draw_set_transform(player_point, -GameState.player_yaw, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -10), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)]), Color(0.4, 0.95, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var legend_y := rect.end.y + 16
	draw_string(font, Vector2(rect.position.x, legend_y), "● 敌人  ■ 补给  ◆ 当前目标  ▲ 玩家", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.65, 0.82, 0.88))
	draw_string(font, Vector2(rect.end.x - 110, legend_y), "M  关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.65, 0.82, 0.88))


func _draw_diamond(point: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		point + Vector2(0, -radius), point + Vector2(radius, 0),
		point + Vector2(0, radius), point + Vector2(-radius, 0)]), color)
