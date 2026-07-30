## DayNightDemoController — 演示场景专用控制器（W7 昼夜域）
##
## 仅用于 day_night_demo.tscn 的独立测试，不进入正式游戏流程。
## 职责：T 键切换昼夜模式、简易相机、UI 提示、NightVisionOverlay 接线。
extends Node

@onready var _day_night: Node = $"../DayNightController"
@onready var _nv_overlay: CanvasLayer = $"../NightVisionOverlay"
@onready var _camera: Camera3D = $"../Camera3D"
@onready var _info_label: Label = $"../UI/InfoLabel"

var _pitch: float = -0.3
var _yaw: float = 0.0


func _ready() -> void:
	# 将 DayNightController 引用注入 NightVisionOverlay（限制白天不可用）。
	if _nv_overlay.has_method("set") or "day_night_ref" in _nv_overlay:
		_nv_overlay.day_night_ref = _day_night
	# 监听模式切换以刷新 UI。
	_day_night.mode_changed.connect(_on_mode_changed)
	_update_label()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.003
		_pitch = clampf(_pitch - motion.relative.y * 0.003, -1.4, 1.4)
		_camera.rotation.y = _yaw
		_camera.rotation.x = _pitch
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.physical_keycode:
			KEY_T:
				_day_night.toggle_mode()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	# 简易 WASD 飞行相机（演示用，无碰撞）。
	var speed := 15.0 * delta
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		dir.y += 1.0
	if dir != Vector3.ZERO:
		dir = dir.normalized()
		_camera.position += (_camera.global_transform.basis * dir) * speed


func _on_mode_changed(_new_mode: int) -> void:
	_update_label()


func _update_label() -> void:
	var mode_str := "NIGHT" if _day_night.is_night() else "DAY"
	_info_label.text = "[T] Toggle Day/Night  |  [N] Night Vision (night only)  |  [WASD+QE] Fly  |  [Esc] Release Mouse\nMode: %s" % mode_str
