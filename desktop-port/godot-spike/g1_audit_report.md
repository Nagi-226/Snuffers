# G1 门禁审计报告 — 《废墟突围》Godot Spike「手感关」

> **审计角色**：G1 门禁审计员（只读，未修改/新建任何业务文件）
> **审计快照**：2026-07-20 19:51（本地时间）· 分支 `dev_godot`
> **引擎**：Godot v4.6.2.stable.official.71f334935（标准版，`D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe`）
> **审计基准**：`desktop-port/godot-spike/00-spike-plan.md` §5 G1 验收口径 + §7 手感参数对照表（G1 行）+ `AGENTS.md` 质量防线 L1/L2
> **并发声明**：审计期间 W2（Jeh3no 插件目录）、W5（hud.gd / hud.tscn / audio_manager.gd）、W6（check.ps1 / smoke_scenes.gd / ATTRIBUTION.md / .gitignore）仍在并行交付，本报告基于 19:51 快照；此前 19:4x 完成的全部校验在快照点复跑复核通过。审计副作用（`--import` 重写的 13 个 `.import` 缓存文件，内容与索引零差异、仅行尾 stat 变化）已用 `git checkout` 恢复，未污染工作区。

---

## ① L1 静态校验（通过）

### 1a. 原生 `--check-only --script` 直跑（任务指定命令）

| 命令 | 结果 |
|---|---|
| `godot --headless --path godot --check-only --script res://autoload/events.gd` | ✅ exit 0 |
| 同法 `game_config.gd` / `game_state.gd` / `tests/check_scripts.gd` / `tests/smoke_contracts.gd` | ✅ exit 0 |
| 同法 `scripts/player/player_controller.gd` | ❌ `Identifier not found: GameConfig`（:56，`GameConfig.view_sensitivity`） |
| 同法 `scripts/ui/audio_manager.gd` | ❌ `Identifier not found: Events`（:159，`Events.weapon_fired`） |
| 同法 `scripts/ui/hud.gd` | ❌ `Identifier not found: GameState`（:55，`GameState.kills`） |

**根因判定（非代码缺陷，系工具链已知假阳性）**：headless `--check-only` 模式下 GDScript 分析器无法解析 autoload **成员访问**（`Events.*` / `GameConfig.<var>` / `GameState.*`），仅 **常量访问**（如 `GameConfig.FOV_BASE`）因编译期折叠可通过。该假阳性已被 W6 在校验链脚本 `godot/tests/check_scripts.gd:1-14` 与 `godot/tools/check.ps1:92-96` 中书面记录，并以自建 harness 替代。佐证：`game_state.gd` 只含 `GameConfig.<const>` 访问，直跑即过；三个 FAIL 均落在 var/成员访问行。

### 1b. W6 校验链复测（项目既定 L1 标准，含全部 9 个工程 .gd）

```
godot --headless --path godot -s res://tests/check_scripts.gd -- <9×.gd>
→ SCRIPT-OK ×9，"check_scripts: all scripts OK"，exit 0   （19:51 快照复跑同结果）
```

覆盖：autoload 三件套 + player_controller.gd + hud.gd + audio_manager.gd + tests 三脚本（check.ps1 口径：`addons/` 与 `.godot/` 排除）。

### 1c. 契约冒烟断言

```
godot --headless --path godot -s res://tests/smoke_contracts.gd
→ PASS ×7（SPEED_STAND==4.5 / RIFLE_FIRE_INTERVAL==0.1 / weapon_fired / game_over 信号存在
  / reset() 三部位血量键齐全），exit 0
```

### 1d. 场景节点冒烟（W6 Sprint 2 加固步）

```
godot --headless --path godot -s res://tests/smoke_scenes.gd
→ PASS ×16（player.tscn 3 节点、greybox_arena.tscn 6 节点、hud.tscn 7 节点）
  SKIP ×3（rifle.tscn / rpg.tscn / infantry.tscn —— W2/W3 未交付，按设计报 SKIP），exit 0
```

---

## ② L2 契约校验：game_config.gd vs §7 手感参数对照表 G1 行（通过，7/7 项全符）

