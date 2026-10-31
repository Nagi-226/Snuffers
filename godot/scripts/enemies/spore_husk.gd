extends "res://scripts/enemies/enemy_base.gd"

enum State { DORMANT, ALERT, ENGAGE, COMPRESS, LEAP, RECOVER }

var current_state: int = State.DORMANT
var _state_timer := 0.0
var _attack_cooldown := 0.0
var _leap_hit := false
var _animation_player: AnimationPlayer = null


func _ready() -> void:
	super()
	enemy_kind = &"spore_husk"
	health = GameConfig.SPORE_HUSK_HP
	var players := $BodyMesh.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation_player = players[0] as AnimationPlayer
		_animation_player.animation_finished.connect(_on_animation_finished)
		for clip_name in [&"idle", &"crawl"]:
			var clip := _animation_player.get_animation(clip_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
		_play(&"idle")


func _play(clip_name: StringName, restart := false) -> void:
	if _animation_player == null or not _animation_player.has_animation(clip_name):
		return
	if not restart and _animation_player.current_animation == clip_name:
		return
	_animation_player.play(clip_name, 0.12)


func _set_state(next_state: int, timer := 0.0) -> void:
	current_state = next_state
	_state_timer = timer
	match current_state:
		State.DORMANT, State.RECOVER:
			_play(&"idle")
		State.ALERT, State.COMPRESS:
			_play(&"alert", true)
		State.ENGAGE:
			_play(&"crawl")
		State.LEAP:
			_play(&"leap", true)


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
		State.DORMANT:
			velocity.x = 0.0
			velocity.z = 0.0
			if dist <= GameConfig.SPORE_HUSK_ALERT_RANGE and _update_sight(delta, player_pos + Vector3(0, 0.4, 0)):
				_set_state(State.ALERT, 0.35)
		State.ALERT:
			_face_position(player_pos)
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_timer <= 0.0:
				_set_state(State.ENGAGE)
		State.ENGAGE:
			_face_position(player_pos)
			var direction := player_pos - global_position
			direction.y = 0.0
			direction = direction.normalized()
			velocity.x = direction.x * GameConfig.SPORE_HUSK_SPEED
			velocity.z = direction.z * GameConfig.SPORE_HUSK_SPEED
			if dist >= GameConfig.SPORE_HUSK_LEAP_MIN and dist <= GameConfig.SPORE_HUSK_LEAP_MAX and _attack_cooldown <= 0.0:
				_set_state(State.COMPRESS, 0.3)
			elif dist <= 1.3 and _attack_cooldown <= 0.0:
				_attack_cooldown = GameConfig.SPORE_HUSK_COOLDOWN
				_damage_player(GameConfig.SPORE_HUSK_DAMAGE)
		State.COMPRESS:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_timer <= 0.0:
				_begin_leap(player_pos)
		State.LEAP:
			if not _leap_hit and dist <= 1.25:
				_leap_hit = true
				_attack_cooldown = GameConfig.SPORE_HUSK_COOLDOWN
				_damage_player(GameConfig.SPORE_HUSK_DAMAGE)
			if is_on_floor() and _state_timer <= 0.35:
				_set_state(State.RECOVER, 0.65)
		State.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_timer <= 0.0:
				_set_state(State.ENGAGE)
	move_and_slide()


func _begin_leap(player_pos: Vector3) -> void:
	_leap_hit = false
	var direction := player_pos - global_position
	direction.y = 0.0
	direction = direction.normalized()
	velocity.x = direction.x * GameConfig.SPORE_HUSK_LEAP_HORIZONTAL
	velocity.z = direction.z * GameConfig.SPORE_HUSK_LEAP_HORIZONTAL
	velocity.y = GameConfig.SPORE_HUSK_LEAP_VERTICAL
	_set_state(State.LEAP, 0.9)


func get_state_name() -> StringName:
	return StringName(State.keys()[current_state])


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
