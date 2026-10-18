# 《熄烛者》Snuffers — W7 Qoder 派单 16：夜视仪升级（选项 2 已批准）+ 文档订正

> 本文档 = 蜂后派单提示词全文（2026-10-18），可直接整篇复制粘贴给 Qoder（Qwen3.8Max）。
> 前置：派单 13（street_day_night_driver）已收口，蜂后对抗审查通过；street_test.tscn 接线（S3）仍属蜂后待办，本单不涉及。

## 你的角色

你是 W7 Qoder，外部 IDE Agent，负责**昼夜/夜视域**。项目：Godot 4.6.2 + 纯 GDScript 线性 FPS。仓库：`E:\Github Project\Nagi_Games\Snuffers`，分支 **dev1**（禁止碰 master）。

## 入场纪律（先读后做）

1. 读仓库根 `AGENTS.md` 全文（十荣十耻、翻车模式、commit 自检四问）
2. 读 `desktop-port/godot-spike/03-handoff-2026-10-07-w7.md`（你上一班的交接——本单多处引用它）
3. 读 `desktop-port/godot-spike/05-daynight-street-proposal.md` §四（夜视升级选项 2 的原始论证）
4. `git pull origin dev1` 同步；`git status` + `git log --oneline -3` 确认无半截改动
5. 工作树里他人未提交的改动一律不碰；显式路径 `git add`，禁用 `git add -A`

## 蜂后对你三条契约申请的裁决（先告知，不用回确认）

| 申请 | 裁决 | 理由 |
|---|---|---|
| 1 `STREET_DAY_GROUND_HORIZON_COLOR` | **驳回（YAGNI）** | DAY 态仅美术对照，c1m1 剧情态恒为夜；c1m2 若真需要分离地面反光色，届时重新申请 |
| 2 `STREET_DAY_FOG_SKY_AFFECT` | **驳回（YAGNI）** | 同上；补常量+一行代码的成本留在真需求出现时再付 |
| 3 文档 `emission_strength`→`brightness` 订正 | **批准** | 即本单任务 2，你自己改自己的文档 |

## 任务 1（主任务）：夜视仪升级——选项 2「屏幕采样亮度增益」

你交接 §五和 05 文档 §四的论证蜂后已采信：现占位 overlay 是纯绿色彩覆盖（alpha≈0.3），**暗部无增益**，夜视仪的核心价值（暗处可视）未实现，且是 Phase 2「萤」暗斑可读性的前置条件。机主已批准按**选项 2** 施工。

### 改动范围

- **唯一允许修改的脚本**：`night_vision_overlay.gd`（你的域内文件）及其 canvas_item shader
- 新参数（增益强度/去饱和度/绿调色相等）**留脚本本地 const**，不入契约（沿用你 05 文档 §五「不申请项」的口径）；施工中若发现必须契约化，写交接「契约变更申请」段

### 硬性设计要求

1. **shader 加 `hint_screen_texture` 采样**（项目 Forward+ 默认渲染器，你已取证支持）：对屏幕颜色做**暗部 lift（亮度增益）→ 去饱和 → 绿磷光色调映射**，保留现有扫描线 + 暗角效果
2. **自发光体自然过曝**：应急灯/力场蓝光/天际线亮窗在增益下发白发亮 = 真实夜视仪光晕行为，这是**特性不是 bug**（05 文档 §四.2 已定调），不要压掉它
3. **HUD 层级实测核对**（你 05 文档自己挂的悬念）：CanvasLayer(100) 与 HUD 的 layer 关系必须实测并在交接里写结论——夜视膜盖住准星/血条还是在其下，两种情况的行为截图各留一张；若盖住准星导致不可读，调整 layer 并在交接说明
4. **隐式耦合防线（翻车模式⑦）**：`night_vision_overlay.gd` 正被灰盒流程消费。改前先 `grep -r` 找出全部引用方（greybox_arena / player 链 / hud），逐个确认兼容；**禁止改变**：N 键切换行为、`GameState.night_vision` 语义、`Events.night_vision_toggled` 信号消费关系、白天禁开门控逻辑
5. **增益参数的安全边界**：gain 别拉到把夜景洗成白昼——验收截图里暗部可读但「夜」的氛围必须在（机主对违和感极敏感，夜视仪观感参考：暗部清晰可辨、整体仍是绿调暗世界）
6. 应急灯/力场/天际线的具体共存表现以实测为准，05 文档 §4.1 的预测表仅作参考

### 验收标准（物化）

1. **L1 全链 PASS**（串行纪律：跑前杀 Godot 进程，同一时刻只你一个跑）
2. **audit_map A/B/C 全零**（兜底）
3. **截图组**（存 `modeling/audit-<日期>-nv/`，不入库）：
   a. E1 室内暗部：夜视开/关 对比——**暗部 lift 效果必须肉眼可分**（这是本单的核心验收点）
   b. 街区 overview：夜视开/关 对比——夜空不被洗成白昼、天际线亮窗过曝发白但可辨
   c. 应急灯旁：夜视开——暖橙光源过曝为白亮斑
   d. HUD 层级结论图（见设计要求 3）
4. 截图纪律：OverviewCamera transform 用完恢复；`--shot` 不用 `--quit`（你交接 §七.3 的教训）；ambient 提亮技巧用完必须还原 0.38
5. 灰盒回归：greybox_arena 开夜视截一张，确认升级后灰盒夜视无异常（G1/G2 基线场景，不许退化）

## 任务 2（小任务）：文档订正（契约申请 3 已批）

修改 `desktop-port/godot-spike/05-daynight-street-proposal.md`（你自己的文档）：
1. §四/§五中 `emission_strength` 全部订正为 **`brightness`**（代码事实）
2. shader 归属订正：**塔楼用 `skyline_facade.gdshader`**，`skyline_windows.gdshader` 用于天线与 Backdrop 楼块（你交接 §五.2 的发现）
3. 文末加一行修订记录（日期 + 订正原因 + 派单 16）

## 你不能动的文件

autoload 三件套、`street_test.tscn`、`main.tscn`、`project.godot`、`street_builder.gd` / `skyline_builder.gd` / 任何 shader 文件（只能改 overlay 自己内联的 shader 代码）、player/enemy 脚本、`tools/`、`tests/`、他人文档。`day_night_controller.gd` / `street_day_night_driver.gd` 本单不动。

## 工程纪律（继承）

- 小步提交，commit message 末尾 `自检: ①②③④ 通过`；只提 dev1
- 新文档编号用 **17-** 起（13/14/15/16 已被派单占用）
- 截图/证据 PNG 一律不入库；.bat 如需新建：GBK + CRLF
- 收工 commit + push origin dev1，写 `03-handoff-<日期>-w7.md`：完成/未完成/HUD 层级结论/契约变更申请（如有）/给下一棒的注意事项
- 不确定的 shader 内置函数/API 先查 Godot 官方文档，禁止凭记忆猜；30 分钟无进展暂停报告