| §7 G1 行 | 网页版实际值 | Godot 目标值 | GameConfig 现状 | 实现接线（player_controller.gd） | 判定 |
|---|---|---|---|---|---|
| 站立移速 | 4.5 u/s | 4.5（delta 化） | `SPEED_STAND = 4.5` | `_current_speed()` L151；`_physics_process(delta)` L98 | ✅ |
| 瞄准移速 | 1.5 u/s | 1.5 | `SPEED_AIM = 1.5` | L148-149 | ✅ |
| 趴下移速 | 0.72 u/s | 0.72 | `SPEED_PRONE = 0.72` | L146-147 | ✅ |
| 腿伤移速 | 2.25 u/s | 同 | `LEG_INJURED_FACTOR = 0.5` → 4.5×0.5 = **2.25**；阈值 `LEG_INJURED_THRESHOLD = 0.6` | L152-154 | ✅ |
| 重伤移速 | 1.125 u/s | 同 | `LEG_CRITICAL_FACTOR = 0.25` → 4.5×0.25 = **1.125** | L155-156 | ✅ |
| 鼠标灵敏度 | movement × 0.002 × 2.0，开镜 ×0.3 | 同 | `MOUSE_SENS_BASE = 0.002`、`view_sensitivity = 2.0`、`AIM_SENS_FACTOR = 0.3` | L56-58 三者相乘，开镜分支正确 | ✅ |
| 俯仰钳制 | ±1.2 rad | 同 | `PITCH_CLAMP = 1.2` | L60 `clampf(±PITCH_CLAMP)` | ✅ |
| 相机高度 | 站 2.0 / 趴 0.5 + 150ms 过渡（有意改进） | 同 | `CAM_HEIGHT_STAND = 2.0`、`CAM_HEIGHT_PRONE = 0.5`、`CAM_HEIGHT_LERP_TIME = 0.15` | L46-47 初始化 + L137-140 lerp 过渡 | ✅ |

**缺失项：无。数值不符项：无。**

附加核对（W1 派单口径，非 §7 行但属 G1 范围）：世界边界 `WORLD_BOUND_X=98 / WORLD_BOUND_Z=58`（L128-129 钳制）✅；碰撞几何 `PLAYER_RADIUS=0.4 / PLAYER_HEIGHT_STAND=1.8`（L42-44）✅；delta 化改造（§6 缺陷修复项）已落实为 `_physics_process(delta)` ✅；全部手感参数均引自 GameConfig，player_controller.gd 未见硬编码手感数值（重力取自 `ProjectSettings` 引擎全局，注释明示非手感参数）✅。

---

## ③ 信号清单核对（通过，含 G1 阶段预期缺口标注）

events.gd 定义信号 **28 个**；全工程 `Events.xxx` 引用 **23 个**；**被引用但未定义的信号：0 个**（差集为空，无悬空引用）。

### 3a. 已闭环（emit + connect 齐备）——6 个

| 信号 | emit | connect |
|---|---|---|
| `player_health_changed` | player_controller.gd:256 | hud.gd:97 |
| `weapon_switched` | player_controller.gd:238 | hud.gd:100 |
| `weapon_reloaded` | player_controller.gd:230 | audio_manager.gd:160 |
| `medkit_used` | player_controller.gd:252 | audio_manager.gd:164 |
| `night_vision_toggled` | player_controller.gd:244 | audio_manager.gd:165 |
| `heli_called` | player_controller.gd:273 | hud.gd:106 + audio_manager.gd:166 |

### 3b. 有 emit 无 connect ——5 个（G1 阶段可接受）

`player_prone_changed`、`player_aim_changed`、`player_speed_state_changed`、`player_still_time_changed`（均由 player_controller 发射；消费方属 Sprint 2/3：瞄准镜 PiP、HUD 静止警告、碉堡停火判定）、`weapon_reload_started`（HUD 换弹提示属 Sprint 2）。

### 3c. 有 connect 无 emit ——12 个（G1 阶段可接受，Sprint 1 无伤害/击杀来源）

`player_damaged`（hud+audio）、`leg_state_changed`（hud）、`weapon_fired`（audio）、`ammo_changed`（hud）、`hit_confirmed`（hud+audio）、`enemy_died`（hud+audio）、`heli_timer_updated`、`heli_arrived`、`mission_completed`、`game_over`（hud+audio）、`message_posted`（hud）、`kills_changed`（hud）。发射方均为 Sprint 2（W2 武器/W3 敌人）与 Sprint 3（任务流程）职责，**G2 门禁必须复核本表全部接通**。

