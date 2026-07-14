# 03 · Godot 4.6.2 重写可行性评估报告

> 评估对象：`E:\Github Project\Nagi_Games\Ruins-Breakout\index.html`（3502 行，Three.js r128 + Cannon.js 0.6.2 单页 3D 射击游戏）
> 评估环境：本机 Godot `4.6.2.stable.official.71f334935`（已用 `--headless --version` 实测确认），位于 `D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe`
> 结论性质：本报告**不修改任何游戏源文件**，仅产出设计与估算。

---

## 一、结论先行（TL;DR）

1. **Godot 无法"包装"现有 Web 技术栈。** Godot 是原生引擎，不能加载 Three.js/Cannon.js，也不能直接运行 `index.html`。走 Godot 这条路 = **用 GDScript 把整个游戏从零重写一遍**，等同于立项一个"原生重制版"新项目，而不是"移植/打包"。
2. **本次桌面化（要一个能跑的 Windows .exe）不推荐 Godot。** 目标是"尽快得到 .exe 且行为与原作一致"，Electron 包装路线约 **4–8 人日**即可交付且 100% 保真；Godot 重写路线粗估 **45–70 人日（约 2–3.5 人月）**，且手感/物理/渲染三大维度都难以 1:1 复刻。
3. **Godot 真正的价值在"未来原生重制版"。** 当目标是"做一个画质、手感、性能全面升级的 PC 原生版"时，Godot 4.6 非常合适，且其**导出 .exe 的流程本身极简**（装导出模板 → 加 Windows Desktop preset → 一键导出，见 §六）。
4. 重写难度最大的三块是：**程序化建模重建**、**敌人 AI 状态机**、**物理行为复刻**；最简单的三块是：**药包/雷区**、**HUD 与菜单**、**直升机撤离流程**。

---

## 二、为什么 Godot 不能"直接包装"——技术边界

| 维度 | 现状（Web） | Godot 4.6 | 能否直接复用 |
|------|-------------|-----------|--------------|
| 渲染 | Three.js r128（WebGL） | RenderingServer / Forward+ / Mobile / Compatibility 渲染器 | ❌ 不可复用，需重建场景与材质 |
| 物理 | Cannon.js 0.6.2 | Godot Physics 3D / Jolt（4.6 内置可选） | ❌ 不可复用，需重建刚体并重新调校 |
| 逻辑 | 内联 JavaScript | GDScript（或 C# / C++ GDExtension） | ❌ 需逐函数翻译为 GDScript |
| UI | HTML/CSS/Tailwind DOM | Control 节点 / CanvasLayer / Theme | ❌ 需用 Control 节点重做 |
| 输入 | Touch Events（触屏） | Input Map / InputEventMouseMotion / Pointer Lock | ❌ 桌面端本来就要改键鼠 |
| 资源 | `img/title-bg.jpg`、程序化几何 | 可复用图片；几何需重建 | ⚠️ 仅图片可复用 |

**关键判断**：原作唯一的"资产"是 `img/title-bg.jpg` 和大量**程序化建模代码**（用 `BoxGeometry`/`CylinderGeometry` 等手工拼出步枪、火箭筒、碉堡、直升机）。这些代码在 Godot 里要么重写为 GDScript 即时生成 `ArrayMesh`，要么在编辑器里用 `MeshInstance3D` + 基础网格重新搭建——无论哪种都是**重做**，不是**搬运**。

---

## 三、游戏子系统清单 → Godot 4.6 映射 → 工作量分级

> 工作量分级口径：**小**（0.5–2 人日，逻辑直译即可）/ **中**（2–5 人日，需重新设计或调校）/ **大**（5 人日以上，复杂逻辑或大量资源重建）。
> 行号指 `index.html` 中的位置。

