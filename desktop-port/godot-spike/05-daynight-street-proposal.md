# 昼夜/夜视系统 × 街区图 c1m1_oldtown_south 集成预研方案（W7）

> 版本：v0.1 · 2026-09-30 · W7 Qoder（外部 IDE Agent，昼夜/夜视域）
> 性质：**只读调研产物，未动任何代码**。蜂后评审通过后再排施工。
> 调研基线：dev1 HEAD `0d4729a`；取证方式：逐文件 Read/grep，非回忆。
> 编号说明：按蜂后派单指定文件名 `05-daynight-street-proposal.md`；与既有
> `05-edaa-derivative-assessment.md` 编号撞车，是否改号（如 13-）请蜂后评审时裁决。

---

## 一、现状事实核查（代码级取证）

### 1.1 street_test.tscn 环境链（正在活跃施工，W7 只读）

| 部件 | 现值 | 出处 |
|------|------|------|
| `WorldEnvironment`（场景根子节点） | `Environment_main`：background_mode=2（**Sky**）、ProceduralSkyMaterial 靛蓝蓝调（sky_top `0.012,0.085,0.21` / horizon `0.05,0.13,0.27`）、ambient_light_source=3（**Sky**）、ambient_energy 0.38、tonemap_mode=2（Filmic） | street_test.tscn L8–29 |
| `MoonLight`（DirectionalLight3D） | 色 `0.6,0.7,0.9`、能量 **0.25**、**shadow_enabled=false** | street_test.tscn L31–35 |
| 夜雾 | `street_builder._apply_fog()` 在 `_ready()` 第一行**无条件**写入：FOG_MODE_EXPONENTIAL、density/颜色/散射/sky_affect 全部取 `GameConfig.NIGHT_FOG_*`（60m 能见度，机主护栏：density ≤0.065、sky_affect 禁上调） | street_builder.gd L42–43、L474–483；game_config.gd L200–208 |
| CBD 天际线 | `skyline_builder.gd` + `skyline_windows.gdshader`：emission 自发光窗格、`render_mode fog_disabled`（夜雾不洗天际线的前提）、材质 `brightness` instance uniform 可逐塔调暗 | skyline_builder.gd；shader L12–33 |
| 背景楼夜窗 | `street_builder._get_block_material()` 复用同 shader，住宅化参数（lit_ratio 0.30） | street_builder.gd L1275–1285 |
| 力场幕墙 | `mat_energy_field.gdshader`：自发光半透明（base_alpha 0.16 / band 0.30 / edge 0.35），四向 `FIELD_*` + 发射柱 `tip_glow` + 每力场一盏 `OmniLight3D` 蓝光灯（投路面光晕） | street_builder.gd L79–83、L218–224 |
| E1 应急灯 | `emergency_light.gd`（OmniLight3D）暖橙闪烁，参数全走 `GameConfig.EMERGENCY_*`；一楼门厅 + 二楼楼梯口各一盏 | 03-handoff-2026-09-27 §二 |

**关键事实**：street_test 的夜景是「tscn 静态环境资源 + builder 脚本运行时写雾」**双头维护**，且 builder 注释明示「street_test 已固化为蓝调时刻夜景」（L475）。

### 1.2 既有昼夜域产物（灰盒时代，W7 自有域）

| 文件 | 现状 | 与街区图的差距 |
|------|------|--------------|
| `day_night_controller.gd/.tscn` | 自包含 WorldEnvironment + SunLight；DAY/NIGHT 双预设 const 本地硬编码；`_apply_mode` 写 `GameState.is_night`；background_mode=**BG_COLOR 纯色** | ①自带 env 与 street_test 已有 env **互斥**（一个 Viewport 只允许一个 WorldEnvironment 生效）②纯色背景会**摧毁 Sky 模式 + CBD 天际线**③NIGHT 预设（fog_density 0.005、ambient 0.15）与街区图现值（0.065、Sky 环境光 0.38）**完全不同**，直接套用=视觉回归 |
| `night_vision_overlay.gd` | CanvasLayer(100) + 绿色磷光 canvas_item shader（alpha≈0.3 半透明覆盖 + 扫描线 + 暗角）；无玩家在场时自持 N 键，有玩家让位 player_controller；白天禁开读 `GameState.is_night` | **无亮度增益**（纯色彩覆盖，暗处仍暗）；灰盒可接受，街区图暗部多（室内/巷弄），实用性存疑 → §四升级选项 |
| `day_night_demo_controller.gd` | T 键切换演示专用，不进正式流程 | 与集成无关，保留不动 |
| 接线现状 | 仅 `greybox_arena.tscn` / `day_night_demo.tscn` 挂载 | street_test / main.tscn 均**未**挂载任何昼夜节点 |