### 3d. 定义但零引用（emit 与 connect 均无）——5 个，全部属 Sprint 2/3 范围，G1 不构成不通过

| 信号 | 预定职责 | 备注 |
|---|---|---|
| `ricochet_on_bunker` | W2 步枪打碉堡跳弹提示 | G2 复核 |
| `enemies_alerted` | W3 同伴警戒（半径 40） | G2 复核 |
| `heli_unlock_changed` | Sprint 3 撤离解锁 | G3 复核 |
| `medkit_picked` | 拾取物流程 | G2/G3 复核 |
| `minefield_triggered` | 地雷（含 §6 缺陷修复：HP 清零即 game_over） | G3/拉伸项复核 |

### 3e. 连接生命周期

hud.gd 与 audio_manager.gd 均在 `_exit_tree` 对称 disconnect（18/18 与 10/10 配对），无泄漏隐患。

---

## ④ 场景可解析（通过）

| 校验 | 命令 | 结果 |
|---|---|---|
| 工程导入 | `godot --headless --path godot --import` | ✅ exit 0（13 个音频资产重导入成功） |
| 主场景启动 | `godot --headless --path godot --quit-after 30` | ✅ exit 0，无 ERROR/SCRIPT ERROR |
| 逐场景实例化 | 同法 `--quit-after 10 <scene>` ×6 | ✅ 全过：main / player / greybox_arena / hud / hud_test / audio_manager |

---

## ⑤ 性能与手感主观项（明确标记：需机主试玩验证，本审计不臆断）

| 项 | G1 验收口径 | 本审计状态 |
|---|---|---|
| 1080p 稳定 60fps | §5 G1 验收 | **需机主/蜂后实机验证**。headless 环境无渲染负载，无法取样；Tracy 采样属 W6 G4 取证范畴，G1 可先做粗测 |
| 移动/转身/瞄准跟手感 | §8 主观项 1 | **需机主试玩打分**，不得由静态审计推断 |
| 蜂后手感试玩签字 | §5 G1 验收 | **需蜂后实机试玩**，本报告不替代签字 |

---

## 汇总三栏

### ✅ 通过项

1. **L1 静态校验**：9/9 工程脚本经 W6 校验链编译通过；契约冒烟 7/7；场景节点冒烟 16 PASS + 3 SKIP（按设计）。
2. **原生 `--check-only` 直跑的 3 个 FAIL 已定性为工具链假阳性**（autoload 成员访问不可解析），非代码缺陷，W6 链有书面记录与替代方案。
3. **L2 契约校验**：§7 G1 行 7/7 全符（站立 4.5 / 瞄准 1.5 / 趴下 0.72 / 腿伤 2.25 / 重伤 1.125 / 灵敏度 0.002×2.0 开镜×0.3 / 俯仰 ±1.2 / 相机 2.0/0.5+150ms），无缺失无不符。
4. **信号清单**：28 定义信号零悬空引用；6 条 G1 闭环全部双向接通；connect/disconnect 对称。
5. **场景可解析**：`--import` + 主场景 30 帧 + 6 场景实例化全过。
6. **设计约束抽查**：player/hud/audio 三脚本手感参数全部引自 GameConfig 无硬编码；跨模块通信全部走 Events 总线，未见跨模块 `get_node`；文件命名 snake_case；autoload 三件套与 project.godot 未被工蜂改动（git diff 确认改动仅限 W2/W5/W6 各自所有权目录）。

### ❌ 不通过项

**无。**

### ⚠️ 存疑项（不阻断 G1，需蜂后知晓/裁决）