### 1. Three.js 渲染 / 场景 / 光照
- **原作实现**（行 290–310）：`Scene` + `PerspectiveCamera(75°)` + `WebGLRenderer`（开阴影、`autoClear=false`）；`AmbientLight(0x111122, 0.15)` + 主平行光 `moonLight(0xaaccff, 0.4)`（2048 阴影贴图）+ 补光 `fillLight(0x223344, 0.1)`。
- **程序化建模**（行 490–651、1487–2300 等）：步枪 `createWeapon`、火箭筒 `createRPG`、直升机 `createHelicopter`、碉堡 `createBunker`、各类掩体（`createAbandonedCar`/`createBoulder`/`createConcreteWall`/`createBarrel`/`createTreeCover`）全部用基础几何手工拼装。
- **Godot 对应**：`Node3D` 场景树 + `MeshInstance3D`（`BoxMesh`/`CylinderMesh`/`SphereMesh`）+ `Camera3D` + `DirectionalLight3D`（开 `shadow_enabled`）+ `WorldEnvironment`（环境光/色调映射）。
- **工作量：大（8–12 人日）**。模型数量多且全部代码化，需逐个在 Godot 中重建并对齐比例/材质。

### 2. 夜视 / 热融合后处理
- **原作实现**：`toggleNightVision`（行 375–400）切换 `scene.background` 为天蓝、抬高各光强、加蓝色 `#nvOverlay`；`updateThermalVision`（行 361–373）把敌人材质 `emissive` 设为白色实现"发热高亮"。
- **Godot 对应**：`WorldEnvironment.environment`（切 `background_mode`/环境光能量）+ 给敌人 `StandardMaterial3D.emission_enabled` + 全屏 `ColorRect` 叠色；进阶可用 `Compositor` 或屏幕 `Shader` 做真正的热成像 LUT。
- **工作量：中（2–3 人日）**。思路一致，但 Godot 的色调映射/环境光模型不同，要调出"同样观感"需反复比对。

### 3. Cannon.js 物理 / 碰撞
- **原作实现**：
  - 世界与地面：`CANNON.World` + `gravity(0,-9.82,0)`（行 312–313）、地面 `Plane` 静态体（行 319–322）、所有障碍 `physicsBodies[]`（`addObstacle` 行 332–337）。
  - **玩家不走物理引擎**：`updateMovement`（行 3149–3192）用手写 AABB 检测 `checkObstacleCollision`（行 3116–3147）+ 逐轴滑动（先 X 后 Z）+ 固定速度（腰射 0.15 / 趴下 0.08 / 瞄准 0.05）。
  - **敌人走物理引擎**：`Enemy` 用 `CANNON.Body(mass 80, Cylinder, fixedRotation, linearDamping 0.9)`（行 961–964），靠 `velocity` 驱动、`syncPosition`（行 1018–1026）回写。
  - **火箭弹不走物理引擎**：`updateRocket`（行 2864–2911）手写弹道（`velocity.y -= 9.8*dt`）+ `Raycaster` 碰撞。
- **Godot 对应**：玩家用 `CharacterBody3D.move_and_slide()`；障碍用 `StaticBody3D` + `CollisionShape3D`；敌人用 `CharacterBody3D` 或 `RigidBody3D`；火箭弹用 `PhysicsRayQueryParameters3D` 或继续手写弹道（反而更易 1:1）。
- **工作量：中（5–8 人日）**。引擎 API 齐全，但**手感与走位节奏必须重新调校**（见 §五 风险 1/2）。

### 4. 武器系统（步枪 + 火箭筒）
- **原作实现**：步枪 `shoot()`（行 2685–2759）`Raycaster` 从相机发射，散布（腰射 0.004 / 瞄准 0.0005 / 趴下 0.002）、爆头 50 / 身体 25、射程 100、弹匣 30/备弹 150、连发 100ms；后坐力 `updateWeaponRecoil`（行 2914–2947）+ 镜头抖动 `updateScopeShake`（行 2948–2968）；火箭筒 `fireRPG`（行 2809–2912）+ RPG 镜下坠线 `updateRPGScope`（行 2791–2807，按 50/100/200m 计算弹道下坠）；换弹 `reload`（行 2530–2541）+ 三段弹匣动画 `playReloadAnimation`（行 2542–2597）；切枪 `weaponBtn`（行 2484–2510）。
- **Godot 对应**：`PhysicsRayQueryParameters3D`（`PhysicsServer3D.space_get_direct_state().intersect_ray()`）做命中判定；`Camera3D` 抖动 + 武器 `Node3D` 位移做后坐力；弹道用 GDScript 积分；下坠线用 `Control._draw()` 或 `Line2D`。
- **工作量：中（4–6 人日）**。命中/弹道逻辑可直译；后坐力/散布的"手感数值"需重调。