### 1.3 契约现状（autoload 三件套，W7 只读）

- `GameState.is_night` 默认 **true**、`GameState.night_vision` 默认 false（game_state.gd L37–39）。
- `Events.night_vision_toggled(enabled)` 已存在（events.gd L84），音频/HUD/overlay 均已消费。
- 夜视门控链：`player_controller._toggle_night_vision()` → `if not GameState.is_night and not GameState.night_vision: return`（player_controller.gd L245–249）。
- **推论**：street_test 当前无控制器、`is_night` 靠默认值 true 兜底，夜视门控恰好可用。任何集成方案**必须保证 NIGHT 态显式写 `is_night=true`**，否则白天模式退出后若无人回写，门控静默失效（翻车模式⑦隐式耦合）。

---

## 二、集成冲突清单（为什么不能直接把 controller 塞进 street_test）

| # | 冲突 | 后果 |
|---|------|------|
| C1 | 双 WorldEnvironment（controller 自带 vs 场景已有） | Godot 只生效其一，另一个静默失效——具体哪个取决于树顺序，隐式耦合 |
| C2 | controller NIGHT 预设 ≠ 街区图现值 | 套用即视觉回归：雾 0.005 vs 0.065、BG_COLOR 纯色 vs Sky、ambient 0.15 vs Sky 环境光 0.38、tonemap 丢失 |
| C3 | 雾参数所有权：`street_builder._apply_fog()` 无条件写 vs controller 预设也写 | 双方竞争同一 Environment 属性；且 **Godot `_ready` 顺序 = 子节点先于父节点**，controller 若是根的子节点则先跑，随后被 builder（根脚本）**覆盖**——NIGHT 侥幸等价，DAY 必被踩回夜雾 |
| C4 | `MoonLight` 与 controller 的 `SunLight` 并存 | 双 DirectionalLight3D，白天两盏叠光、阴影方向打架 |
| C5 | project.godot 无任何 day_night 接线；autoload 属共享文件 | W7 无权改 project.godot / main.tscn / autoload 三件套（AGENTS.md 边界表） |

---

## 三、方案对比与推荐

### 方案 A：新增「街区昼夜驱动器」，不动既有 controller（**推荐**）

新增文件（全部落在 W7 可写域 `scenes/levels/` + `scripts/levels/`）：

```
godot/scripts/levels/street_day_night_driver.gd   （新增）
godot/scenes/levels/street_day_night_driver.tscn  （新增，仅一个 Node + 脚本）
```

**设计要点**：

1. **不自带 WorldEnvironment / 光源子节点**。驱动器通过 `get_parent()` 定位宿主场景既有的 `WorldEnvironment` 与 `MoonLight`（挂载约定：实例化为 street_test 根的直接子节点，节点名契约固定）——规避 C1/C4。
   - 注：这是对宿主场景节点的定向引用，严格说触碰「禁止跨模块 get_node」红线的边缘。但驱动器与 street_test 同属 **levels 域**，域内引用不越界；且挂载方式本身（往 street_test.tscn 加一行 instance）必须由 W4/蜂后执行（见 §三.施工边界）。
2. **NIGHT 预设 = street_test 现值零差异固化**：驱动器 NIGHT 分支写入的值与 tscn `Environment_main` + `_apply_fog` 结果**逐项相等**（Sky 背景、ambient 0.38、MoonLight 0.25 等），保证「挂上去当夜无变化」的零回归验收（§六）。
3. **雾所有权让渡（规避 C3，利用 `_ready` 顺序）**：
   - NIGHT 态驱动器**完全不写 fog_***——夜雾唯一事实源保持 `street_builder._apply_fog()`（契约 `NIGHT_FOG_*` + 机主护栏）。
   - DAY 态在**第二个物理帧**（`_ready` 后 await 一次 process）再写雾，确保排在 builder 之后：取**既有契约** `GameConfig.FOG_*`（浓雾 30m，game_config.gd L195–198）作为白天雾基线，白天浓雾恰好符合「回南」潮湿氛围且不触碰夜雾护栏。
4. **DAY 预设（新增视觉参数，走契约申请 §五）**：Sky 材质换白天配色（sky_top/horizon 提亮为昼间蓝）、ambient_energy 上调、MoonLight 换暖白日光 + 能量上调 + **shadow_enabled=true**（白天阳光投影；夜景关阴影是性能取舍，白天开回来）、`skyline_windows` 材质 `emission_strength` 乘昼间衰减因子（白天亮窗不可信）。
5. **模式切换入口**：驱动器自持 `mode_changed` 本地信号（同 controller 先例，非全局契约）；写 `GameState.is_night`（复用既有字段，无契约变更）。是否给玩家/任务链暴露切换能力**不在本期范围**——c1m1 剧情定位即夜战，DAY 态主要用于美术对照与未来 c1m2 复用。
6. **应急灯/力场白天策略**：均**不动**。应急灯是 OmniLight，白天环境光下自然不可见（物理正确）；力场 shader 自发光白天略洗白，属 Phase 2 美术期议题（07 文档域），本期只在文档记录。

