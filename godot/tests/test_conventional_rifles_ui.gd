## Service rifle HUD, real sound event routing, model icons and in-game attribution.
extends SceneTree

const IDS := [&"sig516", &"sr25", &"m700"]
const DETAILS := {
	&"sig516": {"name": "SIG516", "ammo": "5.56×45mm", "reserve": &"ammo_556_reserve", "cap": 30, "pitch": "SIG516_SOUND_PITCH"},
	&"sr25": {"name": "SR25", "ammo": "7.62×51mm", "reserve": &"ammo_308_reserve", "cap": 20, "pitch": "SR25_SOUND_PITCH"},
	&"m700": {"name": "Remington M700", "ammo": ".308 Win", "reserve": &"ammo_308_reserve", "cap": 5, "pitch": "M700_SOUND_PITCH"},
}
const SOURCES := [
	["N-GONE", "a9ea47674b824665b4e3b58a28b149e8"],
	["TastyTony", "81976c51d61543a288cf135fd7485951"],
	["mehmetuysun", "f55c2e95edd84b80b283e181d63e5ef6"],
	["GoldbergR", "bf0e3597985940408d24669297d15509"],
	["GoldbergR", "daa7dd1e247e453496974a5d252396f4"],
]
const AUDIO_SOURCES := {
	&"sig516": ["areniporgen", "737569"],
	&"sr25": ["areniporgen", "712577"],
	&"m700": ["gezortenplotz", "43756"],
}

