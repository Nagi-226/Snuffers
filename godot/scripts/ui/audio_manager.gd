## AudioManager — 战斗音效与音频总线骨架（普通场景节点，非 autoload）
##
## 职责（W5 派单）：
## 1. _ready 时用 AudioServer 创建 sfx / loop / ambient 三条总线（挂在 Master 下），
##    音量取自 GameConfig.VOL_SFX / VOL_LOOP / VOL_AMBIENT（linear_to_db 换算）。
## 2. 对外接口：play_sfx(name) / play_loop(name) / stop_loop(name)。
## 3. 订阅 Events 信号完成战斗音效接线（接线表见 _connect_events 注释）。
##
## 契约约束：音量/音高抖动参数一律引用 GameConfig（AGENTS.md 约束 #2）；
## 场景通信只走 Events 总线（约束 #3）。资产台账见 assets/audio/LICENSES.md。
extends Node

## 音频文件目录（音效名即文件名主体，如 &"rifle" → rifle.mp3；ambient 为程序合成占位，
## 按蜂后裁决以 .wav 入库，加载时先找 .mp3 再找 .wav）。
const AUDIO_DIR: String = "res://assets/audio/"
## 枪声类音效：播放时附加 ±GameConfig.SFX_PITCH_JITTER 随机 pitch_scale（派单口径）。
const GUN_SOUNDS: Array[StringName] = [&"rifle", &"rocket"]

const BUS_SFX: StringName = &"sfx"
const BUS_LOOP: StringName = &"loop"
const BUS_AMBIENT: StringName = &"ambient"

## 音频流缓存：StringName → AudioStream（加载失败缓存 null 并告警，避免重复 IO 刷屏）。
var _streams: Dictionary = {}
## 循环音播放器注册表：StringName → AudioStreamPlayer。
var _loop_players: Dictionary = {}
## 环境音播放器（ambient 总线，场景就绪即循环）。
var _ambient_player: AudioStreamPlayer


func _ready() -> void:
	_setup_buses()
	_connect_events()
	_play_ambient()


func _exit_tree() -> void:
	_disconnect_events()
	stop_all_loops()
	if _ambient_player != null:
		_ambient_player.stop()


## 创建三条总线并设置音量（幂等：总线已存在则只刷新音量，防止重复 add_bus）。
func _setup_buses() -> void:
	_ensure_bus(BUS_SFX, GameConfig.VOL_SFX)
	_ensure_bus(BUS_LOOP, GameConfig.VOL_LOOP)
	_ensure_bus(BUS_AMBIENT, GameConfig.VOL_AMBIENT)


func _ensure_bus(bus_name: StringName, volume_linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(volume_linear))


## 播放一次性音效（sfx 总线）；枪声类自动附加随机音高抖动。
## name 与 assets/audio/ 下的文件名主体一致（rifle/rocket/reload/... ）。
func play_sfx(sound_name: StringName) -> void:
	var stream: AudioStream = _get_stream(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	if sound_name in GUN_SOUNDS:
		var jitter: float = GameConfig.SFX_PITCH_JITTER
		player.pitch_scale = randf_range(1.0 - jitter, 1.0 + jitter)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## 启动循环音（loop 总线：脚步/直升机）；同名重复调用幂等。
func play_loop(sound_name: StringName) -> void:
	if _loop_players.has(sound_name):
		return
	var stream: AudioStream = _get_stream(sound_name)
	if stream == null:
		return
	_enable_loop(stream)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_LOOP
	add_child(player)
	player.play()
	_loop_players[sound_name] = player


## 停止并释放指定循环音；未在播则静默返回。
func stop_loop(sound_name: StringName) -> void:
	var player: AudioStreamPlayer = _loop_players.get(sound_name, null) as AudioStreamPlayer
	if player == null:
		return
	player.stop()
	player.queue_free()
	_loop_players.erase(sound_name)


## 停止全部循环音（mission_completed / game_over 时调用）。
func stop_all_loops() -> void:
	for sound_name in _loop_players.keys():
		stop_loop(sound_name)


## 环境音：ambient 总线循环播放，场景就绪即开始（派单口径）。
func _play_ambient() -> void:
	var stream: AudioStream = _get_stream(&"ambient")
	if stream == null:
		return
	_enable_loop(stream)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = stream
	_ambient_player.bus = BUS_AMBIENT
	add_child(_ambient_player)
	_ambient_player.play()


## 加载并缓存音频流；失败时告警并缓存 null，单次失败不影响其他音效。
func _get_stream(sound_name: StringName) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name] as AudioStream
	var stream: AudioStream = null
	# 先按 .mp3 找，找不到再按 .wav 找（ambient 为程序合成占位，按裁决以 WAV 入库）。
	var path: String = AUDIO_DIR + String(sound_name) + ".mp3"
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	else:
		path = AUDIO_DIR + String(sound_name) + ".wav"
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager: 音频加载失败 %s（文件缺失或导入失败）" % path)
	_streams[sound_name] = stream
	return stream