**施工边界（关键）**：street_test.tscn 属 W4 活跃施工文件，W7 一个字节不能动。落地时由蜂后派单 W4（或蜂后本人）**在 street_test.tscn 追加一行 instance**（约 2 行 diff：ext_resource + node），驱动器脚本/场景由 W7 提供。这符合「单行接线、零改既有节点」的最小侵入原则。

### 方案 B：直接挂既有 day_night_controller.tscn（否决）

C1–C4 全中：双 env、纯色背景毁天际线、NIGHT 预设回归、双方向光。**否决理由充分，仅存档备查。**

### 方案 C：改造 day_night_controller.gd 兼容街区图（否决）

controller 正被 greybox_arena（G1/G2 验收基线场景）引用，改其预设或加宿主探测逻辑 = 改公共接口行为（翻车模式⑦）。灰盒与街区图两套环境差异过大，强行兼容会做出「双头怪」。保留 controller 服务灰盒，街区图另起驱动器，两文件同属 W7 域、互不引用。

### 方案 D：autoload 全局昼夜管理器（暂缓）

跨图统一昼夜状态确是存档系统 S1/S2（per-map 快照）的关联议题，但 autoload 属蜂后专属共享文件，且 S1 契约尚未冻结。本期不申请；待 S1 契约冻结时由蜂后统筹是否把 `is_night` 升级为 per-map 快照字段。

---

## 四、夜视仪与应急灯/力场蓝光共存分析

### 4.1 现状叠加行为（占位 overlay，alpha≈0.3 绿色覆盖）

| 光源 | 夜视下观感 | 评估 |
|------|-----------|------|
| E1 应急灯（暖橙 `1.0,0.55,0.25`，能量 1.6） | 橙色高亮区叠绿膜 → 呈亮黄绿斑，闪烁保留 | **正收益**：楼梯引导灯变成夜视下的显眼路标，与「断电楼内备用电」设定自洽 |
| 力场蓝光（shader 自发光 + OmniLight 蓝晕） | 蓝色半透明幕墙叠绿膜 → 青绿色发光带 | **正收益**：周界在夜视下更可读，不干扰「萤」HUD 敌我识别（暗斑机制在角色轮廓上，与背景光无耦合） |
| CBD 天际线（emission 窗格，fog_disabled） | 远景亮窗叠绿 → 天空泛绿光晕 | **风险点**：overlay 暗角外沿 alpha 0.3 会把大面积夜空洗绿，久视疲劳 |
| 室内暗部（E1 无窗房间） | 纯绿膜无增益 → 暗处依旧暗 | **实用性缺口**：夜视仪核心价值（暗处可视）未实现 |

### 4.2 升级选项（供蜂后裁决，施工另排）

- **选项 1（保守，零依赖）**：维持现状，仅把 overlay alpha 从 0.3 降至 ~0.22 并加深暗角，缓解天际线洗绿。参数在 W7 域内脚本 const，无契约变更。
- **选项 2（推荐，中成本）**：canvas_item shader 加 `hint_screen_texture` 采样——亮度增益（对暗部 lift）+ 去饱和 + 绿磷光色调 + 保留扫描线/暗角。project.godot 无 renderer 覆盖 = **Forward+ 默认，支持 screen_texture**（已取证）。应急灯/力场等自发光体在增益下自然过曝发白 = 符合真实夜视仪光晕行为，共存问题一并解决。**注意**：CanvasLayer(100) 在 HUD 之下还是之上需实测（HUD layer 未取证，施工时核对，避免夜视膜盖住准星/血条或反之）。
- **选项 3（激进，高成本）**：WorldEnvironment 挂夜视专用 Environment（tonemap 白点拉低 + glow 增强）双 env 切换。与 C1 同源风险高，否决不推荐。

「萤」HUD 敌我识别（07 美术设定核心创新）依赖夜视下宿主轮廓中心暗斑——选项 2 的亮度增益是暗斑可见性的**前置条件**（现占位 overlay 暗部无增益，暗斑无从谈起），故推荐选项 2 与 Phase 2 夜视热斑换皮同批施工。

---

## 五、契约变更申请（按协同协议第 3 条，只申请不落地）

### 申请 1：game_config.gd 新增「街区图昼间预设」参数段（方案 A 依赖）

