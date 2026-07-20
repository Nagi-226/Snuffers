## RPGController — 火箭筒投射物武器（W2 火力蜂）
##
## 参数基准（§7 对照表 G2 行）：初速 120 · 重力 9.8 · 爆径 10 · 5 发 · 最大射程 300。
## 缺陷修正（§6 处置清单）：网页版 RPG 后坐永不触发（recoilOffset 仅步枪路径设置，
## index.html L2959 vs fireRPG L3077+）——Godot 版 RPG 经 _apply_recoil() 走与步枪
## 相同的后坐状态机，参数独立（WeaponData recoil_* 字段，RPG 相机上跳值为契约缺口暂定值）。
##
## 弹药：无弹匣概念（events.gd 契约注明「RPG 无换弹事件」），GameState.rpg_ammo 总数制，
## ammo_changed 的 reserve 恒为 -1。半自动：每次左键按下击发一发（网页版无射速限制）。
extends WeaponController


## 半自动：左键按下边沿击发（全自动 tick 不适用于 RPG，基类 _tick_weapon 保持空实现）。
func _on_trigger_pressed() -> void:
	if GameState.rpg_ammo <= 0:
		# 网页版提示文案（index.html L3079）。
		Events.message_posted.emit("火箭筒弹药耗尽")
		return

	GameState.rpg_ammo -= 1
	Events.ammo_changed.emit(&"rpg", GameState.rpg_ammo, -1)
	Events.weapon_fired.emit(&"rpg")
	_apply_recoil()

	var projectile: Node3D = weapon_data.projectile_scene.instantiate()
	# 投射物挂到关卡根（武器随玩家移动，投射物需独立存在于世界空间）。
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_tree().root
	container.add_child(projectile)
	projectile.global_transform = global_transform
	projectile.setup(
		-global_transform.basis.z,
		HitSolver.collect_owner_rids(self),
		weapon_data
	)
