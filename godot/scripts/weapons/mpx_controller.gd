## SIG MPX：复用长枪命中与真实弹匣，三档击发仅由当前武器消费。
## 与 EM-127M 同样保留物理帧冷却余量，使 850 RPM 不被 60Hz 量化降速。
extends RifleController

const RETICLE_TEXTURE := preload("res://addons/community_weapons/mpx_reticle_red.png")


func _ready() -> void:
	super()
	_configure_reticle()
	Events.fire_mode_changed.connect(_on_fire_mode_changed)


func _configure_reticle() -> void:
	var crosshair := _weapon_node.find_child("HolographicSightPart1", true, false) as MeshInstance3D
	if crosshair == null or crosshair.mesh == null:
		push_error("mpx: source crosshair mesh is missing")
		return
	var source := crosshair.get_active_material(0) as BaseMaterial3D
	if source == null:
		push_error("mpx: source crosshair material is missing")
		return
	# 只覆盖此实例的材质；源镜片、网格UV和配件方向保持原样。
	var material := source.duplicate() as BaseMaterial3D
	material.albedo_texture = RETICLE_TEXTURE
	material.albedo_color = GameConfig.MPX_RETICLE_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = GameConfig.MPX_RETICLE_COLOR
	material.emission_energy_multiplier = GameConfig.MPX_RETICLE_EMISSION_ENERGY
	crosshair.set_surface_override_material(0, material)


func _exit_tree() -> void:
	Events.fire_mode_changed.disconnect(_on_fire_mode_changed)
	super()


func _on_trigger_pressed() -> void:
	match _current_fire_mode():
		&"semi":
			if _fire_cooldown <= 0.0:
				_try_fire()
		&"burst":
			# 未完成的三发序列不能被重按续长；松开扳机仍完成原序列。
			if not _is_reloading and _burst_left == 0 and _fire_cooldown <= 0.0:
				_burst_left = 3


func _tick_weapon(delta: float) -> void:
	_fire_cooldown -= maxf(delta, 0.0)
	var mode := _current_fire_mode()
	if _is_reloading or (mode != &"auto" and mode != &"burst"):
		_burst_left = 0
		_fire_cooldown = maxf(_fire_cooldown, 0.0)
		return
	var firing := _trigger_held if mode == &"auto" else _burst_left > 0
	if not firing:
		_fire_cooldown = maxf(_fire_cooldown, 0.0)
		return
	while _fire_cooldown <= 0.0:
		var remainder := _fire_cooldown
		if not _try_fire():
			_burst_left = 0
			_fire_cooldown = 0.0
			return
		_fire_cooldown += remainder
		if mode == &"burst":
			_burst_left -= 1
			if _burst_left <= 0:
				return


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id == weapon_data.weapon_id:
		_burst_left = 0
		if _current_fire_mode() != &"auto":
			_trigger_held = false
	super._on_reload_started(weapon_id)


func _on_weapon_switched(weapon_id: StringName) -> void:
	_burst_left = 0
	_trigger_held = false
	_fire_cooldown = 0.0
	super._on_weapon_switched(weapon_id)


func _on_fire_mode_changed(weapon_id: StringName, _mode: StringName) -> void:
	if weapon_id == weapon_data.weapon_id:
		_burst_left = 0
		_trigger_held = false
		_fire_cooldown = 0.0
