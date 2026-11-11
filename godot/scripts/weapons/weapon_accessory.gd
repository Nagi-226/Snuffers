## G17/MPX实际配件出口；世界光束和灯光与枪臂显示变换分别更新。
extends Node

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")

@export var laser_origin_path: NodePath
@export var flashlight_origin_path: NodePath

var _weapon: WeaponController
var _laser_origin: Marker3D
var _flashlight_origin: Marker3D
var _laser_direction_local := Vector3.FORWARD
var _flashlight_direction_local := Vector3.FORWARD
var _laser_beam: MeshInstance3D
var _laser_dot: MeshInstance3D
var _laser_cylinder: CylinderMesh
var _flashlight: SpotLight3D


func _ready() -> void:
	# Player priority=1先完成近墙显示压缩，再由实际出口重建米制世界效果。
	process_priority = 2
	_weapon = get_parent() as WeaponController
	if _weapon == null or _weapon.weapon_data == null:
		push_error("weapon accessory requires its actual weapon controller and data")
		set_process(false)
		return
	_laser_origin = _weapon.get_node_or_null(laser_origin_path) as Marker3D
	_flashlight_origin = _weapon.get_node_or_null(flashlight_origin_path) as Marker3D
	var aim_reference := _weapon.get_node_or_null(^"ViewModel/OpticAim") as Marker3D
	if _laser_origin == null or _flashlight_origin == null or aim_reference == null:
		push_error("weapon accessory could not resolve its actual emitter markers and sight reference")
		set_process(false)
		return
	# 源静止几何确定25m归零角；后续只跟实际出口旋转，不追固定屏幕瞄点。
	_laser_direction_local = (_laser_origin.to_local(aim_reference.global_position) + Vector3.FORWARD * GameConfig.WEAPON_LASER_ZERO_DISTANCE).normalized()
	_flashlight_direction_local = (_flashlight_origin.to_local(aim_reference.global_position) + Vector3.FORWARD * GameConfig.WEAPON_LASER_ZERO_DISTANCE).normalized()
	_build_world_effects()


func _build_world_effects() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GameConfig.WEAPON_LASER_COLOR
	material.emission_enabled = true
	material.emission = GameConfig.WEAPON_LASER_COLOR
	material.emission_energy_multiplier = GameConfig.WEAPON_LASER_EMISSION_ENERGY
	_laser_cylinder = CylinderMesh.new()
	_laser_cylinder.top_radius = GameConfig.WEAPON_LASER_WIDTH * 0.5
	_laser_cylinder.bottom_radius = _laser_cylinder.top_radius
	_laser_beam = MeshInstance3D.new()
	_laser_beam.name = "AccessoryLaserBeam"
	_laser_beam.mesh = _laser_cylinder
	_laser_beam.material_override = material
	_laser_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prepare_world_effect(_laser_beam)
	var sphere := SphereMesh.new()
	sphere.radius = GameConfig.WEAPON_LASER_DOT_RADIUS
	sphere.height = sphere.radius * 2.0
	_laser_dot = MeshInstance3D.new()
	_laser_dot.name = "AccessoryLaserDot"
	_laser_dot.mesh = sphere
	_laser_dot.material_override = material
	_laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prepare_world_effect(_laser_dot)
	_flashlight = SpotLight3D.new()
	_flashlight.name = "AccessoryFlashlight"
	_flashlight.light_color = GameConfig.WEAPON_FLASHLIGHT_COLOR
	_flashlight.light_energy = GameConfig.WEAPON_FLASHLIGHT_ENERGY
	_flashlight.spot_range = GameConfig.G17_FLASHLIGHT_RANGE if _weapon.weapon_data.weapon_id == &"g17" else GameConfig.MPX_FLASHLIGHT_RANGE
	_flashlight.spot_angle = GameConfig.WEAPON_FLASHLIGHT_ANGLE
	_flashlight.spot_attenuation = GameConfig.WEAPON_FLASHLIGHT_ATTENUATION
	_flashlight.shadow_enabled = true
	_prepare_world_effect(_flashlight)


func _prepare_world_effect(effect: Node3D) -> void:
	effect.top_level = true
	effect.set_meta(GameConfig.VIEWMODEL_WORLD_FX_META, true)
	effect.visible = false
	# 普通Node父节点切断Node3D可见性继承；枪臂被近墙隐藏时不关世界灯。
	add_child(effect)


func _process(_delta: float) -> void:
	if _laser_beam == null:
		return
	var current := _weapon._is_current_weapon()
	var mode: StringName = GameState.weapon_accessory_modes.get(_weapon.weapon_data.weapon_id, GameConfig.WEAPON_ACCESSORY_DEFAULT_MODE)
	var laser_on := current and mode in [&"laser", &"combined"]
	_flashlight.visible = current and mode in [&"flashlight", &"combined"]
	_laser_beam.visible = laser_on
	_laser_dot.visible = false
	if not current:
		return
	if _flashlight.visible:
		_flashlight.visible = not _origin_is_blocked(_flashlight_origin.global_position)
		var basis := _flashlight_origin.global_basis.orthonormalized()
		var light_direction := basis * _flashlight_direction_local
		_flashlight.global_transform = Transform3D(basis, _flashlight_origin.global_position)
		_flashlight.look_at(_flashlight_origin.global_position + light_direction, basis.y)
	if not laser_on:
		return
	var from := _laser_origin.global_position
	var direction := _laser_origin.global_basis.orthonormalized() * _laser_direction_local
	var to := from + direction * GameConfig.WEAPON_LASER_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = HitSolver.collect_owner_rids(self)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var hit := _weapon.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = hit.position
		if (hit.normal as Vector3).is_zero_approx() or from.is_equal_approx(to):
			_laser_beam.visible = false
			return
		var dot_scale := _dot_display_scale(to)
		_laser_dot.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * dot_scale), to)
		_laser_dot.visible = true
	var motion := to - from
	if motion.is_zero_approx():
		_laser_beam.visible = false
		return
	_laser_cylinder.height = motion.length()
	_laser_beam.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, motion.normalized())), from + motion * 0.5)


func _origin_is_blocked(origin: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = origin
	query.exclude = HitSolver.collect_owner_rids(self)
	query.collide_with_areas = false
	return not _weapon.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


func _dot_display_scale(position: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(position):
		return 1.0
	var center := camera.unproject_position(position)
	var edge := camera.unproject_position(position + camera.global_basis.x.normalized() * GameConfig.WEAPON_LASER_DOT_RADIUS)
	var radius_pixels := center.distance_to(edge)
	if is_zero_approx(radius_pixels):
		return 1.0
	# 只放大世界红点的显示尺寸；物理命中中心、4mm基准和光束终点不变。
	return maxf(1.0, GameConfig.WEAPON_LASER_DOT_MIN_DIAMETER_PIXELS * 0.5 / radius_pixels)
