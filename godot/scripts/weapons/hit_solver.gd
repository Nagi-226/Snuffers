## HitSolver — 命中解算静态工具（W2 内部共用：步枪 hitscan 与 RPG 爆炸）
##
## 解耦约定（AGENTS.md 约束 #3 + 派单铁律「禁止直接引用 enemies 域节点」）：
## 不 preload、不类名引用任何 enemies/levels 域脚本，只对物理查询返回的 collider
## 做鸭子类型探测（has_method / is_in_group / has_meta）。与 Jeh3no 脚手架
## projectile_script.gd 的 is_in_group + has_method 模式一致（见 ATTRIBUTION.md）。
##
## 跨域接口约定（已与蜂后报告，待 W3/W4 对齐）：
## - 可伤害目标：实现 take_damage(amount: float, is_headshot: bool)；
##   命中头部 hitbox 节点时，伤害接收者可为其祖先（沿 parent 链向上找）。
## - 头部 hitbox：节点元数据 "hit_part" = &"head"。
## - 狙击手：group "sniper"（命中即 RIFLE_DMG_VS_SNIPER 固定伤害）。
## - 碉堡：group "bunker"（步枪跳弹；RPG 爆径+bonus 内 destroy()）。
## - 金属表面判定（2026-10-19 机主立项：弹着火花用）：沿 collider 祖先链节点名
##   小写匹配 GameConfig.BULLET_METAL_KEYWORDS（自行车/铁护栏/栏杆/篮架/卷帘门等）。
extends RefCounted

static var _visual_triangle_meshes: Dictionary = {} ## Mesh 资源 → BVH；不保存场景节点引用


## 显示用表皮锚点：简化碰撞盒可在模型内，沿命中法线找最近真实三角面。
## 接收者自身有网格时只查自身；无网格的单碰撞代理才查同容器模型。
## 原语墙面保留物理命中；不修改弹道或伤害。
static func resolve_visual_surface(pos: Vector3, normal: Vector3, receiver: Node3D) -> Dictionary:
	if not is_instance_valid(receiver) or receiver.is_queued_for_deletion() \
			or not receiver.is_inside_tree() or normal.is_zero_approx():
		return {}
	var meshes: Array[MeshInstance3D] = []
	_append_visual_meshes(receiver, meshes)
	var parent := receiver.get_parent()
	var own_geometry := receiver is MeshInstance3D \
		or not receiver.find_children("*", "MeshInstance3D", true, false).is_empty()
	if not own_geometry and parent != null and parent != receiver.get_tree().root \
			and parent != receiver.get_tree().current_scene:
		var bodies := 0
		for child in parent.get_children():
			if child is CollisionObject3D:
				bodies += 1
		# 建筑集合等多接收体容器不能借用兄弟楼的立面；车辆代理仅有一个碰撞体。
		if bodies == 1 and receiver is CollisionObject3D:
			for sibling in parent.get_children():
				if sibling == receiver:
					continue
				var path := sibling.scene_file_path.to_lower()
				if sibling is MeshInstance3D or path.ends_with(".glb") or path.ends_with(".gltf"):
					_append_visual_meshes(sibling, meshes)
	if meshes.is_empty():
		return {}
	normal = normal.normalized()
	var reach := 0.0
	for instance in meshes:
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		# 用候选模型包围盒计算外端，避免固定距离漏掉长车或扫入其他场景。
		reach = maxf(reach, pos.distance_to(bounds.get_center()) + bounds.size.length())
	if is_zero_approx(reach):
		return {}
	var endpoints := [pos + normal * reach, pos - normal * reach]
	var nearest := INF
	var result := {}
	for instance in meshes:
		var mesh := instance.mesh
		if not _visual_triangle_meshes.has(mesh):
			_visual_triangle_meshes[mesh] = mesh.generate_triangle_mesh()
		var triangles := _visual_triangle_meshes[mesh] as TriangleMesh
		if triangles == null or instance.global_basis.determinant() == 0.0:
			continue
		var inverse := instance.global_transform.affine_inverse()
		var begin := inverse * pos
		# 两侧各用一次 BVH 首命中，再按物理点距离选近面，避免开放房间借用对墙。
		for endpoint: Vector3 in endpoints:
			var end := inverse * endpoint
			if begin == end:
				continue
			var hit := triangles.intersect_segment(begin, end)
			if hit.is_empty():
				continue
			var point: Vector3 = instance.global_transform * hit.position
			var distance := pos.distance_squared_to(point)
			if distance >= nearest:
				continue
			# 法线用逆转置转换，兼容导入模型缩放；朝物理命中法线避免反向贴花。
			var outward: Vector3 = (instance.global_basis.inverse().transposed() * hit.normal).normalized()
			if outward.is_zero_approx():
				continue
			if outward.dot(normal) < 0.0:
				outward = -outward
			nearest = distance
			result = {"position": point, "normal": outward}
	return result


static func _append_visual_meshes(from_node: Node, meshes: Array[MeshInstance3D]) -> void:
	var candidates: Array[Node] = from_node.find_children("*", "MeshInstance3D", true, false)
	if from_node is MeshInstance3D:
		candidates.append(from_node)
	for candidate in candidates:
		var instance := candidate as MeshInstance3D
		if instance.mesh is ArrayMesh and instance.is_visible_in_tree() \
				and not instance.is_queued_for_deletion():
			meshes.append(instance)


## 是否金属表面：祖先链任一节点名小写后含关键词列表任一项。
static func is_metal_surface(collider: Object) -> bool:
	var node := collider as Node
	while node != null:
		var lower := String(node.name).to_lower()
		for kw: String in GameConfig.BULLET_METAL_KEYWORDS:
			if lower.contains(kw):
				return true
		node = node.get_parent()
	return false


## 沿 collider 向上找最近实现 take_damage(amount, is_headshot) 的节点；找不到返回 null。
static func find_damageable(collider: Object) -> Node:
	var node := collider as Node
	while node != null:
		if node.has_method(&"take_damage"):
			return node
		node = node.get_parent()
	return null


## 沿 collider 向上找第一个属于指定 group 的节点；找不到返回 null。
static func find_group_ancestor(collider: Object, group: StringName) -> Node:
	var node := collider as Node
	while node != null:
		if node.is_in_group(group):
			return node
		node = node.get_parent()
	return null


## 头部 hitbox 判定：命中节点自身带 "hit_part" = &"head" 元数据（W3 挂接约定）。
static func is_headshot(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return false
	return node.has_meta(&"hit_part") and node.get_meta(&"hit_part") == &"head"


## 收集持枪者碰撞 RID 链（射线/爆炸排除自身）。
## 武器场景按约定挂在持枪者（Player）节点树下，沿 parent 链收集全部 CollisionObject3D；
## 属场景内组合探测，非跨模块 get_node 引用。
static func collect_owner_rids(from_node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	var node := from_node.get_parent()
	while node != null:
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
		node = node.get_parent()
	return rids
