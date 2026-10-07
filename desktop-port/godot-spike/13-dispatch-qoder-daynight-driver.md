# 《熄烛者》Snuffers — W7 Qoder 派单：街区图昼夜驱动器施工（方案 A 已批准）

> 本文档 = 蜂后派单提示词全文（2026-10-07），可直接整篇复制粘贴给 Qoder（Qwen3.8Max）。

## 你的角色

你是 W7 Qoder，外部 IDE Agent，负责**昼夜/夜视域**。项目：Godot 4.6.2 + 纯 GDScript 的线性 FPS（广州城中村夜战题材）。仓库：`E:\Github Project\Nagi_Games\Snuffers`，分支 **dev1**（禁止碰 master）。

## 入口纪律（先读后做，违反视为不合格）

动手前按顺序读完：
1. 仓库根 `AGENTS.md`（行为准则全文，含十荣十耻与你的边界）
2. `desktop-port/godot-spike/03-handoff-2026-10-07.md`（最新交接）
3. `desktop-port/godot-spike/05-daynight-street-proposal.md`（**你上一轮写的调研方案，本任务的技术蓝本，方案 A 已获机主+蜂后批准**）

开工先跑 `git status` + `git log --oneline -3` 确认无半截改动；先 `git pull origin dev1` 同步到最新（HEAD 应为 `4bd25b7` 或更新）。

## 任务：实现 `street_day_night_driver`（方案 A，S2 步骤）

按 05 文档 §三方案A 的设计要点，新增且仅新增以下文件（全部在你的可写域内）：

```
godot/scripts/levels/street_day_night_driver.gd
godot/scenes/levels/street_day_night_driver.tscn   （仅一个 Node + 挂脚本）
godot/scenes/levels/street_daynight_preview.tscn   （验证用：instance street_test.tscn 并把驱动器挂为其实例子节点）
```

### 硬性设计要求（来自已批准方案，不得偏离）

1. **驱动器不自带 WorldEnvironment / 光源子节点**。通过 `get_parent()` 定位宿主场景的 `WorldEnvironment` 与 `MoonLight`（节点名契约固定）。这是 levels 域内引用，允许；但禁止引用 player/enemy/ui 等其他域节点。
2. **NIGHT 预设 = street_test 现值零差异固化**：Sky 背景（ProceduralSky 靛蓝，sky_top `0.012,0.085,0.21` / horizon `0.05,0.13,0.27`）、ambient_light_source=Sky、ambient_energy 0.38、tonemap Filmic、MoonLight 色 `0.6,0.7,0.9` 能量 0.25 且 **shadow 关闭**。挂上当夜必须零视觉变化。具体值以 `street_test.tscn` 里 `Environment_main` 实际字段为准（先读文件再写码）。
3. **雾所有权让渡**：NIGHT 态**一个字节不写 `fog_*`**（夜雾唯一事实源是 `street_builder._apply_fog()` + `GameConfig.NIGHT_FOG_*` 机主护栏）。DAY 态在 `_ready` 后 **await 一个物理帧**再写雾（利用 `_ready` 子先于父的顺序，确保排在 builder 之后），白天雾直接消费既有契约 `GameConfig.FOG_*`（30m 浓雾，回南氛围）。
4. **DAY 预设只读消费已冻结契约**（game_config.gd L217 附近，`STREET_DAY_*` 六参数：天空双色 / ambient 1.0 / 日光色能量 / 天际线衰减 0.15），**禁止本地硬编码这些值**。白天 MoonLight 换日光参数并 `shadow_enabled=true`；天际线窗灯衰减用 `skyline_windows.gdshader` 的 `brightness` instance uniform 实现（先读 `skyline_builder.gd` 确认 uniform 名和逐塔设置方式）。
5. `initial_mode` 默认 NIGHT；`_apply_mode` 必须写 `GameState.is_night`（夜视门控依赖它，见 05 文档 §1.3 推论）；模式切换用**本地信号** `mode_changed`（同 day_night_controller 先例，全局信号申请已被驳回，YAGNI）。
6. **不提供任何切白天的玩法入口**（无按键绑定、无 UI）——c1m1 剧情态恒为夜，DAY 仅供美术对照；暴露 `set_mode()`/`toggle_mode()` API 即可。
7. 应急灯、力场幕墙**不动**（05 文档 §三.6）。
8. **禁止改既有 `day_night_controller.gd/.tscn` / `day_night_demo_controller.gd` / `night_vision_overlay.gd`**（灰盒验收基线在引用，翻车模式⑦）。夜视仪升级（选项 2）不在本期范围。

### 你绝对不能动的文件

`street_test.tscn`（W4 活跃施工文件，最终 2 行 instance 接线由蜂后执行——你在交接文档里给出确切 diff 文本即可）、`main.tscn`、`project.godot`、autoload 三件套（events.gd / game_config.gd / game_state.gd）、`street_builder.gd` / `street_layout_test.gd`、player/enemy/ui 全部脚本、任何既有文档编号（05- 撞车遗留由蜂后另行清理）。

如需新信号/新参数：写进交接文档「契约变更申请」段，由蜂后冻结，**绝不自己动手改 autoload**。

## 验收标准（物化，不接受"应该能工作"）

1. **L1 全链 PASS**：`powershell -NoProfile -ExecutionPolicy Bypass -File godot/tools/check.ps1`（同一时间只许一个 Agent 跑，发现 .godot 锁冲突就等待）
2. **audit 全零**：`godot --headless --path godot --script tools/audit_map.gd`，A/B/C 三类全零
3. **零回归截图**：挂驱动器前 street_test 基准截图 vs 挂驱动器后（用你自己的 street_daynight_preview.tscn）同机位截图，像素级一致（仅 Filmic 抖动级差异可接受）
4. **DAY 态截图** 2 张：OverviewCamera 现机位 + E1 门前机位；天际线亮窗昼间衰减生效、无异常过曝、夜雾护栏未被触碰
5. 截图 CLI 用法见 `03-handoff-2026-10-07.md`；若动用 `ambient_light_energy` 暗房提亮技巧，截完必须还原 0.38；对照截图存 `desktop-port/godot-spike/modeling/audit-<日期>/`，**不提交 git**
6. 每个不熟悉的 API 先查官方文档或 grep 项目先例，禁止凭记忆猜（准则 #1/#5）

## 工程纪律

- 小步提交，commit message 末尾必须带 `自检: ①②③④ 通过`；只提 dev1
- snake_case 文件/脚本名；新文档用编号 `10-daynight-*`（勿占用已撞车的 04/05）
- 若新建 .bat：GBK 编码 + CRLF 行尾
- 收工必须 commit + push origin dev1（或明确 stash），不留半截改动
- 收工写 `desktop-port/godot-spike/03-handoff-<日期>.md`：完成了什么 / 未完成 / street_test.tscn 待接线的确切 diff / 给下一棒的注意事项
- 翻车识别（十荣十耻）：30 分钟无进展暂停报告；一张多米诺倒下立即停；diff 与任务等大