var _assertions := 0
var _failures := 0


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void:
		push_error("service rifle UI/audio verification timed out")
		quit(1))
	var state = root.get_node("GameState")
	var events = root.get_node("Events")
	state.reset()
	var config = root.get_node("GameConfig")
	_assert(config.AMMO_556_RESERVE == 600 and state.ammo_556_reserve == 600, "real fresh Config and GameState start the shared 5.56 reserve at the approved 600 rounds")
	_assert(config.AMMO_308_RESERVE == 300 and state.ammo_308_reserve == 300, "real fresh Config and GameState start the shared .308 reserve at the approved 300 rounds")
	_assert(config.M700_MAG == 5, "real fresh Config freezes M700 at five internal rounds independently of the HUD fixture")
	var fresh_m700_total: int = int(state.m700_mag) + (1 if state.weapon_chambered.get(&"m700", false) else 0)
	_assert(state.m700_mag == 5 and state.weapon_chambered.get(&"m700", false) and fresh_m700_total == 6, "real fresh GameState supplies five M700 internal rounds plus one retained chamber before any manual HUD state")
	var m700_data = load("res://scenes/weapons/m700.tres").duplicate()
	_assert(m700_data.mag_size == 5, "raw M700 WeaponData resource stores the approved five-round internal capacity before Config sync")
	m700_data.sync_from_config()
	_assert(m700_data.mag_size == 5, "M700 WeaponData Config sync retains the approved five-round internal capacity")
	var hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var ammo = hud._weapon_ammo
	for id: StringName in [&"sr25", &"m700"]:
		state.current_weapon = id
		events.weapon_switched.emit(id)
		_assert(ammo.weapon_id == id and ammo.reserve == 300, "%s actual fresh HUD consumes the same approved 300-round .308 reserve" % id)
		if id == &"m700":
			_assert(ammo.mag == 6 and ammo.show_chamber_bonus, "actual fresh M700 HUD displays five internal rounds plus one chamber without manually replacing its state")
	if "--reserve-only" in OS.get_cmdline_user_args():
		hud.queue_free()
		await process_frame
		print("CONVENTIONAL_RIFLES_UI assertions=", _assertions, " failures=", _failures)
		quit(1 if _failures > 0 else 0)
		return
	state.ammo_556_reserve = 231
	state.ammo_308_reserve = 317
	for id: StringName in IDS:
		var detail: Dictionary = DETAILS[id]
		state.weapon_unlocked[id] = true
		state.set(String(id) + "_mag", detail.cap)
		state.weapon_chambered[id] = true
		state.current_weapon = id
		events.weapon_switched.emit(id)
		_assert(ammo.weapon_id == id and String(ammo.weapon_name) == detail.name and ammo.mag == int(detail.cap) + 1 and ammo.show_chamber_bonus and ammo.reserve == int(state.get(detail.reserve)), "%s actual switch displays its own name, full magazine plus chamber, and correct conventional reserve" % id)
		_assert(ammo.ammo_type == detail.ammo and not ammo.show_grenades, "%s actual HUD identifies its conventional cartridge without an unrelated grenade count" % id)
		var expected_mode: String = "栓动" if id == &"m700" else ("全自动" if id == &"sig516" else "半自动")
		_assert(expected_mode in ammo.mode_tag, "%s HUD displays the actual firing mechanism" % id)
		state.set(String(id) + "_mag", 2)
		state.weapon_chambered[id] = false
		events.ammo_changed.emit(id, 2, int(state.get(detail.reserve)))
		_assert(ammo.mag == 2 and not ammo.show_chamber_bonus, "%s actual ammunition event displays chamber-empty supply without plus-one" % id)
		var selected_mag: int = ammo.mag
		events.ammo_changed.emit(&"rifle", 19, 999)
		_assert(ammo.weapon_id == id and ammo.mag == selected_mag, "%s ignores another weapon's ammunition event" % id)
	state.current_weapon = &"sig516"
	events.weapon_switched.emit(&"sig516")
	var remembered: Dictionary = state.weapon_accessory_modes.duplicate()
	for mode: StringName in [&"laser", &"flashlight", &"combined"]:
		state.weapon_accessory_modes[&"sig516"] = mode
		events.weapon_accessory_mode_changed.emit(&"sig516", mode)
		var tag: String = {&"laser": "红点", &"flashlight": "手电", &"combined": "红点+手电"}[mode]
		_assert(ammo.weapon_id == &"sig516" and String(ammo.mode_tag).ends_with("·" + tag), "SIG516 actual accessory event updates its %s HUD tag" % mode)
	_assert(state.weapon_accessory_modes[&"g17"] == remembered[&"g17"] and state.weapon_accessory_modes[&"mpx"] == remembered[&"mpx"], "SIG516 HUD refresh preserves the independent older accessory states")
	var icon_script = load("res://scripts/ui/weapon_icon.gd")
	var icons: Dictionary = icon_script.ICONS
	for id: StringName in IDS:
		var texture := icons.get(id) as Texture2D
		_assert(texture != null and texture.resource_path == "res://assets/ui/weapons/%s.svg" % id and texture.get_width() > 0 and texture.get_height() > 0, "%s actual weapon icon maps to its own imported silhouette" % id)
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	root.add_child(title)
	var credits: String = title.get_node("CreditsPanel/VBox/CreditsText").text
	var ledger := FileAccess.get_file_as_string("res://addons/community_weapons/ATTRIBUTION.md")
	for source: Array in SOURCES:
		_assert(String(source[0]) in credits and String(source[1]) in credits and String(source[0]) in ledger and String(source[1]) in ledger, "%s model %s author and official URL occur in both asset ledger and actual game credits" % [source[0], source[1]])
	_assert("https://creativecommons.org/licenses/by/4.0/" in credits and "调整" in credits, "actual model credits retain the license link and modification notice")
	var audio_ledger := FileAccess.get_file_as_string("res://assets/audio/LICENSES.md")
	for id: StringName in IDS:
		var source: Array = AUDIO_SOURCES[id]
		_assert("%s_fire.wav" % id in audio_ledger and source[0] in audio_ledger and source[1] in audio_ledger and source[0] in credits and source[1] in credits, "%s independent recording file, real author and official source URL appear in the ledger and actual game credits" % id)
	await _check_audio(events)
	hud.queue_free()
	title.queue_free()
	await process_frame
	await process_frame
	print("CONVENTIONAL_RIFLES_UI assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check_audio(events) -> void:
	var config = root.get_node("GameConfig")
	var state = root.get_node("GameState")
	var manager := (load("res://scenes/ui/audio_manager.tscn") as PackedScene).instantiate()
	root.add_child(manager)
	await process_frame
	var actual_players: Array[AudioStreamPlayer] = []
	var pcm_hashes: Array[String] = []
	var older_pcm_hashes: Array[String] = []
	for path: String in ["res://assets/audio/g17.wav", "res://assets/audio/mpx.wav"]:
		older_pcm_hashes.append(_pcm_sha256(_source_pcm(path, false)))
	state.current_weapon = &"pistol"
	for id: StringName in IDS:
		var expected := "res://assets/audio/%s_fire.wav" % id
		var pcm := _source_pcm(expected, true)
		if not pcm.is_empty():
			var digest := _pcm_sha256(pcm)
			_assert(not pcm_hashes.has(digest) and not older_pcm_hashes.has(digest), "%s actual PCM SHA256 differs from both other new recordings and older G17/MPX recordings" % id)
			pcm_hashes.append(digest)
			print("CONVENTIONAL_AUDIO_PCM id=", id, " sha256=", digest)
		var before: Array[Node] = manager.get_children()
		events.weapon_fired.emit(id)
		var players: Array[AudioStreamPlayer] = []
		for child in manager.get_children():
			if child is AudioStreamPlayer and child not in before and child.bus == &"sfx":
				players.append(child)
		_assert(players.size() == 1, "%s actual weapon_fired ID spawns exactly one SFX even while another weapon is selected" % id)
		if players.size() != 1:
			continue
		var player := players[0]
		actual_players.append(player)
		var base: float = config.get(DETAILS[id].pitch)
		var jitter: float = config.SFX_PITCH_JITTER
		_assert(is_equal_approx(base, 1.0), "%s independent recording keeps its real source pitch at the approved 1.0 base" % id)
		_assert(player.playing and player.stream is AudioStreamWAV and player.stream.resource_path == expected and player.stream.get_length() >= 0.20 and player.stream.get_length() <= 3.0 and player.pitch_scale >= base * (1.0 - jitter) - 0.0001 and player.pitch_scale <= base * (1.0 + jitter) + 0.0001, "%s actual playback uses its own nonempty real shot WAV and approved source pitch" % id)
	_assert(pcm_hashes.size() == 3, "all three independent conventional gun recordings supply valid distinct PCM data")
	for player in actual_players:
		while is_instance_valid(player) and player.playing:
			await process_frame
	await process_frame
	await process_frame
	_assert(actual_players.all(func(player): return not is_instance_valid(player)), "all actual service rifle shots finish and release their SFX player naturally")
	for child in manager.get_children():
		if child is AudioStreamPlayer:
			child.stop()
	manager.queue_free()
	await process_frame
	await process_frame
	var mix_period := AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix()
	await create_timer(maxf(mix_period, 1.0 / Engine.max_fps)).timeout
	await process_frame
	await process_frame


func _pcm_sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _source_pcm(path: String, validate: bool) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if validate:
		_assert(file != null, path.get_file() + " independent shot recording exists before loading")
	if file == null:
		return PackedByteArray()
	var riff := file.get_buffer(4).get_string_from_ascii()
	var declared := file.get_32()
	var kind := file.get_buffer(4).get_string_from_ascii()
	var format := 0
	var channels := 0
	var rate := 0
	var bits := 0
	var pcm := PackedByteArray()
	var complete := declared + 8 == file.get_length()
	while file.get_position() + 8 <= file.get_length():
		var chunk := file.get_buffer(4).get_string_from_ascii()
		var size := file.get_32()
		var begin := file.get_position()
		if begin + size > file.get_length():
			complete = false
			break
		if chunk == "fmt " and size >= 16:
			format = file.get_16()
			channels = file.get_16()
			rate = file.get_32()
			file.get_32()
			file.get_16()
			bits = file.get_16()
		elif chunk == "data":
			pcm = file.get_buffer(size)
		file.seek(begin + size + size % 2)
	file.close()
	var valid := riff == "RIFF" and kind == "WAVE" and complete and format == 1 and channels in [1, 2] and rate == 44100 and bits == 16 and not pcm.is_empty() and pcm.size() % (2 * maxi(channels, 1)) == 0
	if validate:
		_assert(valid, path.get_file() + " is a complete 44.1kHz mono/stereo PCM16 WAV with real sample frames")
	if not valid:
		return PackedByteArray()
	if validate:
		var energy := 0.0
		var peak := 0.0
		var clipped := 0
		var onset := -1
		for index in range(0, pcm.size(), 2):
			var sample: int = int(pcm[index]) | (int(pcm[index + 1]) << 8)
			if sample >= 32768:
				sample -= 65536
			var value := absf(float(sample) / 32768.0)
			energy += value * value
			peak = maxf(peak, value)
			if value >= 0.999:
				clipped += 1
			if onset < 0 and value >= 0.005:
				onset = index / 2
		var samples := int(pcm.size() / 2)
		var rms := sqrt(energy / maxf(samples, 1))
		var duration := float(samples) / float(channels * rate)
		_assert(duration >= 0.20 and duration <= 3.0 and rms >= 0.005 and peak >= 0.10 and float(clipped) / samples < 0.0005 and onset >= 0 and float(onset) / float(channels * rate) <= 0.10, path.get_file() + " contains an audible prompt single-shot-length waveform without prolonged initial silence or significant digital clipping")
		print("CONVENTIONAL_AUDIO_WAVE file=", path.get_file(), " duration=", duration, " rms=", rms, " peak=", peak, " clipped=", clipped, " onset=", float(onset) / float(channels * rate))
	return pcm


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