## 为循环类音频启用循环：MP3 用 loop 标志；WAV 用 LOOP_FORWARD 全段循环（ambient 占位音）。
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = 0


## Events 接线表（派单口径）：
## weapon_fired → 按 GameState.current_weapon 放 rifle/rocket（枪声带音高抖动）
## weapon_reloaded → reload ｜ hit_confirmed → hitmark ｜ player_damaged → player_hurt
## enemy_died → enemy_death ｜ medkit_used → medkit ｜ night_vision_toggled → nightvision
## heli_called → helicopter（loop 总线循环）｜ mission_completed / game_over → 停全部 loop
## Sprint 2 缺口（契约无信号，见交付报告「需蜂后裁决」）：
##   explosion ← 建议信号 rpg_exploded()；footstep（loop）← 建议信号 player_moving_changed(is_moving)；
##   ui_click ← 留待 Sprint 3 菜单界面接入。
func _connect_events() -> void:
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)
	Events.hit_confirmed.connect(_on_hit_confirmed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.enemy_died.connect(_on_enemy_died)
	Events.medkit_used.connect(_on_medkit_used)
	Events.night_vision_toggled.connect(_on_night_vision_toggled)
	Events.heli_called.connect(_on_heli_called)
	Events.mission_completed.connect(_on_mission_ended)
	Events.game_over.connect(_on_game_over)


func _disconnect_events() -> void:
	Events.weapon_fired.disconnect(_on_weapon_fired)
	Events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	Events.hit_confirmed.disconnect(_on_hit_confirmed)
	Events.player_damaged.disconnect(_on_player_damaged)
	Events.enemy_died.disconnect(_on_enemy_died)
	Events.medkit_used.disconnect(_on_medkit_used)
	Events.night_vision_toggled.disconnect(_on_night_vision_toggled)
	Events.heli_called.disconnect(_on_heli_called)
	Events.mission_completed.disconnect(_on_mission_ended)
	Events.game_over.disconnect(_on_game_over)


func _on_weapon_fired(_weapon_id: StringName) -> void:
	match GameState.current_weapon:
		&"rifle":
			play_sfx(&"rifle")
		&"rpg":
			play_sfx(&"rocket")


func _on_weapon_reloaded(_reloaded_id: StringName) -> void:
	play_sfx(&"reload")


func _on_hit_confirmed(_is_headshot: bool) -> void:
	play_sfx(&"hitmark")


func _on_player_damaged(_part: StringName, _amount: float) -> void:
	play_sfx(&"player_hurt")


func _on_enemy_died(_enemy: Node) -> void:
	play_sfx(&"enemy_death")


func _on_medkit_used(_remaining: int) -> void:
	play_sfx(&"medkit")


func _on_night_vision_toggled(_enabled: bool) -> void:
	play_sfx(&"nightvision")


func _on_heli_called() -> void:
	play_loop(&"helicopter")


func _on_mission_ended() -> void:
	stop_all_loops()


func _on_game_over(_reason: StringName) -> void:
	stop_all_loops()
