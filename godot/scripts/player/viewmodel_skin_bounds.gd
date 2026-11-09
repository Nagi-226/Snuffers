## 近墙检测专用：缓存每个 skin bind 的顶点界限，逐帧按真实骨骼姿态变换。
## 不用未蒙皮的厘米级 mesh AABB，也不逐帧调用 GPU 读回/bake。
extends RefCounted

var _cache: Dictionary = {}


func get_pose_bounds(instance: MeshInstance3D) -> AABB:
	var reference := instance.get_skin_reference()
	if reference == null:
		return instance.get_aabb()
	var skin := reference.get_skin()
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	if skin == null or skeleton == null:
		return instance.get_aabb()
	if not _cache.has(instance) or _cache[instance].mesh != instance.mesh or _cache[instance].skin != skin:
		_cache[instance] = _build_bounds(instance.mesh, skin, skeleton)
	var data: Dictionary = _cache[instance]
	var bounds: AABB = data.plain
	var has_bounds: bool = data.has_plain
	for entry: Dictionary in data.entries:
		# 与 Godot Skeleton3D 上传的 bone_global_pose * bind_pose 相同。
		# bind_pose 已在缓存顶点上应用；这些盒子的并集包含全部加权顶点。
		var posed: AABB = skeleton.get_bone_global_pose(entry.bone) * entry.bounds
		bounds = bounds.merge(posed) if has_bounds else posed
		has_bounds = true
	return bounds if has_bounds else instance.get_aabb()


func _build_bounds(mesh: Mesh, skin: Skin, skeleton: Skeleton3D) -> Dictionary:
	var bind_bounds: Array[AABB] = []
	bind_bounds.resize(skin.get_bind_count())
	var active := PackedByteArray()
	active.resize(skin.get_bind_count())
	var plain := AABB()
	var has_plain := false
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			for vertex in vertices:
				plain = plain.expand(vertex) if has_plain else AABB(vertex, Vector3.ZERO)
				has_plain = true
			continue
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per_vertex: int = bones.size() / vertices.size()
		for index in vertices.size():
			var vertex := vertices[index]
			var influenced := false
			for influence in per_vertex:
				var offset := index * per_vertex + influence
				if offset >= weights.size() or weights[offset] <= 0.0:
					continue
				var bind := bones[offset]
				if bind < 0 or bind >= skin.get_bind_count():
					continue
				var local: Vector3 = skin.get_bind_pose(bind) * vertex
				bind_bounds[bind] = bind_bounds[bind].expand(local) if active[bind] else AABB(local, Vector3.ZERO)
				active[bind] = 1
				influenced = true
			if not influenced:
				plain = plain.expand(vertex) if has_plain else AABB(vertex, Vector3.ZERO)
				has_plain = true
	var entries: Array[Dictionary] = []
	for bind in skin.get_bind_count():
		if not active[bind]:
			continue
		var bone := skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
		if bone >= 0 and bone < skeleton.get_bone_count():
			entries.append({"bone": bone, "bounds": bind_bounds[bind]})
	return {"mesh": mesh, "skin": skin, "entries": entries, "plain": plain, "has_plain": has_plain}
