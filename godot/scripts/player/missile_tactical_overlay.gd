## 长弓瞄准镜：沿用目标投影和测距，锁定只累计同一个中心选中目标。
extends "res://scripts/player/dmr_tactical_overlay.gd"

var _selected_target: Node3D = null
var _lock_elapsed: float = 0.0


func _ready() -> void:
	Events.ec120_lock_consumed.connect(clear_lock)
	Events.ec120_guidance_changed.connect(_on_guidance_changed)
	Events.weapon_switched.connect(_on_weapon_switched)
	Events.player_aim_changed.connect(_on_aim_changed)


func _process(delta: float) -> void:
	if not visible or camera == null or GameState.current_weapon != &"em120r" or not GameState.is_aiming:
		clear_lock()
		return
	# 每帧重新确认中心选中与遮挡，避免把刷新间隔内的失去目标计入连续锁定。
	_refresh_targets()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_range()
		_refresh_left = GameConfig.DMR_SCOPE_REFRESH_INTERVAL
	for target in _target_age:
		if is_instance_valid(target):
			_target_age[target] += delta
	_update_lock(delta)
	queue_redraw()


func _refresh_targets() -> void:
	super()
	_primary_target = null
	for entry in _targets:
		if (entry.rect as Rect2).has_point(size * 0.5):
			_primary_target = entry.target as Node3D
			break


func _update_lock(delta: float) -> void:
	if GameState.em120r_guidance_mode != &"homing":
		clear_lock()
		return
	var target := _primary_target
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		clear_lock()
		return
	var health: Variant = target.get("health")
	if health != null and float(health) <= 0.0:
		clear_lock()
		return
	if target != _selected_target:
		clear_lock()
		_selected_target = target
		return
	_lock_elapsed = minf(_lock_elapsed + delta, GameConfig.EM120R_LOCK_TIME)
	if _lock_elapsed >= GameConfig.EM120R_LOCK_TIME and GameState.em120r_locked_target != target:
		GameState.em120r_locked_target = target
		Events.ec120_lock_changed.emit(target)


func clear_lock() -> void:
	_selected_target = null
	_lock_elapsed = 0.0
	if GameState.em120r_locked_target != null:
		GameState.em120r_locked_target = null
		Events.ec120_lock_changed.emit(null)


func _on_guidance_changed(_mode: StringName) -> void:
	clear_lock()


func _on_weapon_switched(_weapon_id: StringName) -> void:
	clear_lock()


func _on_aim_changed(aiming: bool) -> void:
	if not aiming:
		clear_lock()


func _draw() -> void:
	if camera == null:
		return
	var font := get_theme_default_font()
	var center := size * 0.5
	var color := Color(0.32, 0.90, 1.0, 0.95)
	for entry in _targets:
		if not is_instance_valid(entry.target):
			continue
		var selected: bool = entry.target == _selected_target
		_draw_target_frame(entry.rect as Rect2, color if selected else Color(0.32, 0.90, 1.0, 0.5), selected)
	var progress := _lock_elapsed / GameConfig.EM120R_LOCK_TIME
	if progress > 0.0:
		draw_arc(center, size.y * 0.065, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, color, 2.0, true)
	var radius := _scope_radius()
	var mode_text := "LASER GUIDANCE" if GameState.em120r_guidance_mode == &"laser" else "FIRE & FORGET"
	draw_string(font, center + Vector2(-radius * 0.55, -radius * 0.76), "EC-120 / " + mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
	draw_string(font, center + Vector2(-radius * 0.72, radius * 0.72), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
	draw_string(font, center + Vector2(radius * 0.28, radius * 0.72), _range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
	if _selected_target != null:
		var label := "LOCKED" if GameState.em120r_locked_target == _selected_target else "ACQUIRE %d%%" % int(_lock_elapsed / GameConfig.EM120R_LOCK_TIME * 100.0)
		draw_string(font, center + Vector2(-64, radius * 0.50), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	if GameState.em120r_guidance_mode == &"homing" and _selected_target == null:
		draw_string(font, center + Vector2(-64, radius * 0.50), "CENTER TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
