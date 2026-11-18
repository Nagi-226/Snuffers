## M700原内置弹仓逐发装填；物理tick完成栓机后才允许下一发。
## 枪体/原狙击镜不替换，独立原栓机网格与黑色原生手臂共同运动。
extends LongGunController

var _bolt_left: float = 0.0
var _reload_progress: float = 0.0
var _closing_reload_bolt: bool = false
var _bolt: Node3D
var _bolt_home := Transform3D.IDENTITY
var _bolt_grip_local := Vector3.ZERO
var _loading_round: Node3D
var _round_basis := Basis.IDENTITY


func _ready() -> void:
	super()
	_bolt = _weapon_node.get_node_or_null(^"M700Scoped/Bolt") as Node3D
	var grip := _weapon_node.get_node_or_null(^"M700Scoped/BoltGrip") as Node3D
	_loading_round = get_node_or_null(^"ViewModel/LoadingRound") as Node3D
	if _bolt == null or grip == null or _loading_round == null:
		push_error("M700 could not resolve its actual bolt, grip and insertion model")
		return
	_bolt_home = _bolt.transform
	_bolt_grip_local = _bolt.to_local(grip.global_position)
	# 先按圆柱本地Y长轴缩放，再旋转沿枪口-Z；不从每帧分解后的scale累乘。
	_round_basis = Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(GameConfig.M700_ROUND_RADIUS * 2.0, GameConfig.M700_ROUND_LENGTH, GameConfig.M700_ROUND_RADIUS * 2.0))
	_loading_round.visible = false


func _tick_weapon(delta: float) -> void:
	var elapsed := maxf(delta, 0.0)
	var was_cycling := _bolt_left > 0.0
	_bolt_left = maxf(0.0, _bolt_left - elapsed)
	if was_cycling and _bolt_left <= 0.0:
		_closing_reload_bolt = false
		if ChamberFeed.load_chamber(weapon_data.weapon_id, weapon_data.weapon_id + "_mag"):
			Events.ammo_changed.emit(weapon_data.weapon_id, GameState.get(weapon_data.weapon_id + "_mag"), GameState.get(_reserve_key))
	if _is_reloading:
		_reload_progress += elapsed / weapon_data.reload_time
		while _reload_progress >= 1.0 and _is_reloading:
			_reload_progress -= 1.0
			var mag := int(GameState.get(weapon_data.weapon_id + "_mag"))
			var reserve := int(GameState.get(_reserve_key))
			if mag < weapon_data.mag_size and reserve > 0:
				GameState.set(weapon_data.weapon_id + "_mag", mag + 1)
				GameState.set(_reserve_key, reserve - 1)
				Events.ammo_changed.emit(weapon_data.weapon_id, mag + 1, reserve - 1)
			if int(GameState.get(weapon_data.weapon_id + "_mag")) >= weapon_data.mag_size or int(GameState.get(_reserve_key)) <= 0:
				Events.weapon_reloaded.emit(weapon_data.weapon_id)
			elif _native_arms != null:
				_native_arms.begin_reload(weapon_data.reload_time)
	super._tick_weapon(delta)


func _fire() -> bool:
	if _is_reloading or _bolt_left > 0.0:
		return false
	if not ChamberFeed.is_chambered(weapon_data.weapon_id) and int(GameState.get(weapon_data.weapon_id + "_mag")) > 0:
		_begin_bolt(false)
		return false
	if not super._fire():
		return false
	_begin_bolt(false)
	return true


func _begin_bolt(closing_reload: bool) -> void:
	_closing_reload_bolt = closing_reload
	_bolt_left = GameConfig.M700_BOLT_TIME


func _start_reload() -> void:
	if _is_reloading or _bolt_left > 0.0 or int(GameState.get(_reserve_key)) <= 0:
		return
	if int(GameState.get(weapon_data.weapon_id + "_mag")) >= weapon_data.mag_size:
		return
	_reload_generation += 1
	_reload_progress = 0.0
	Events.weapon_reload_started.emit(weapon_data.weapon_id)


