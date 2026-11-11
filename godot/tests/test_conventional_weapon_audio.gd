## Actual weapon_fired routing must spawn conventional audio, independently of the EM sound bank.
extends SceneTree

const SOUNDS := [
	[&"g17", "res://assets/audio/g17.wav", "gezortenplotz", 0.75],
	[&"mpx", "res://assets/audio/mpx.wav", "Franki-01234", 0.60],
]

var _assertions := 0
var _failures := 0


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	create_timer(15.0).timeout.connect(func() -> void:
		push_error("conventional weapon audio did not finish its actual playback lifecycle")
		quit(1))
	for item: Array in SOUNDS:
		_assert(FileAccess.file_exists(item[1]) and ResourceLoader.exists(item[1]), "%s has its own conventional firing sound asset" % item[0])
	if _failures > 0:
		_finish()
		return
	var streams: Array[AudioStreamWAV] = []
	for item: Array in SOUNDS:
		_check_source_wav(item[1], String(item[0]))
		var stream := load(item[1]) as AudioStreamWAV
		_assert(stream != null, "%s conventional sound imports as a WAV stream" % item[0])
		if stream == null:
			_finish()
			return
		streams.append(stream)
		_assert(stream.mix_rate == 44100 and not stream.data.is_empty(), "%s imports nonempty 44.1kHz playable recording data" % item[0])
		_assert(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and absf(stream.get_length() - float(item[3])) < 0.01, "%s sound is one non-looping shot with its declared edited duration" % item[0])
	_assert(streams[0].data != streams[1].data, "the two guns use different recording data")
	var manager := (load("res://scenes/ui/audio_manager.tscn") as PackedScene).instantiate()
	root.add_child(manager)
	await process_frame
	var events = root.get_node("Events")
	var state = root.get_node("GameState")
	state.current_weapon = &"rifle"
	var actual_players: Array[AudioStreamPlayer] = []
	for item: Array in SOUNDS:
		var before: Array[Node] = manager.get_children()
		events.weapon_fired.emit(item[0])
		var players: Array[AudioStreamPlayer] = []
		for child in manager.get_children():
			if child is AudioStreamPlayer and child not in before and child.bus == &"sfx":
				players.append(child)
		_assert(players.size() == 1, "%s real weapon_fired signal creates one SFX player even when another gun is selected" % item[0])
		if players.size() == 1:
			actual_players.append(players[0])
			_assert(players[0].playing and players[0].stream != null and players[0].stream.resource_path == item[1], "%s actual SFX playback uses its new recording rather than an EM source" % item[0])
	var licenses := FileAccess.get_file_as_string("res://assets/audio/LICENSES.md")
	_assert("g17.wav" in licenses and "mpx.wav" in licenses and "CC-BY" in licenses and "CC0" in licenses, "audio attribution records both edited files and their source licenses")
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	root.add_child(title)
	var text: String = title.get_node("CreditsPanel/VBox/CreditsText").text
	for item: Array in SOUNDS:
		_assert(String(item[2]) in licenses and String(item[2]) in text, "%s recording author appears in the ledger and the actual in-game credits" % item[0])
	_assert("MP5A3" in text and "近似" in text, "in-game credits identify the MPX sound as an MP5A3 approximation")
	# A play request must actually reach the mixer; let both real SFX complete naturally at their actual pitch.
	for player in actual_players:
		while is_instance_valid(player) and player.playing:
			await process_frame
	await process_frame
	await process_frame
	_assert(actual_players.all(func(player): return not is_instance_valid(player)), "both actual firing SFX finish naturally and release their player nodes")
	# Ambient stop retires playback at the next measured mix, then on the main thread (same gate as scene_boot_smoke).
	for child in manager.get_children():
		if child is AudioStreamPlayer:
			child.stop()
	manager.queue_free()
	title.queue_free()
	await process_frame
	await process_frame
	var mix_period := AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix()
	await create_timer(maxf(mix_period, 1.0 / Engine.max_fps)).timeout
	await process_frame
	await process_frame
	_finish()


func _check_source_wav(path: String, label: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, label + " edited source WAV can be read")
	if file == null:
		return
	var riff := file.get_buffer(4).get_string_from_ascii()
	file.get_32()
	var kind := file.get_buffer(4).get_string_from_ascii()
	_assert(riff == "RIFF" and kind == "WAVE", label + " edited source uses a complete RIFF/WAVE container")
	var format := 0
	var channels := 0
	var rate := 0
	var bits := 0
	var data_bytes := 0
	while file.get_position() + 8 <= file.get_length():
		var chunk := file.get_buffer(4).get_string_from_ascii()
		var size := file.get_32()
		var begin := file.get_position()
		if begin + size > file.get_length():
			break
		if chunk == "fmt " and size >= 16:
			format = file.get_16()
			channels = file.get_16()
			rate = file.get_32()
			file.get_32()
			file.get_16()
			bits = file.get_16()
		elif chunk == "data":
			data_bytes = size
		file.seek(begin + size + size % 2)
	file.close()
	_assert(format == 1 and channels in [1, 2] and rate == 44100 and bits == 16 and data_bytes > 0, label + " source is nonempty 44.1kHz mono/stereo PCM16 before Godot import compression")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("CONVENTIONAL_WEAPON_AUDIO assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
