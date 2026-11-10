extends SceneTree

const ASSETS := [
	["res://addons/community_weapons/mpx_tactical.glb", 0.65],
	["res://addons/community_weapons/g17_gen5_olight.glb", 0.20],
]
const MPX_GROUPS := ["Body", "HolographicSight", "Foregrip", "InfraredModule", "WeaponLight"]

var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void:
		push_error("community asset test timed out")
		quit(1))
	for asset: Array in ASSETS:
		_assert(FileAccess.file_exists(asset[0]), "prepared asset exists: " + asset[0])
	if _failures > 0:
		_finish()
		return
	for asset: Array in ASSETS:
		_check_glb_container(asset[0])
		var packed := load(asset[0]) as PackedScene
		_assert(packed != null, "Godot imports prepared GLB as a scene: " + asset[0])
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		_assert(model != null, "prepared asset instantiates: " + asset[0])
		if model == null:
			continue
		root.add_child(model)
		var bounds := _bounds(model)
		var expected: float = asset[1]
		_assert(bounds.size.z > expected * 0.8 and bounds.size.z < expected * 1.2, "asset uses the specified meter-scale working length: " + asset[0])
		_assert(bounds.size.z > bounds.size.x and bounds.size.z > bounds.size.y, "asset long axis is Godot Z: " + asset[0])
		_assert(bounds.get_center().length() < expected * 0.05, "prepared geometry is centered: " + asset[0])
		var triangles := 0
		var textures := 0
		for instance in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := instance as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: Variant = arrays[Mesh.ARRAY_INDEX]
				triangles += int(indices.size() / 3) if indices is PackedInt32Array and not indices.is_empty() else int(vertices.size() / 3)
				var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
				_assert(material != null, "mesh surface imports a valid PBR material")
				if material == null:
					continue
				for field in ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture", "ao_texture", "emission_texture"]:
					var texture := material.get(field) as Texture2D
					if texture == null:
						continue
					textures += 1
					_assert(texture.get_width() > 0 and texture.get_height() > 0 and maxi(texture.get_width(), texture.get_height()) <= 2048, "imported %s is nonempty and at most 2048 pixels" % field)
		_assert(triangles > 0, "actual imported geometry contains triangles: " + asset[0])
		_assert(textures > 0, "actual imported materials contain usable textures: " + asset[0])
		if asset[0].ends_with("mpx_tactical.glb"):
			_check_mpx_groups(model, expected)
		print("COMMUNITY_ASSET_STATS ", asset[0], " triangles=", triangles, " textures=", textures, " bounds=", bounds)
		model.queue_free()
		await process_frame
	_finish()


func _check_glb_container(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "prepared GLB can be read: " + path)
	if file == null:
		return
	_assert(file.get_32() == 0x46546c67 and file.get_32() == 2, "prepared asset is a glTF 2 binary container")
	var total_length := file.get_32()
	_assert(total_length == file.get_length(), "GLB length matches the complete file")
	var document: Dictionary = {}
	while file.get_position() + 8 <= file.get_length():
		var length := file.get_32()
		var kind := file.get_32()
		if file.get_position() + length > file.get_length():
			_assert(false, "GLB chunk stays inside the file")
			break
		var data := file.get_buffer(length)
		if kind == 0x4e4f534a:
			var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
			if parsed is Dictionary:
				document = parsed
	file.close()
	_assert(not document.is_empty(), "GLB contains a valid JSON chunk")
	if document.is_empty():
		return
	var buffers: Array = document.get("buffers", [])
	var images: Array = document.get("images", [])
	_assert(not buffers.is_empty() and not images.is_empty(), "GLB embeds geometry and image data")
	for buffer: Dictionary in buffers:
		_assert(not buffer.has("uri"), "GLB geometry has no external buffer dependency")
	var views: Array = document.get("bufferViews", [])
	for image: Dictionary in images:
		var view_index: int = image.get("bufferView", -1)
		_assert(not image.has("uri") and view_index >= 0 and view_index < views.size(), "GLB texture is embedded without an external image dependency")


func _check_mpx_groups(model: Node3D, working_length: float) -> void:
	var body := model.find_child("Body", true, false) as Node3D
	for name in MPX_GROUPS:
		var group := model.find_child(name, true, false) as Node3D
		_assert(group != null and not group is MeshInstance3D, "MPX has the dedicated Node3D component group: " + name)
		if group == null:
			continue
		var bounds := _bounds(group)
		_assert(bounds.size.length() > 0.001, "MPX component has real geometry: " + name)
		if name != "Body" and body != null:
			var body_bounds := _bounds(body)
			_assert(body_bounds.grow(working_length * 0.35).has_point(bounds.get_center()), "MPX component is assembled near the body: " + name)
	var foregrip := model.find_child("Foregrip", true, false) as Node3D
	if body != null and foregrip != null:
		var body_bounds := _bounds(body)
		var grip_center := _bounds(foregrip).get_center()
		var relative_z := grip_center.z - body_bounds.get_center().z
		_assert(absf(relative_z + 0.245) <= 0.015, "MPX foregrip geometry center moves forward to Z=-0.245m relative to the body center")
		_assert(grip_center.z - body_bounds.position.z >= 0.045 and relative_z < 0.0, "MPX foregrip stays in the forward handguard with at least 45mm of clearance from the body front")
	_check_mpx_optical_glass(model)


func _check_mpx_optical_glass(model: Node3D) -> void:
	var glass_seen := false
	var glass_valid := true
	var glass_triangles := 0
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as BaseMaterial3D
			if material == null or material.resource_name != "EotechOpticalGlass":
				continue
			glass_seen = true
			glass_valid = glass_valid and material.albedo_color.a <= 0.15 and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var arrays := instance.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			glass_triangles += int(indices.size() / 3) if indices is PackedInt32Array and not indices.is_empty() else int(vertices.size() / 3)
	_assert(glass_seen, "MPX imports the dedicated EotechOpticalGlass lens material")
	_assert(glass_seen and glass_valid, "MPX optical glass uses alpha at most 0.15 with transparency enabled")
	_assert(glass_triangles == 12, "MPX transparent optical glass covers exactly the twelve source lens triangles")


func _bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := instance.global_transform * vertex
				if first:
					bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					bounds = bounds.expand(point)
	return bounds


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("COMMUNITY_ASSETS assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
