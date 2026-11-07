extends "res://scripts/enemies/enemy_base.gd"

var target_health: float = 150.0
var _animation_player: AnimationPlayer


func _ready() -> void:
	super._ready()
	remove_from_group(&"enemy")
	add_to_group(&"range_target")
	health = target_health
	var players := find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation_player = players[0] as AnimationPlayer
		if _animation_player.has_animation(&"idle"):
			_animation_player.play(&"idle")
		elif _animation_player.has_animation(&"crawl"):
			_animation_player.play(&"crawl")


func _on_damaged(_amount: float, _attacker_pos: Vector3) -> void:
	pass


func _die() -> void:
	_dead = true
	Events.enemy_died.emit(self)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if _animation_player != null and _animation_player.has_animation(&"death"):
		_animation_player.play(&"death")
		await _animation_player.animation_finished
	queue_free()
