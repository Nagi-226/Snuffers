extends Node3D
## 第一关材质样板与全街区覆面。仅替换显示材质；原路面、建筑与门锁碰撞保持原样。
## 与 StreetDayNightDriver 同属关卡域，沿用父关卡借用节点与延迟初始化模式。

const Layout := preload("res://scripts/levels/street_layout_test.gd")

var _street: Node3D
var _day_night: Node
var _lights: Array[SpotLight3D] = []
var _lenses: Array[StandardMaterial3D] = []
var _reflection: ReflectionProbe
var _reflection_shifted: bool = false


func _ready() -> void:
	# 仅供 tools 的同机位基线取证，在入树前设置，不改变正常关卡入口。
	if get_meta("quality_sample_disabled", false):
		return
	_street = get_parent() as Node3D
	await get_tree().process_frame # 父 builder 与昼夜驱动先完成原有几何/环境初始化。
	if not is_instance_valid(_street) or not _street.has_node("Ground/Asphalt"):
		push_error("street_quality_sample: expected the completed first street builder")
		return
	var plaster := _pbr_material("plaster", GameConfig.STREET_SAMPLE_PLASTER_TILE_M)
	var asphalt := _pbr_material("asphalt", GameConfig.STREET_SAMPLE_ASPHALT_TILE_M)
	var metal := _pbr_material("metal", GameConfig.STREET_SAMPLE_METAL_TILE_M)
	var concrete := _pbr_material("concrete", GameConfig.STREET_SAMPLE_PLASTER_TILE_M)
	if plaster == null or asphalt == null or metal == null or concrete == null:
		return
	_apply_wall_and_gate_materials(plaster, metal)
	_build_sample_ground(asphalt, concrete)
	_build_lamps(metal)
	_day_night = _street.get_node_or_null("StreetDayNightDriver")
	if _day_night != null:
		_day_night.connect("mode_changed", _on_mode_changed)
	_set_lamp_state(_day_night == null or _day_night.call("is_night"))
	_reflection = ReflectionProbe.new()
	_reflection.name = "SampleReflection"
	_reflection.size = GameConfig.STREET_SAMPLE_REFLECTION_SIZE
	_reflection.position = GameConfig.STREET_SAMPLE_REFLECTION_ORIGIN
	_reflection.box_projection = true
	_reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	_reflection.max_distance = GameConfig.STREET_SAMPLE_REFLECTION_SIZE.z
	add_child(_reflection)


func _pbr_material(kind: String, tile_m: float) -> StandardMaterial3D:
	var base := "res://assets/textures/street_sample/" + kind
	if kind == "concrete":
		base = "res://assets/textures/pbr/concrete034/concrete034"
	var color := load(base + "_color.jpg") as Texture2D
	var normal := load(base + "_normal.jpg") as Texture2D
	var rough := load(base + "_rough.jpg") as Texture2D
	if color == null or normal == null or rough == null:
		push_error("street_quality_sample: incomplete PBR texture set " + kind)
		return null
	var material := StandardMaterial3D.new()
	material.resource_name = "street_sample_" + kind
	material.albedo_texture = color
	material.normal_enabled = true
	material.normal_texture = normal
	material.normal_scale = GameConfig.STREET_SAMPLE_NORMAL_SCALE
	material.roughness_texture = rough
	material.roughness = 1.0
	# GreenMetalRust 的漆层/氧化物属于介质，不能把整张表面当作裸钢。
	material.metallic = 0.0
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / tile_m
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _apply_wall_and_gate_materials(plaster: StandardMaterial3D, metal: StandardMaterial3D) -> void:
	var meshes := _street.find_children("*", "MeshInstance3D", true, false)
	if GameConfig.STREET_SAMPLE_FULL_SCENE:
		# 全街区只扩大原建筑/门体材质范围；远景和独立模型不参与墙面分类。
		meshes.clear()
		for path in ["Buildings", "SceneGate"]:
			var scope := _street.get_node_or_null(path)
			if scope != null:
				meshes.append_array(scope.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not _in_sample(mesh.global_position.z):
			continue
		var parent_name := String(mesh.get_parent().name)
		if parent_name.begins_with("BGateLeaf_") or parent_name.begins_with("BGateBrace_") \
				or parent_name.begins_with("BGatePost_") or parent_name.begins_with("BGateBeam_") \
				or (parent_name.begins_with("Gar_") and parent_name.ends_with("_Shutter")):
			mesh.material_override = metal
			mesh.set_meta("quality_sample_surface", "metal")
			continue
		var structural_wall := parent_name.begins_with("Bldg_") \
				and not parent_name.contains("FLOOR") and not parent_name.contains("ROOF") \
				and not parent_name.contains("SLAB") and not parent_name.contains("RAMP") \
				and not parent_name.contains("POST") and not parent_name.contains("RAIL") \
				and not parent_name.contains("_JAMB_") and not parent_name.contains("_LINTEL") \
				and not parent_name.contains("_HR") \
				and not parent_name.contains("LANDING") and not parent_name.contains("_S1") \
				and not parent_name.contains("_S2")
		structural_wall = structural_wall or (parent_name.begins_with("Gar_") \
				and (parent_name.contains("_Wall") or parent_name.ends_with("_Upper") \
				or parent_name.ends_with("_Lintel") or parent_name.ends_with("_RearLintel") \
				or parent_name.ends_with("_JambN") or parent_name.ends_with("_JambS")))
		for index in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index)
			if source == null:
				continue
			var replacement: StandardMaterial3D
			var kind := ""
			if source.resource_name == "shutter_metal":
				replacement = metal
				kind = "metal"
			elif source.resource_name == "plaster" or structural_wall:
				replacement = plaster.duplicate() as StandardMaterial3D
				if source is StandardMaterial3D:
					replacement.albedo_color = (source as StandardMaterial3D).albedo_color
				kind = "wall"
			if replacement != null:
				mesh.set_surface_override_material(index, replacement)
				mesh.set_meta("quality_sample_surface", kind)


