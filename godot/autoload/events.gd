## Events — 全局信号总线（Autoload 单例）
##
## AGENTS.md 约束 #3：场景通信只走本总线，禁止跨模块直接 get_node 引用其他模块节点。
## 新增/修改信号必须先改本契约，再改实现（约束 #2）。
##
## 命名约定：过去式表事件（xxx_died），现在/进行表状态广播（xxx_changed）。
extends Node

# ===== 玩家 =====
## 玩家受到伤害。part: &"head" / &"body" / &"legs"
signal player_damaged(part: StringName, amount: float)
## 某部位血量变化（含治疗）。用于 HUD 血条刷新。
signal player_health_changed(part: StringName, current: float, maximum: float)
## 趴下状态切换。
signal player_prone_changed(is_prone: bool)
## 瞄准状态切换。
signal player_aim_changed(is_aiming: bool)
## 移动速度状态变化（健康/受伤/重伤/趴下联动结果）。state: &"normal" / &"injured" / &"critical" / &"prone"
signal player_speed_state_changed(state: StringName)
## 连续静止时长（秒），狙击手秒杀判定与 HUD 警告共用。仅在越过 1.0s 阈值时必需持续广播。
signal player_still_time_changed(seconds: float)
## 腿部状态警告（&"healthy" / &"injured" / &"critical"），HUD「⚠ 腿部受伤」条。
signal leg_state_changed(state: StringName)

# ===== 武器 =====
## 开火。weapon_id: &"rifle" / &"rpg"
signal weapon_fired(weapon_id: StringName)
## 切枪完成。
signal weapon_switched(weapon_id: StringName)
## 换弹开始（RPG 无此事件）。
signal weapon_reload_started(weapon_id: StringName)
## 换弹完成。
signal weapon_reloaded(weapon_id: StringName)
## 弹药数变化。reserve 对 RPG 为 -1（无弹匣概念）。
signal ammo_changed(weapon_id: StringName, mag: int, reserve: int)
## 命中确认（准星放大 1.3× / 爆头 1.8× + hitmark 音效）。
signal hit_confirmed(is_headshot: bool)
## 步枪打碉堡跳弹（提示「需用火箭筒摧毁碉堡」）。
signal ricochet_on_bunker()

# ===== 敌人 =====
## 敌人死亡（任意类型）。enemies_alerted 由击杀者随后广播。
signal enemy_died(enemy: Node)
## 以 origin 为中心 radius 范围同伴警戒（网页版半径 40，index.html L3029-3057）。
signal enemies_alerted(origin: Vector3, radius: float)

# ===== 任务 =====
## 呼叫直升机按钮解锁状态变化（撤离点 15u 内或通讯小屋 6u 内）。
signal heli_unlock_changed(unlocked: bool)
## 已呼叫直升机，60s 坚守开始。
signal heli_called()
## 坚守倒计时（每秒广播）。
signal heli_timer_updated(seconds_left: float)
## 直升机到达，可登机。
signal heli_arrived()
## 登机成功，任务完成。
signal mission_completed()
## 游戏结束。reason: &"enemy" / &"machine_gunner" / &"sniper" / &"mine" / &"generic"
signal game_over(reason: StringName)

# ===== 拾取与环境 =====
## 拾取药包（库存变化）。
signal medkit_picked(total: int)
## 使用药包。
signal medkit_used(remaining: int)
## 触发地雷（Day 0 裁决：HP 清零即触发 game_over，修复网页版缺陷）。
signal minefield_triggered()

# ===== 界面与系统 =====
## 夜视仪切换。
signal night_vision_toggled(enabled: bool)
## 中央飘字（msgArea，800ms 消失）。
signal message_posted(text: String)
## 击杀数变化。
signal kills_changed(kills: int)