func _play_reload_anim() -> void:
	_reload_progress = 0.0
	if _native_arms != null:
		_native_arms.begin_reload(weapon_data.reload_time)
	if _loading_round != null:
		_loading_round.visible = false


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != weapon_data.weapon_id:
		return
	_reset_reload_visuals()
	_is_reloading = false
	_reload_progress = 0.0
	_begin_bolt(true)
	if _loading_round != null:
		_loading_round.visible = false
	Events.ammo_changed.emit(weapon_id, GameState.get(weapon_id + "_mag"), GameState.get(_reserve_key))


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	_bolt_left = 0.0
	_reload_progress = 0.0
	_closing_reload_bolt = false
	if _bolt != null:
		_bolt.transform = _bolt_home
	if _loading_round != null:
		_loading_round.visible = false
	if weapon_id == weapon_data.weapon_id and not ChamberFeed.is_chambered(weapon_id) and int(GameState.get(weapon_id + "_mag")) > 0:
		_begin_bolt(false)


func _process(delta: float) -> void:
	super._process(delta)
	if _bolt == null or _loading_round == null:
		return
	var pull := 0.0
	var lift := 0.0
	if _is_reloading:
		pull = 1.0
		lift = 1.0
	elif _bolt_left > 0.0:
		var progress := clampf(1.0 - _bolt_left / GameConfig.M700_BOLT_TIME, 0.0, 1.0)
		if _closing_reload_bolt:
			pull = 1.0 - smoothstep(0.0, GameConfig.M700_BOLT_CLOSE_PHASE, progress)
			lift = 1.0 - smoothstep(GameConfig.M700_BOLT_CLOSE_PHASE, 1.0, progress)
		else:
			lift = smoothstep(0.0, GameConfig.M700_BOLT_OPEN_PHASE, progress) * (1.0 - smoothstep(GameConfig.M700_BOLT_CLOSE_PHASE, 1.0, progress))
			var travel := clampf((progress - GameConfig.M700_BOLT_OPEN_PHASE) / (GameConfig.M700_BOLT_CLOSE_PHASE - GameConfig.M700_BOLT_OPEN_PHASE), 0.0, 1.0)
			pull = sin(travel * PI)
	_bolt.transform = _bolt_home * Transform3D(Basis(Vector3.FORWARD, -GameConfig.M700_BOLT_LIFT * lift), Vector3.BACK * GameConfig.M700_BOLT_PULL * pull)
	_loading_round.visible = false
	if _native_arms == null:
		return
	var profile: Dictionary = _native_arms._profile
	var hip_offset := _pose_extra.basis * Vector3(0, 0, float(profile.hip_rearward) * (1.0 - _aim_weight))
	if _is_reloading:
		var progress := clampf(_reload_progress, 0.0, 1.0)
		var cant := sin(progress * PI)
		_weapon_node.transform = _pose_extra * _weapon_home * Transform3D(Basis.from_euler(Vector3(0, 0, -GameConfig.M700_RELOAD_CANT * cant)), GameConfig.M700_RELOAD_LIFT * cant)
		_weapon_node.position += hip_offset
		_arms_animation.seek(progress * weapon_data.reload_time, true)
		_native_arms.pose_hold(_aim_weight)
		var retrieve := GameConfig.M700_ROUND_RETRIEVE_PHASE
		var insert := GameConfig.M700_ROUND_INSERT_PHASE
		var travel := smoothstep(retrieve, insert, progress)
		var point := GameConfig.M700_ROUND_START.lerp(GameConfig.M700_ROUND_PORT, travel)
		_loading_round.global_transform = Transform3D(_weapon_node.global_basis * _round_basis, _weapon_node.to_global(point))
		_loading_round.visible = progress >= retrieve and progress < insert
		var reach := smoothstep(0.0, retrieve, progress)
		if progress >= insert:
			reach = 1.0 - smoothstep(insert, 1.0, progress)
		var support: Vector3 = (profile.support_grip_hip as Vector3).lerp(profile.support_grip_ads as Vector3, _aim_weight)
		_native_arms.pose_left_grip(_weapon_node.to_global(support.lerp(point + GameConfig.M700_ROUND_HAND_OFFSET, reach)), _native_arms.support_basis_world())
	else:
		_weapon_node.position += hip_offset
		_native_arms.pose_hold(_aim_weight)
		if _bolt_left > 0.0:
			var grip_point := _bolt.to_global(_bolt_grip_local)
			var rotation: Basis = _weapon_node.global_basis.orthonormalized() * _native_arms._wrist_basis[0]
			_native_arms._place_palm(0, grip_point, rotation)
	_native_arms.update_bounds()