```
# ===== 街区图昼间预设（street_day_night_driver 专用；c1m1 剧情态恒为夜，DAY 仅美术对照）=====
STREET_DAY_SKY_TOP_COLOR      ≈ Color(0.35, 0.55, 0.85)   # 昼间天空顶色（蓝调→昼间蓝）
STREET_DAY_SKY_HORIZON_COLOR  ≈ Color(0.65, 0.72, 0.80)   # 地平线雾霭色
STREET_DAY_AMBIENT_ENERGY     ≈ 1.0                        # Sky 环境光能量（夜 0.38 → 昼）
STREET_DAY_SUN_COLOR          ≈ Color(1.0, 0.95, 0.85)    # 日光色（沿用 controller DAY 值）
STREET_DAY_SUN_ENERGY         ≈ 1.2
STREET_DAY_SKYLINE_EMISSION_SCALE ≈ 0.15                   # 天际线窗灯昼间衰减因子
```

数值为探讨稿，冻结前可依据白天截图 A/B 调整；**白天雾直接复用既有 `FOG_*` 契约，不新增**。

### 申请 2：events.gd 新增 `day_night_mode_changed(mode: int)` 信号（低优先级，可缓）

理由：未来 UI（时钟/任务简报）与音频（昼间环境声）若需感知昼夜，走总线优于直引驱动器。本期驱动器仅本地信号即可运转，**若蜂后认为 YAGNI 可驳回**（当前零消费方，符合翻车模式②警戒线）。

### 不申请项（明示）

- 不动 `NIGHT_FOG_*`（机主护栏）、不动 `EMERGENCY_*`、不动 `GameState.is_night` 语义。
- 夜视升级选项 2 的参数（增益/去饱和度）暂留 W7 域脚本 const，待正式施工时视情契约化。

---

## 六、施工排期建议与验收标准（评审通过后生效）

| 步骤 | 内容 | 验收 |
|------|------|------|
| S1 | 蜂后裁决：方案 A + 契约申请 1（+申请 2 可选）+ 夜视选项 | 本文件批注 |
| S2 | W7 写 `street_day_night_driver.gd/.tscn`（NIGHT 零差异 + DAY 预设） | L1 全绿；`--check-only` 过 |
| S3 | 蜂后/W4 在 street_test.tscn 加一行 instance（W7 不动该文件） | diff ≤ 2 行 |
| S4 | 零回归验证：NIGHT 默认态截图 vs 挂驱动器前截图逐像素对比 | **像素级一致**（或仅 Filmic tonemap 抖动级差异） |
| S5 | DAY 态截图验证（OverviewCamera 现机位 + E1 门前机位各一张）；夜雾护栏复查（DAY 不写 NIGHT_FOG） | 天际线/力场/应急灯无异常；audit_map A/B/C 全零（环境改动不触碰撞，理论上零影响，仍跑一遍兜底） |
| S6 | 夜视升级（若批准选项 2）单独排期，不与 S2–S5 混批 | 「萤」暗斑可读性由蜂后/机主目测 |

截图纪律遵守：OverviewCamera transform 用完恢复 `Transform3D(1,0,0, 0,1,0, 0,0,1, 0,1.7,20)`；白天对照照不提交进 git（存 modeling/ 审计目录，同 audit-0927 先例）。

---

## 七、风险与开放问题

1. **编号撞车**：`05-` 前缀与 EDAA 评估文档重复（见文首），请蜂后定夺最终文件名。
2. **street_test 定位**：该场景当前是预览/审计场（fly_camera + 工具链 dump/audit 均实例化它），并非玩家可玩图入口（main.tscn 是 G2 灰盒）。驱动器挂在 street_test 属**预演集成**；正式 c1m1 玩家动线入场时（任务链移植），驱动器随场景迁移即可，无需二次设计——但迁移时点需蜂后在地图序列计划（12-map-sequence-plan.md）中统筹。
3. **DAY 态的「固化夜景」冲突**：street_builder 注释明示本图固化蓝调夜景。本方案的 DAY 态**不改变这一剧情定位**（默认 initial_mode=NIGHT，无玩法入口切白天），仅提供美术对照与未来复用能力。若蜂后认为 c1m1 根本不需要 DAY 态，可裁剪为「NIGHT-only 驱动器 + 夜视升级」，S2 工作量减半。
4. **多 WorldEnvironment 遗留**：greybox_arena 的 controller 与未来 main 流程的昼夜接管关系，属 G4 后集成议题，本期不展开。

---

*本文档为只读调研产物；施工待蜂后评审。取证文件清单：street_test.tscn / street_builder.gd / street_layout_test.gd / skyline_builder.gd / day_night_controller.gd(.tscn) / day_night_demo_controller.gd / night_vision_overlay.gd / emergency_light 契约段 / game_config.gd / game_state.gd / events.gd / player_controller.gd / mat_energy_field.gdshader / skyline_windows.gdshader / project.godot。*
