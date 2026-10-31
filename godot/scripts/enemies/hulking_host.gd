extends "res://scripts/enemies/enemy_base.gd"

enum State { IDLE, ADVANCE, WINDUP, RECOVER }

var current_state: int = State.IDLE
var _state_timer := 0.0
var _attack_cooldown := 0.0
var _animation_player: AnimationPlayer = null


func _ready() -> void:
	super()
	enemy_kind = &"hulking_host"
	health = GameConfig.HULKING_HOST_HP
	var players := $BodyMesh.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation_player = players[0] as AnimationPlayer
		_animation_player.animation_finished.connect(_on_animation_finished)
		for clip_name in [&"idle", &"walk"]:
			var clip := _animation_player.get_animation(clip_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
		_play(&"idle")


func _play(clip_name: StringName, restart := false) -> void:
	if _animation_player == null or not _animation_player.has_animation(clip_name):
		return
	if not restart and _animation_player.current_animation == clip_name:
		return
	_animation_player.play(clip_name, 0.15)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_state_timer -= delta
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	if not _has_player():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var player_pos := _get_player_position()
	var dist := _horizontal_distance_to(player_pos)
	match current_state:
		State.IDLE, State.ADVANCE:
			_face_position(player_pos)
			var direction := player_pos - global_position
			direction.y = 0.0
			direction = direction.normalized()
			velocity.x = direction.x * GameConfig.HULKING_HOST_SPEED
			velocity.z = direction.z * GameConfig.HULKING_HOST_SPEED
			current_state = State.ADVANCE
			_play(&"walk")
			if dist <= GameConfig.HULKING_HOST_MELEE_RANGE and _attack_cooldown <= 0.0 and _update_sight(delta, player_pos + Vector3(0, 1.2, 0)):
				current_state = State.WINDUP
				_state_timer = GameConfig.HULKING_HOST_WINDUP
				velocity.x = 0.0
				velocity.z = 0.0
				_play(&"attack", true)
		State.WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_timer <= 0.0:
				if dist <= GameConfig.HULKING_HOST_MELEE_RANGE and _smash_clear(player_pos):
					_damage_player(GameConfig.HULKING_HOST_DAMAGE)
				_attack_cooldown = GameConfig.HULKING_HOST_COOLDOWN
				current_state = State.RECOVER
				_state_timer = GameConfig.HULKING_HOST_RECOVER
		State.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_timer <= 0.0:
				current_state = State.ADVANCE
	move_and_slide()


func _smash_clear(player_pos: Vector3) -> bool:
	var from: Vector3 = $Eye.global_position
	var target := player_pos + Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.exclude = _los_exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or from.distance_to(hit.position) > from.distance_to(target) - 0.1


func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group(&"enemy")
	collision_layer = 0
	collision_mask = 0
	$HeadHitbox.collision_layer = 0
	$HeadHitbox.collision_mask = 0
	Events.enemy_died.emit(self)
	_play(&"death", true)
	if _animation_player == null:
		queue_free()


func _on_animation_finished(clip_name: StringName) -> void:
	if clip_name == &"death" and _dead:
		queue_free()
