## Events — 全局信号总线（Autoload 单例）
##
## AGENTS.md 约束 #3：场景通信只走本总线，禁止跨模块直接 get_node 引用其他模块节点。
## 新增/修改信号必须先改本契约，再改实现（约束 #2）。
##
## 命名约定：过去式表事件（xxx_died），现在/进行表状态广播（xxx_changed）。
extends Node

# ===== 玩家 =====
## 玩家受到伤害。part 为发射侧语义标签（敌人随机池遗留），结算侧自 2026-10-21
## 单一生命值制起不再按部位区分。
signal player_damaged(part: StringName, amount: float)
## 受击来源方向（HUD 受击方向指示弧用，§11.1 A 方案三件套，2026-08-19 蜂后冻结新增）。
## 与 player_damaged 同点发射（enemy_base._damage_player / 狙击直发路径），纯增量不改既有签名。
signal player_hit_direction(from_position: Vector3)
## 生命值变化（含治疗与脱战回复）。用于 HUD 生命条刷新。
## 2026-10-21 机主裁决：三部位耐久制取消，改单一生命值；签名保留，part 恒为 &"hp"。
signal player_health_changed(part: StringName, current: float, maximum: float)
## 护甲能量变化（2026-10-19 机主立项：纳米服式脱战回充，回充期无受击事件，HUD 需专用信号刷新）。
signal armor_changed(current: float, maximum: float)
## 趴下状态切换。
signal player_prone_changed(is_prone: bool)
## 瞄准状态切换。
signal player_aim_changed(is_aiming: bool)
## 移动速度状态变化（健康/受伤/重伤/趴下联动结果）。state: &"normal" / &"injured" / &"critical" / &"prone"
signal player_speed_state_changed(state: StringName)
## 移动输入状态切换（脚步循环音起停用）。is_moving: 有无移动输入，与速度档位语义不同（G2 冻结新增）。
signal player_moving_changed(is_moving: bool)
## 连续静止时长（秒），狙击手秒杀判定与 HUD 警告共用。仅在越过 1.0s 阈值时必需持续广播。
signal player_still_time_changed(seconds: float)

# ===== 武器 =====
## 开火。weapon_id: &"rifle" / &"pistol" / &"grenade"（2026-10-22 EM-40G 榴档由步枪发出 &"grenade"）。
signal weapon_fired(weapon_id: StringName)
## 射击模式切换（2026-10-19 机主立项：X 键循环；2026-10-22 步枪追加 &"grenade" 榴档，闭环 全自动→半自动→三发点射→滚雷）。
## mode: &"semi" / &"burst" / &"auto" / &"grenade"
signal fire_mode_changed(weapon_id: StringName, mode: StringName)
## 切枪完成。
signal weapon_switched(weapon_id: StringName)
## 数字类别或滚轮请求显示武器选择栏。category 为主键盘 1..6。
signal weapon_category_selected(category: int)
## 换弹开始（榴弹档无此事件，雷池由模块自持）。
signal weapon_reload_started(weapon_id: StringName)
## 换弹完成。
signal weapon_reloaded(weapon_id: StringName)
## 弹药数变化。reserve 对榴弹档为 -1（雷池独立于备弹）。
signal ammo_changed(weapon_id: StringName, mag: int, reserve: int)
## 玩家枪口焰（2026-10-19 机主立项：微弱青蓝电磁焰）。position 为炮口世界坐标。
signal player_muzzle_flash(weapon_id: StringName, position: Vector3)
## 玩家弹丸命中环境（非可伤害目标）。metal=true 时命中金属表面（溅火星口径）。
signal bullet_impacted(position: Vector3, normal: Vector3, metal: bool)
## 命中确认（准星放大 1.3× / 爆头 1.8× + hitmark 音效）。
signal hit_confirmed(is_headshot: bool)
## 步枪打碉堡跳弹（提示「需用滚雷榴弹摧毁碉堡」）。
signal ricochet_on_bunker()
## 榴弹爆炸（爆炸音效/特效锚点，G2 冻结新增）。信号名保留护 G2 冻结面，现由 EM-40G 榴弹爆炸发射（2026-10-22 旧 RPG 已退役并入步枪榴档）。
signal rpg_exploded(position: Vector3)
## 对敌人造成伤害（HUD 伤害飘字用，G2 冻结新增）。与 hit_confirmed 互补；伤害投递仍走 take_damage 鸭子接口。
signal damage_dealt(amount: float, is_headshot: bool)
## 碉堡被榴弹摧毁（碉堡机枪停火 / HUD 提示 / 任务判定共用，G2 冻结新增）。碉堡全图唯一，无需参数。
signal bunker_destroyed()

# ===== 敌人 =====
## 敌人死亡（任意类型）。enemies_alerted 由击杀者随后广播。
signal enemy_died(enemy: Node)
## 以 origin 为中心 radius 范围同伴警戒（网页版半径 40，index.html L3029-3057）。
signal enemies_alerted(origin: Vector3, radius: float)
## 敌人开火（枪口音效/火光锚点，G2 冻结新增）。kind: &"rifle" / &"machine_gun"
signal enemy_fired(kind: StringName, position: Vector3)

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
## 拾取电池组（EC-68 武器备弹补充；reserve 为补充后的步枪备弹总数）。
## 2026-10-07 机主裁决冻结新增：居民区室内补给只出电池组/医疗注射，不出 RPG 战斗部。
signal battery_picked(reserve: int)
## 拾取手枪弹匣组（EM-57P 备弹补充；reserve 为补充后的手枪备弹总数）。
## 2026-10-19 机主立项：两种弹药拾取道具视觉/效果区分。
signal pistol_ammo_picked(reserve: int)
## 拾取 EC-12 弹匣组（EM-12G-1 备弹补充）。
signal shotgun_ammo_picked(reserve: int)
## 拾取取证终端（叙事收集品，提灯人前置情报遗留）。collected 已收集数，total 本图总数。
signal intel_picked(collected: int, total: int)
## 触发地雷（Day 0 裁决：HP 清零即触发 game_over，修复网页版缺陷）。
signal minefield_triggered()

# ===== 界面与系统 =====
## 夜视仪切换。
signal night_vision_toggled(enabled: bool)
## 中央飘字（msgArea，800ms 消失）。
signal message_posted(text: String)
## 击杀数变化。
signal kills_changed(kills: int)