func _in_sample(z: float) -> bool:
	return GameConfig.STREET_SAMPLE_FULL_SCENE \
		or (z >= GameConfig.STREET_SAMPLE_Z_MIN and z <= GameConfig.STREET_SAMPLE_Z_MAX)


func _build_sample_ground(asphalt: StandardMaterial3D, concrete: StandardMaterial3D) -> void:
	if GameConfig.STREET_SAMPLE_FULL_SCENE:
		# 按 builder 已完成的顶面取尺寸，覆盖街道与铺装巷院；不重建碰撞。
		for body in _street.get_node("Ground").get_children():
			var part := String(body.name)
			var road := part == "Asphalt" or part == "CrossAsphalt" or part == "SouthAsphalt"
			var sidewalk := part.begins_with("Sidewalk_") or part.begins_with("CrossSidewalk_") \
				or part.begins_with("SouthSidewalk_")
			var paving := part.begins_with("Alley_")
			if not road and not sidewalk and not paving:
				continue
			for node in body.get_children():
				var source := node as MeshInstance3D
				if source == null or not source.mesh is BoxMesh:
					continue
				var box := source.mesh as BoxMesh
				var top := source.global_transform * Vector3(0, box.size.y * 0.5, 0)
				top += _street.global_basis.y * GameConfig.STREET_SAMPLE_SURFACE_OFFSET
				var surface_name := "SampleRoad" if part == "Asphalt" else "Sample" + part
				_add_surface(surface_name, Vector2(box.size.x, box.size.z),
					global_transform.affine_inverse() * top, asphalt if road else concrete, "road")
		return
	var length := GameConfig.STREET_SAMPLE_Z_MAX - GameConfig.STREET_SAMPLE_Z_MIN
	var center_z := (GameConfig.STREET_SAMPLE_Z_MAX + GameConfig.STREET_SAMPLE_Z_MIN) * 0.5
	var half_width: float = Layout.STREET["half_width"]
	var walkway_width: float = Layout.STREET["kerb"] - half_width
	_add_surface("SampleRoad", Vector2(half_width * 2.0, length),
		Vector3(0, GameConfig.STREET_SAMPLE_SURFACE_OFFSET, center_z), asphalt, "road")
	for side in [-1.0, 1.0]:
		_add_surface("SampleSidewalk_" + ("W" if side < 0 else "E"), Vector2(walkway_width, length),
			Vector3(side * (half_width + walkway_width * 0.5),
				Layout.STREET["walk_h"] + GameConfig.STREET_SAMPLE_SURFACE_OFFSET, center_z), concrete, "road")


func _add_surface(node_name: String, size: Vector2, center: Vector3, material: StandardMaterial3D, kind: String) -> void:
	var surface := MeshInstance3D.new()
	surface.name = node_name
	var plane := PlaneMesh.new()
	plane.size = size
	surface.mesh = plane
	surface.material_override = material
	surface.position = center
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.set_meta("quality_sample_surface", kind)
	add_child(surface)