### 5. 敌人 AI（步兵 / 机枪手 / 狙击手 三类）
- **原作实现**：
  - `Enemy`（行 949–1253）：状态机 `PATROL / ALERT / TAKE_COVER / PEEK / ENGAGE`（`switch` 在行 1009–1015），含找掩体 `findNearestCover`、埋伏 `ambushMode`、撤离防守 `extractMode`、连发 `maxBurst`、节流视线检测 `checkLineOfSight`（每 2/60s 一次）、群体警报 `alertNearbyEnemies`（行 2761–2789，40m 范围）。
  - `MachineGunner`（行 711–875）：固定位置、弹匣 100/换弹 10s、碉堡机枪 `isBunkerMG` + 玩家趴下 7s 延迟才停火（`proneDelayTimer`）。
  - `Sniper extends MachineGunner`（行 876–948）：高台、只打静止目标（读 `playerStillTime`）、`lethal` 模式。
- **Godot 对应**：GDScript 状态机（`enum State` + `match`，可直接套用本机 `godot-best-practices` 技能的 `state-machine.gd.md` 模板）；视线检测用 `intersect_ray()`；寻路可用 `NavigationAgent3D` + 烘焙 `NavigationRegion3D`，但原作仅"直线移动 + 预设掩体点"，**不必上完整 navmesh**，用目标点插值即可。
- **工作量：大（6–10 人日）**。状态机结构清晰、可直译，但**视线/掩体/警报/连发节奏的数值**要在新物理与渲染下重新调。

### 6. 直升机呼叫 / 撤离流程
- **原作实现**：`callHelicopter`（行 3366–3421）需在撤离点 15m 或小屋 6m 内、60s 倒计时、呼叫 3s 后刷 2 个狙击手；`animateHelicopter`（行 3423–3435）60s 从 y=50 降到 y=3 + 旋翼旋转；`missionComplete`（行 3208–3241）相机升到 y=40 显示撤离成功。
- **Godot 对应**：`Area3D` 检测进入撤离区 + `Timer` 倒计时 + `Tween` 做直升机下降/相机上升 + 旋翼 `Node3D` 旋转。
- **工作量：小–中（2–3 人日）**。流程清晰，Tween 实现比手写 rAF 更简洁。

### 7. 小地图 / 大地图 UI
- **原作实现**：大地图 `drawFullMap`（行 2598–2683）用 Canvas2D 自绘，`worldToCanvas` 坐标映射，画北/南墙、分隔墙、碉堡、小屋、撤离点、玩家，并遍历 `physicsBodies` 画全部障碍；小地图/血量 HUD（行 185–211）用 SVG 身体部位 + 血条 + 头盔/护甲条。
- **Godot 对应**：大地图用 `Control._draw()`（`draw_rect`/`draw_circle`/`draw_line`）或 `SubViewport` + 俯拍 `Camera3D`；HUD 用 `CanvasLayer` + `TextureProgressBar`/`ProgressBar` + `Panel`。
- **工作量：中（4–6 人日）**。地图自绘逻辑可直译，HUD 重做工作量主要在版式对齐。

### 8. 药包系统
- **原作实现**：`Medkit` 类（行 653–685）浮动旋转、距离 <3 自动拾取；`useMedkit`（行 691–708）全部位 +50HP + 绿色治疗 overlay。
- **Godot 对应**：`Area3D`（`body_entered`）+ `Tween` 浮动；治疗逻辑直译。
- **工作量：小（0.5–1 人日）**。

### 9. 触屏 HUD / 输入（桌面端必改）
- **原作实现**：虚拟摇杆 `handleJoystickMove`（行 2413–2421）→ `Game.moveX/moveY`；9 个触屏按钮（fireBtn/aimBtn/reloadBtn/proneBtn/weaponBtn/callHeliBtn/medkitBtn/mapBtn/nvBtn）；视角用 `document.touchmove`（行 2365–2375）→ `rotX/rotY` + 灵敏度 `Config.viewSensitivity`。
- **Godot 对应**：`Input Map` 绑定 WASD/鼠标/数字键 + `InputEventMouseMotion` + `Input.mouse_mode = MOUSE_MODE_CAPTURED`（Pointer Lock）；HUD 按钮可全部移除或改为键盘提示。
- **工作量：中（2–3 人日）**。Godot 的键鼠 + Pointer Lock 是成熟路径，比"在 Web 上补键鼠"更顺手。

