## Retiming must preserve every original key and leave all other platform resources alone.
extends SceneTree

const IDS := [&"rifle", &"dmr", &"shotgun", &"smg", &"lmg", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1", &"spas12", &"em120r"]
var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source = (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate()
	root.add_child(source)
	await process_frame
	var source_player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source_clip := source_player.get_animation(&"reload")
	var times: Array = []
	var values: Array = []
	for track in source_clip.get_track_count():
		var row: Array = []
		var value_row: Array = []
		for key in source_clip.track_get_key_count(track):
			row.append(source_clip.track_get_key_time(track, key))
			value_row.append(source_clip.track_get_key_value(track, key))
		times.append(row)
		values.append(value_row)
	var lengths: Dictionary = {}
	var players: Array = []
	var weapons: Array = []
	for id in IDS:
		root.get_node("GameState").current_weapon = id
		var weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
		root.add_child(weapon)
		await process_frame
		weapons.append(weapon)
		var animation: AnimationPlayer = weapon._arms_animation
		_assert(animation != null and animation.get_animation_library("") != source_player.get_animation_library(""), "%s owns an isolated animation library" % id)
		if animation == null or weapon._native_arms == null:
			_assert(false, "%s provides its native adapter" % id)
			continue
		var duration: float = weapon.weapon_data.reload_time
		weapon._native_arms.begin_reload(duration)
		var clip := animation.get_animation(&"reload")
		_assert(is_equal_approx(clip.length, duration), "%s uses its own gameplay duration" % id)
		var complete := clip.get_track_count() == times.size()
		for track in mini(clip.get_track_count(), times.size()):
			complete = complete and clip.track_get_key_count(track) == times[track].size()
			for key in mini(clip.track_get_key_count(track), times[track].size()):
				complete = complete and absf(clip.track_get_key_time(track, key) - float(times[track][key]) * duration / source_clip.length) < 0.00001
				complete = complete and clip.track_get_key_value(track, key) == values[track][key]
		_assert(complete, "%s preserves every native key value and scaled time" % id)
		lengths[animation] = duration
		players.append(animation)
	for animation: AnimationPlayer in players:
		_assert(is_equal_approx(animation.get_animation(&"reload").length, lengths[animation]), "later platform setup cannot change an earlier reload duration")
	var unchanged := true
	for track in source_clip.get_track_count():
		unchanged = unchanged and source_clip.track_get_key_count(track) == times[track].size()
		for key in mini(source_clip.track_get_key_count(track), times[track].size()):
			unchanged = unchanged and source_clip.track_get_key_time(track, key) == times[track][key] and source_clip.track_get_key_value(track, key) == values[track][key]
	_assert(unchanged, "all sixteen adapters leave the shared source and pistol animation keys unchanged")
	for weapon in weapons:
		weapon.queue_free()
	source.queue_free()
	players.clear()
	weapons.clear()
	lengths.clear()
	await process_frame
	await process_frame
	print("NATIVE_LONG_GUN_ANIMATION assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