1. **趴下碰撞几何妥协**：`PLAYER_RADIUS=0.4` 与 `PLAYER_HEIGHT_PRONE=0.4` 存在胶囊体几何冲突（高 0.4 < 2×半径 0.8 不可行），W1 已退化为趴下半径 0.2 并注释上报（player_controller.gd:195-198）——**契约参数本身未动，但趴下碰撞半径实际偏离 PLAYER_RADIUS**，建议蜂后裁决：接受妥协 or 修订契约参数并同步 §7 注记。
2. **趴下+腿伤叠加移速未定义**：实现为基速×系数（趴下+受伤 = 0.36 u/s），§7 仅定义站立基准的 2.25/1.125，网页版叠加行为未在对照表覆盖——建议 W1 在 G1 试玩时与网页版实测比对，偏差则记录为 §7 增补行。
3. **HUD/UI 反馈常量滞留业务脚本**（W5 已自标缺口）：hud.gd 头部 9 个视觉常量（准星 1.3×/1.8×/0.06s/0.1s、飘字 0.8s/0.3s、红晕 0.35α/0.4s、击杀反馈 0.6s）——属 UI 动效非手感参数，建议蜂后裁决豁免 or 收编 GameConfig（建议名见下）。
4. **契约信号缺口**（W5 已在代码注释自报，审计汇总）：头盔/护甲无专用变更信号（HUD 现从 GameState 拉取兜底）；音效 `explosion` / `footstep` / `ui_click` 无触发信号，W5 建议 `rpg_exploded()` 与 `player_moving_changed(is_moving)`。
5. **`.gitignore` 残留失效条目**：第 18 行 `godot/addons/jeh3no-fps-weapon-system/`（连字符）与实际目录 `jeh3no_fps_weapon_system`（下划线）不符；第 19 行新条目已正确覆盖，旧行冗余但无害——建议 W6 顺手清理。
6. **并发施工漂移风险**：本审计基于 19:51 快照，W2/W5/W6 仍在写入；蜂后裁决前建议由 W6 以 `tools/check.ps1` 全链复跑一次作为最终封印。

---

## 契约缺口清单（建议，未经授权未添加）

| 类型 | 建议名 | 建议默认值 | 提出方/出处 |
|---|---|---|---|
| GameConfig 参数（或裁决豁免） | `CROSSHAIR_HIT_SCALE` | 1.3 | W5 hud.gd 注释 |
| 同上 | `CROSSHAIR_HEADSHOT_SCALE` | 1.8 | 同上 |
| 同上 | `CROSSHAIR_PULSE_HOLD` | 0.06 | 同上 |
| 同上 | `MESSAGE_HOLD_TIME` | 0.8 | 同上 |
| 同上 | `DAMAGE_FLASH_PEAK_ALPHA` | 0.35 | 同上 |
| 同上 | `DAMAGE_FLASH_FADE_TIME` | 0.4 | 同上 |
| 同上 | `KILL_FEEDBACK_HOLD_TIME` | 0.6 | 同上 |
| Events 信号 | `helmet_changed(current, maximum)` / `armor_changed(current, maximum)` | — | W5 hud.gd 注释（或裁决维持 GameState 拉取模式） |
| Events 信号 | `rpg_exploded(position)` | — | W5 audio_manager.gd 注释（explosion 音效） |
| Events 信号 | `player_moving_changed(is_moving)` | — | W5 同上（footstep 循环音） |

---

## 总体裁决建议：**PASS（附条件生效）**

**客观项 4/4 通过**（L1 静态校验 / L2 契约对照 7-7 / 信号清单零悬空 / 场景全可解析），无阻断性不通过项。

**生效条件（G1 收尾动作）**：
1. 机主/蜂后完成实机试玩，补签 §5 G1 验收的主观两项（手感签字 + 1080p 60fps 粗测）——本审计明确不替代该判定；
2. 蜂后对存疑项 1（趴下碰撞几何）、3（UI 常量豁免）、4（信号缺口）各给一个书面裁决，记入契约或 §7 注记；
3. W6 在代码冻结点以 `tools/check.ps1` 全链复跑封印，消除并发漂移风险。

**给 G2 的前置要求**：§3c 表 12 个「有 connect 无 emit」信号须在 G2 复核全部接通（尤其 `weapon_fired` / `hit_confirmed` / `ammo_changed` / `enemy_died` / `leg_state_changed` / `player_damaged`）。

---

*审计员：G1 门禁审计员（plan 子代理）· 自检：只读纪律遵守（唯一写入 = 本报告）；import 缓存副作用已恢复；全量命令与输出如上可复现。*

*补记（19:51 快照后）：W2 新交付 `scripts/weapons/hit_solver.gd` 与 `scripts/weapons/weapon_data.gd`（Sprint 2 范围，不计入 G1 判定）；顺手经 W6 链补测编译均 SCRIPT-OK。G1 正式判定仍以快照为准，冻结点须由 W6 全链复跑封印。*