### 10. 程序化关卡生成
- **原作实现**：`createDividerBuilding`/`createBunker`/`createCabin`/`spawnRandomCabins`/`createNorthWall`/`createSouthWall`/`createRandomCover`/`spawnEnemies`/`createSniperTower`/`createEastExtension` 等（行 1487–2300），全靠代码生成掩体与敌人分布。
- **Godot 对应**：GDScript 生成 `MeshInstance3D` + `StaticBody3D`，或在编辑器预制 `.tscn` 关卡块后实例化。
- **工作量：大（4–6 人日）**。与 §1 建模强相关，是重制版的主要工程量之一。

### 11. 雷区（Minefield）
- **原作实现**：`Minefield` 类（行 1254–1335），`m.update(camera.position)` 触发 `explode`（行 1336–1379，火球/冲击波/碎片粒子 + 范围杀伤）。
- **Godot 对应**：`Area3D` 触发 + `GPUParticles3D`/`CPUParticles3D` 做爆炸特效 + 范围 `intersect_shape` 杀伤。
- **工作量：小（1 人日）**。Godot 粒子系统比手写 rAF 粒子更省工。

### 12. 游戏状态与主循环
- **原作实现**：全局 `Game` 对象（行 278）持有血量（头 35/躯 85/腿 65）、头盔 50、护甲 100、弹药、击杀数、各数组；主循环 `animate()`（行 3440–3491）含 FPS 统计、`world.step`、各 `update*`、`render`。
- **Godot 对应**：`GameState` Autoload 单例 + 各节点 `_physics_process(delta)` / `_process(delta)`。
- **工作量：小（1–2 人日）**。状态结构可直译为 GDScript 单例。

---

## 四、总体人日估算

| 模块 | 分级 | 人日（低–高） |
|------|------|---------------|
| 场景/渲染/程序化建模重建 | 大 | 8–12 |
| 光照/夜视/后处理 | 中 | 2–3 |
| 物理（玩家+敌人+弹道+碰撞） | 中 | 5–8 |
| 武器系统（步枪+火箭筒+后坐力+换弹） | 中 | 4–6 |
| 敌人 AI（三类+状态机+视线+掩体+警报） | 大 | 6–10 |
| 直升机呼叫/撤离流程 | 小–中 | 2–3 |
| UI（HUD/地图/血量/菜单） | 中 | 4–6 |
| 输入（键鼠映射 + Pointer Lock） | 中 | 2–3 |
| 程序化关卡生成 | 大 | 4–6 |
| 联调 / 手感调校 / 测试 | — | 6–8 |
| **合计** | | **45–67 人日** |

- **忠实重制（力求与原作观感/手感一致）**：约 **45–70 人日 ≈ 2–3.5 人月**。
- **最小可玩重制版（MVP，不求观感一致）**：约 **20–30 人日**。
- **对比 Electron 包装路线**：打包骨架 + 键鼠适配约 **4–8 人日**，且**行为与原作 100% 一致**（因为跑的就是原代码）。

> 量级结论：Godot 重写的人日约为 Electron 包装的 **8–12 倍**，且保真度反而更低。

---

## 五、三大保真风险

### 风险 1 · 手感（Game Feel）—— 高
原作的移动是**手写 AABB + 逐轴滑动 + 固定速度**（行 3149–3192），后坐力/镜头抖动是**手写数值**（行 2914–2968），视角是**触屏灵敏度曲线**（行 2365–2375，`deltaX*0.002*sens`）。Godot 的 `CharacterBody3D.move_and_slide()` 自带加速度/摩擦/碰撞响应模型，与手写固定步长手感差异明显；鼠标视角的灵敏度/加速曲线也要重做。**即便逻辑全对，"玩起来像不像原作"仍需大量真人试玩调校。**

