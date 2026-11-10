## 真实 SceneTree 时钟验证：停止普通process不能自证AnimationPlayer内部时钟已停。
extends SceneTree

var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var adapter = load("res://scripts/player/native_pistol_arms.gd").new()
	var arms := (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate() as Node3D
	var gun := (load("res://addons/community_weapons/g17_gen5_olight.glb") as PackedScene).instantiate() as Node3D
	var mount := Node3D.new()
	root.add_child(mount)
	mount.add_child(arms)
	mount.add_child(gun)
	var config = root.get_node("GameConfig")
	_assert(adapter.configure(arms, gun, gun.find_child("Magazine", true, false), config.BLACK_PISTOL_PROFILES[&"gen5"]), "native clock adapter configures real Gen5")
	adapter.play_reload(1.6)
	await create_timer(0.15).timeout
	var unsampled: float = adapter.animation.current_animation_position
	print("NATIVE_CLOCK paused_update_position=", unsampled)
	_assert(unsampled < 0.0001, "native source animation stays frozen when adapter update is not called")
	adapter.reset()
	adapter.play_reload(1.6)
	var start := Time.get_ticks_usec()
	var previous := start
	var maximum_step := 0.0
	var elapsed := 0.0
	var frames := 0
	while elapsed < 0.25:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := float(now - previous) / 1000000.0
		previous = now
		elapsed = float(now - start) / 1000000.0
		maximum_step = maxf(maximum_step, delta)
		adapter.update(delta)
		frames += 1
	var rate: float = adapter.animation.get_animation(&"reload").length / 1.6
	var actual: float = adapter.animation.current_animation_position
	var expected := elapsed * rate
	print("NATIVE_CLOCK elapsed=", elapsed, " actual=", actual, " expected=", expected, " error=", absf(actual - expected), " maximum_step=", maximum_step, " frames=", frames)
	_assert(absf(actual - expected) < maxf(0.01, maximum_step * rate), "native reload advances once at the duration-adjusted rate under the real SceneTree clock")
	mount.queue_free()
	await process_frame
	print("NATIVE_PISTOL_CLOCK assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
