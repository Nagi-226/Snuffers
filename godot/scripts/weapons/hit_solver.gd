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
extends RefCounted


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