### 风险 2 · 物理行为 —— 高
敌人靠 Cannon.js 0.6.2 的 `velocity` 驱动走位（行 961–1026），其阻尼、碰撞回弹、数值稳定性与 Godot 4.6 的 **Godot Physics 3D / Jolt** 差异显著。巡逻半径、找掩体走位、连发节奏都是在 Cannon 行为下"调出来"的，换引擎后这些**涌现行为会变**。火箭弹因是手写弹道反而容易复刻，但**敌人群体走位是最难 1:1 复刻的部分**。

### 风险 3 · 渲染观感 —— 中
Three.js r128 的 `MeshStandardMaterial` + 单平行光阴影 + "改背景色+提光照+emissive"的夜视，构成一种**朴素、偏暗的夜间战术观感**。Godot 4.6 默认 Forward+ 渲染器、色调映射（默认 AgX/Linear）、环境光、阴影级联完全不同，**默认观感会"更好"但也"更不像原作"**。要 1:1 需自定义 `Environment`/着色器并逐材质对齐；若接受"观感升级"则这条反而是收益而非风险——但这恰恰说明它已是"重制"而非"移植"。

---

## 六、若走"原生重制版"路线：Godot 4.6 导出 .exe 流程（本身极简）

重制路线一旦决定，Godot 的**打包导出是整条链路里最省事的一环**，步骤如下：

1. **安装导出模板**（一次性，需联网下载几百 MB）：
   - 编辑器菜单：`编辑器(Editor) → 管理导出模板(Manage Export Templates) → 下载并安装(Download and Install)`，选与本机一致的 `4.6.2.stable`。
   - 或手动下载 `Godot_v4.6.2-stable_export_templates.tpz` 放入 `%APPDATA%\Godot\export_templates\4.6.2.stable\`。
2. **添加 Windows Desktop preset**：
   - `项目(Project) → 导出(Export…) → 添加(Add…) → Windows Desktop`。
   - 设置可执行文件名、图标、`Architecture = x86_64`；可勾选 `Embed PCK` 生成**单文件 .exe**。
   - 该配置会写入项目根的 `export_presets.cfg`。
3. **一键导出**：`导出(Export) → 导出项目(Export Project…)`，选输出路径 → 生成 `游戏名.exe`（+ `.pck`，若未 embed）。
4. **命令行一键导出**（适合 CI / 脚本）：
   ```bash
   "D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe" \
     --headless --path "<项目目录>" \
     --export-release "Windows Desktop" "<输出路径>\RuinsBreakout.exe"
   ```
   - 前提：第 2 步已生成 `export_presets.cfg`，且导出模板已安装。

> 说明：导出流程本身**没有技术门槛**，真正的成本全部在前面的"重写"上。这也是"现在不用 Godot 打包、未来用 Godot 重制"这一结论的核心依据。

---

## 七、建议与决策矩阵

| 目标 | 推荐路径 | 人日 | 保真度 |
|------|----------|------|--------|
| **尽快拿到能跑的 .exe，行为与原作一致**（本次桌面化） | **Electron 包装**（见 `02-packaging.md`） | 4–8 | ★★★★★（跑原代码） |
| 做一个画质/手感/性能全面升级的 PC 原生版 | Godot 4.6 重写（本报告） | 45–70 | ★★（重写后是新游戏） |
| 既要原生性能又要快 | 暂不可行——没有"既包装又原生"的捷径 | — | — |

**最终建议**：
- **本次桌面化选 Electron**——用最低成本、100% 保真地交付 .exe，把"键鼠适配"作为唯一改动（见 `01-input-adaptation.md`）。
- **把 Godot 4.6 留给"原生重制版"立项**——届时本报告的子系统映射表（§三）可直接作为重制版的任务分解（WBS）与排期依据，导出流程（§六）即插即用。
- 若未来确定重制，建议先做一个 **2 周技术验证（spike）**：只重建"玩家移动 + 步枪射击 + 1 个敌人 + 1 段掩体"，用真实试玩验证 §五 的三大风险是否可接受，再决定是否投入 45+ 人日。

---

*报告完。所有行号与函数名均来自对 `index.html` 的实际阅读；Godot 版本号经本机 `--headless --version` 实测为 `4.6.2.stable`。*