func _build_lamps(metal: StandardMaterial3D) -> void:
	var lamps := Node3D.new()
	lamps.name = "StreetLamps"
	add_child(lamps)
	for side in [-1.0, 1.0]:
		for index in GameConfig.STREET_LAMP_COUNT_PER_SIDE:
			var lamp := StaticBody3D.new()
			lamp.name = "Lamp_%s_%d" % ["W" if side < 0 else "E", index]
			lamp.position = Vector3(side * GameConfig.STREET_LAMP_X_M, Layout.STREET["walk_h"],
				GameConfig.STREET_LAMP_START_Z - index * GameConfig.STREET_LAMP_SPACING_M)
			lamps.add_child(lamp)
			var height := GameConfig.STREET_LAMP_HEIGHT_M
			var radius := GameConfig.STREET_LAMP_POLE_RADIUS_M
			var pole := CylinderMesh.new()
			pole.top_radius = radius * 0.7
			pole.bottom_radius = radius
			pole.height = height
			pole.radial_segments = 16
			_add_lamp_mesh(lamp, "Pole", pole, Vector3(0, height * 0.5, 0), metal)
			var base := CylinderMesh.new()
			base.top_radius = radius * 2.0
			base.bottom_radius = radius * 3.0
			base.height = radius * 4.0
			base.radial_segments = 16
			_add_lamp_mesh(lamp, "Foot", base, Vector3(0, base.height * 0.5, 0), metal)
			var shape := CollisionShape3D.new()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = radius
			cylinder.height = height
			shape.shape = cylinder
			shape.position.y = height * 0.5
			lamp.add_child(shape)
			var arm := GameConfig.STREET_LAMP_ARM_M
			var arm_mesh := BoxMesh.new()
			arm_mesh.size = Vector3(arm, radius * 2.0, radius * 2.0)
			_add_lamp_mesh(lamp, "Arm", arm_mesh, Vector3(-side * arm * 0.5, height - radius * 3.0, 0), metal)
			var head := BoxMesh.new()
			head.size = Vector3(arm * 0.45, radius * 2.5, arm * 0.75)
			var head_center := Vector3(-side * arm, height - radius * 3.0, 0)
			_add_lamp_mesh(lamp, "Head", head, head_center, metal)
			var lens_material := StandardMaterial3D.new()
			lens_material.albedo_color = GameConfig.STREET_LAMP_LIGHT_COLOR
			lens_material.emission_enabled = true
			lens_material.emission = GameConfig.STREET_LAMP_LIGHT_COLOR
			_lenses.append(lens_material)
			var lens := BoxMesh.new()
			lens.size = Vector3(head.size.x * 0.85, radius * 0.25, head.size.z * 0.85)
			_add_lamp_mesh(lamp, "Lens", lens, head_center - Vector3(0, head.size.y * 0.5, 0), lens_material)
			var light := SpotLight3D.new()
			light.name = "StreetLight"
			light.position = head_center - Vector3(0, head.size.y, 0)
			light.rotation_degrees.x = -90.0
			light.light_color = GameConfig.STREET_LAMP_LIGHT_COLOR
			light.spot_range = GameConfig.STREET_LAMP_RANGE_M
			light.spot_angle = GameConfig.STREET_LAMP_ANGLE_DEG
			light.shadow_enabled = true
			light.distance_fade_enabled = true
			light.distance_fade_begin = GameConfig.STREET_LAMP_FADE_BEGIN_M
			light.distance_fade_length = GameConfig.STREET_LAMP_FADE_LENGTH_M
			light.distance_fade_shadow = GameConfig.STREET_LAMP_SHADOW_FADE_M
			lamp.add_child(light)
			_lights.append(light)


func _add_lamp_mesh(parent: Node3D, node_name: String, mesh: Mesh, center: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)


func _set_lamp_state(night: bool) -> void:
	for light in _lights:
		light.light_energy = GameConfig.STREET_LAMP_ENERGY if night else 0.0
	for lens in _lenses:
		lens.emission_energy_multiplier = GameConfig.STREET_LAMP_ENERGY if night else 0.0


func _on_mode_changed(_mode: int) -> void:
	_set_lamp_state(_day_night.call("is_night"))
	if _reflection != null:
		# UPDATE_ONCE 在 transform 改变时重拍。两个定点交替，不积累位移、不逐帧重拍。
		_reflection_shifted = not _reflection_shifted
		_reflection.position = GameConfig.STREET_SAMPLE_REFLECTION_ORIGIN \
			+ Vector3(GameConfig.STREET_SAMPLE_SURFACE_OFFSET if _reflection_shifted else 0.0, 0, 0)
