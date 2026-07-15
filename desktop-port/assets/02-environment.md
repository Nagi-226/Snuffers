# 02 · 环境与场景资产调研（废墟战场环境 · Godot 4.6.2 原生重制版）

> 调研人：环境与场景资产调研员（Kimi Work 桌面端）
> 调研日期：2026-07-15（UTC+8 本机实测网络）
> 适用范围：夜间废墟战场——残破建筑 / 掩体 / 碉堡 / 小屋 / 围墙 / 障碍、地面地形、战场杂物（沙袋 / 箱子 / 油桶 / 铁丝网）、远景天际线
> 法律口径：只推荐明确可商用授权（CC0 最佳；CC-BY 可用但需署名；MIT 可用）。CC-BY-SA（传染性）、CC-BY-NC / NC-ND（禁商用/禁改）、仅个人使用、无许可证声明 → 一律标记不可用。

---

## 一、结论先行（TL;DR）

1. **环境资产可以 100% 用 CC0 免费包拼齐主体，推荐组合 = Quaternius Downtown City MegaKit（建筑主体+天际线）＋ Kenney Graveyard Kit（废墟氛围：断墙/枯树/围栏）＋ KayKit Dungeon Remastered（破墙/碎石/箱桶障碍，GitHub 版）＋ Kenney Nature Kit（岩石/树木地形杂物）＋ Kenney Prototype Kit（军事灰盒补充）。** 五者全部 CC0、全部本机可达、全部有 glTF/GLB 可直接拖入 Godot 4。
2. **最大缺口是"现代军事杂物"**：沙袋、铁丝网、反坦克桩、混凝土碉堡、现代油桶在 CC0 低模包中覆盖不足，需**灰盒自制约 5–8 件**（BoxMesh 拼装+冷色材质即可，与低模风格天然兼容），或用 Sketchfab CC-BY 单品补（需署名）。
3. **网络事实（本机 2026-07-15 实测）**：`kenney.nl` ✅、`quaternius.com` ✅、`github.com` ✅、`kaylousberg.com` ✅、`sketchfab.com` ✅、`opengameart.org` ✅、`polyhaven.com` ✅、`ambientcg.com` ✅；**`itch.io` ❌（KayKit 主站）、`godotengine.org` ❌（含 Asset Library）、`poly.pizza` ❌**。KayKit 改用 **GitHub 官方仓库**（`github.com/KayKit-Game-Assets/*`，与 itch 版同内容同 CC0）即可完全绕开 itch.io。
4. **低模 × 夜战月光冷色调 = 天然适配**：三家 CC0 包全部使用小平面色板贴图（gradient atlas）/顶点色，大平直面在平行月光下明暗干净、剪影清晰；夜色浓雾还能掩盖远景细节不足。**唯一要做的是统一调色**——把各家色板往冷灰蓝方向重染（每包只有 1 张小色板图，改色工作量极小）。
5. **不要指望 Godot 编辑器内的 AssetLib 面板**（后端 godotengine.org 不可达），全部走"浏览器下载 zip / git clone → 拖入项目"的离线流程。

---

## 二、站点可达性实测（本机 · 中国大陆 · 2026-07-15 晚）

| 站点 | 状态 | 说明 |
|---|---|---|
| kenney.nl | ✅ 200 | Kenney 全部资产包页面与下载正常 |
| quaternius.com | ✅ 200 | Quaternius 官网与包页面正常（`/packs/*.html`） |
| github.com | ✅ 200 | KayKit 官方仓库、KenneyNL 官方仓库均可用 |
| kaylousberg.com | ✅ 200 | KayKit 作者官网（JS 渲染，内容以 GitHub 为准） |
| sketchfab.com | ✅ 200 | 浏览/搜索正常；**下载需注册登录**；API 可用 |
| opengameart.org | ✅ 200 | 备用 CC 资产站 |
| polyhaven.com | ✅ 200 | CC0 HDRI 天空/贴图（夜空用） |
| ambientcg.com | ✅ 200 | CC0 PBR 贴图（地面用） |
| **itch.io** | ❌ 超时 | **KayKit 主发行站不可达 → 改用 GitHub 镜像** |
| **godotengine.org** | ❌ 超时 | **Asset Library 不可达 → 编辑器内 AssetLib 面板不可用** |
| **poly.pizza** | ❌ 超时 | Quaternius 镜像站不可达 → 用 quaternius.com 直链替代 |

---

## 三、首选推荐（全部 CC0 · 已逐条验证）

### 3.1 Quaternius Downtown City MegaKit —— 残破建筑主体 + 远景天际线【首选】

| 字段 | 内容 |
|---|---|
| 名称 | Downtown City MegaKit |
| 平台 | quaternius.com |
| URL | https://quaternius.com/packs/downtowncitymegakit.html |
| 许可证 | **CC0**（页面明示 "Free to use in personal, educational and commercial projects"） |
| 格式 | 免费层：**OBJ / FBX / glTF**；付费 Source 层追加：.blend + **Godot 4.5 工程**（含磨损着色器、简易碰撞） |
| 含动画否 | 否（纯环境） |
| 风格 | 低多边形模块化城市（波士顿/纽约街区），300+ 件：楼体模块、街道、人行道 |
| Godot 4 导入 | 免费层：下载 zip → 取 glTF 文件夹拖入 `res://` 即可。Source 层（如日后购买）：直接给 Godot 工程，含**顶点色控制磨损（wear）+ 假窗内透着色器 + 定制简易碰撞**——做"战损城市"极省心 |
| 中国可达性 | ✅ 官网直连可下载，无需登录 |
| 夜战适配 | ★★★★★ 模块化楼体可拼出"半塌街区"；免费层可用深色材质重染；Source 层的 wear 顶点色正好做残破感。远处摆几栋楼 + 雾 = 现成的**天际线剪影**。窗户自发光可关可开（夜里零星亮窗反而出氛围） |

> 备注：免费层 = 整包 60–70% 的模型，完全够本作用量。Quaternius 新 MegaKit 系列（Medieval Village / Stylized Nature / Modular Sci-Fi）同一授权同一模式。

### 3.2 Kenney Graveyard Kit —— 废墟氛围包：断墙 / 枯树 / 围栏 / 石棺【首选】

| 字段 | 内容 |
|---|---|
| 名称 | Graveyard Kit（v5.0 完全重制版） |
| 平台 | kenney.nl |
| URL | https://kenney.nl/assets/graveyard-kit |
| 许可证 | **CC0**（页面明示 "Creative Commons CC0"） |
| 格式 | Kenney 3D 包统一含 **glTF（GLB）/ OBJ / FBX** + PNG 色板贴图（Godot 教程与镜像站交叉验证） |
| 含动画否 | 页面标注 🎞️Animation（少量，如门/灯笼类） |
| 风格 | 低多边形墓地：墓碑、石棺、**破损墙体、铁艺围栏、枯树**、灯笼、枯枝——死亡/破败元素密度最高的 CC0 包 |
| Godot 4 导入 | zip 解压 → `Models/GLB format` 文件夹拖入项目，自动导入 |
| 中国可达性 | ✅ 直连 |
| 夜战适配 | ★★★★★ 题材即夜景：枯树剪影、断墙轮廓在月光下极出效果；灯笼可做稀疏暖光点缀（与冷月光形成冷暖对比） |

### 3.3 KayKit Dungeon Remastered（GitHub 版）—— 破墙 / 碎石 / 箱桶障碍【首选】

| 字段 | 内容 |
|---|---|
| 名称 | KayKit: Dungeon Remastered 1.0 |
| 平台 | GitHub（KayKit-Game-Assets 官方账号；与 itch.io 版同内容） |
| URL | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 |
| 许可证 | **CC0**（仓库内 `LICENSE.txt` 原文确认：Creative Commons Zero，商用可，署名非强制） |
| 格式 | **glTF（.glb）/ FBX / OBJ+MTL** 三格式全给；仓库本身就是 **Godot addon 目录结构**（`addons/kaykit_dungeon_remastered/Assets/...`） |
| 含动画否 | 否 |
| 风格 | 低多边形地牢：**200+ 件，含 wall_broken / wall_cracked / wall_scaffold（破墙/裂墙/脚手架墙）、rubble_large / rubble_half（瓦砾堆）**、木桶、木箱、路障 barrier、地板、楼梯、火把 |
| Godot 4 导入 | `git clone` 或下 zip → 把 `addons/kaykit_dungeon_remastered` 拷进项目；或直接拖 `Assets/gltf/*.glb` |
| 中国可达性 | ✅ GitHub 直连（**绕开不可达的 itch.io**） |
| 夜战适配 | ★★★★☆ 破墙+瓦砾是废墟战场刚需；石墙冷灰底色天然贴合夜战；火把 lit 变体可做点位暖光。注意箱桶为木质中世纪风，现代战场里当"杂物"可以，当"军需箱"略出戏 |

### 3.4 Kenney Nature Kit —— 岩石 / 树木 / 地形杂物【首选】

| 字段 | 内容 |
|---|---|
| 名称 | Nature Kit |
| 平台 | kenney.nl |
| URL | https://kenney.nl/assets/nature-kit |
| 许可证 | **CC0** |
| 格式 | glTF（GLB）/ OBJ / FBX + PNG 色板 |
| 含动画否 | 否 |
| 风格 | 低多边形自然：**330 个文件**——岩石（大/小/层叠）、树木、灌木、草丛、蘑菇等 |
| Godot 4 导入 | zip → GLB 文件夹拖入 |
| 中国可达性 | ✅ 直连 |
| 夜战适配 | ★★★★☆ 岩石当战场天然掩体、地形起伏点缀；树木选枯枝/针叶类配夜景。注意绿色系叶片在冷光下会偏灰绿——正好显荒凉 |

### 3.5 Kenney Prototype Kit + Prototype Textures —— 军事灰盒补充【首选·补缺口用】

| 字段 | 内容 |
|---|---|
| 名称 | Prototype Kit（145 文件）/ Prototype Textures |
| 平台 | kenney.nl |
| URL | https://kenney.nl/assets/prototype-kit 、 https://kenney.nl/assets/prototype-textures |
| 许可证 | **CC0** |
| 格式 | glTF / OBJ / FBX（Kit）；PNG 网格/数字贴图（Textures） |
| 含动画否 | Kit 含少量动画 |
| 风格 | 灰盒/白模几何件：墙、坡、方块、障碍、数字标尺贴图 |
| Godot 4 导入 | 拖入即用 |
| 中国可达性 | ✅ 直连 |
| 夜战适配 | ★★★★☆ **专门用来补"现代军事缺口"**：沙袋墙、铁丝网支架、反坦克桩、混凝土碉堡先用灰盒拼，贴深灰冷色材质即可混入低模场景；后期若有余力再替换成精制模型 |

---

## 四、备选清单（按需取用）

### 4.1 Kenney 系（全部 CC0 · ✅ 直连 · glTF/OBJ/FBX）

| 名称 | URL | 文件数 | 用途定位 | 夜战适配 |
|---|---|---|---|---|
| Castle Kit（v2.0 重制） | https://kenney.nl/assets/castle-kit | 75 | **石墙/塔楼/城门 → 碉堡与围墙的最近替代**；石质冷灰贴夜景合适 | ★★★★ |
| City Kit (Suburban)（v2.0 重制） | https://kenney.nl/assets/city-kit-suburban | 40 | 低模民居 → 原作"小屋"的直接替换 | ★★★★ |
| City Kit (Roads) | https://kenney.nl/assets/city-kit-roads | — | 路面/街块，配 Downtown 用 | ★★★ |
| Survival Kit（v2.0 重制） | https://kenney.nl/assets/survival-kit | 80 | 营地杂物：帐篷、篝火、箱桶、工具 → 战场临时营地 | ★★★★ |
| Fantasy Town Kit | https://kenney.nl/assets/fantasy-town-kit | — | 中世纪民居/围墙，废墟村庄感 | ★★★ |
| Tower Defense Kit | https://kenney.nl/assets/tower-defense-kit | — | 含少量军事风塔/障碍，可淘 | ★★★ |

> Kenney 全站统一 CC0、统一小色板贴图，**跨包混搭风格零冲突**，是"风格统一易凑齐"要求下的最安全底座。

### 4.2 Quaternius 系（全部 CC0 · ✅ 直连）

| 名称 | URL | 模型数 | 格式（免费层） | 用途定位 |
|---|---|---|---|---|
| Medieval Village MegaKit | https://quaternius.com/packs/medievalvillagemegakit.html | 300+ | OBJ/FBX/**glTF** | 网格化模块村庄：墙/顶/楼梯/藤蔓；Source 层有磨损色+碰撞（付费） |
| Stylized Nature MegaKit | https://quaternius.com/packs/stylizednaturemegakit.html | 116 | OBJ/FBX/**glTF** | 40 树 / 27 岩石 / 35 植物；吉卜力风偏鲜亮，夜战建议**只取岩石**或把树叶换秃 |
| Modular Streets | https://quaternius.com/packs/modularstreets.html | 25 | **仅 FBX/OBJ/Blend（老包无 glTF）** | 街道模块；需 FBX2glTF 或 Blender 转换（Godot 4.3+ 内置 ufbx 也可直读 FBX） |
| Buildings（老包） | https://quaternius.com/packs/buildings.html | 9 | 仅 FBX/OBJ/Blend | 少量楼体，同上需转换 |

> Quaternius 老包（2021 前）免费层没有 glTF，优先选 MegaKit 新系列。

### 4.3 KayKit 系（GitHub · 全部 CC0 · Godot addon 结构 · glTF/FBX/OBJ）

| 名称 | URL | 用途定位 |
|---|---|---|
| City Builder Bits | https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0 | 卡通城市建筑 building_A–D、长椅、箱子 → 民居/街景补充（309 文件） |
| Prototype Bits | https://github.com/KayKit-Game-Assets/KayKit-Prototype-Bits-1.0 | 灰盒原型件，与 Kenney Prototype Kit 二选一 |
| Medieval Hexagon Pack | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 | 六边形地形块，若想做战棋式地块可考虑 |
| Halloween Bits | https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0 | 墓碑/枯树/南瓜等阴森杂物，废墟氛围补充 |

### 4.4 Godot 官方 Asset Library【当前不可用】

- `godotengine.org` 本机**不可达**（2026-07-15 实测超时），编辑器内 AssetLib 面板同步失效。
- 替代策略：Asset Library 里的大部分条目（含 Kenney/Quaternius 搬运）本来就托管在 GitHub，**直接用本文 GitHub 直链即可覆盖需求**，不构成实质损失。若日后有代理，可再补逛。

### 4.5 GitHub 上的 Godot 兼容仓库（MIT 许可 · 可商用）

| 名称 | URL | 许可证 | 说明 |
|---|---|---|---|
| KenneyNL/Starter-Kit-City-Builder | https://github.com/KenneyNL/Starter-Kit-City-Builder | **MIT** | **Godot 4.6 工程**（与本机 4.6.2 同代）：城市建造模板，含 CC0 建筑模型 + **动态 MeshLibrary 生成**——本作若走"模块化摆楼"路线，这套代码可直接参考 |
| KenneyNL/Starter-Kit-FPS | https://github.com/KenneyNL/Starter-Kit-FPS | **MIT** | Godot 4.6 FPS 模板：角色控制器/武器/敌人框架，含 CC0 模型——交给武器/角色调研员深挖 |
| KenneyNL/KayKit-Hexagons | https://github.com/KenneyNL/KayKit-Hexagons | **MIT** | 六边形地块素材 |

> 搜索结论：GitHub 上"godot environment assets / low poly ruins"直搜**没有高星、许可证干净的现成废墟环境包**；零星仓库多为无许可证声明（法律默认保留所有权利 = 不可用）或风格不符。故 GitHub 方向收敛为"KayKit 官方仓库 + KenneyNL 官方模板"两个可信源头。

### 4.6 Sketchfab CC 授权单品【备用·需逐个核授权·需登录】

- 可达性：✅ 浏览正常；**下载需注册账号**；站内授权混杂，**必须勾选 Downloadable 且逐件确认是 CC0 / CC-BY**。
- 实测搜索（API 2026-07-15）："low poly ruins" 高赞结果多为 **CC-BY**（可用，须署名），例如 *Ancient Ruins ARC - (Low Poly)*（https://sketchfab.com/3d-models/d6ae5d9b0a2f4ac582965e0dda9e4f2e，CC-BY）、*Desert ruins*（https://sketchfab.com/3d-models/262c6748c7b0400899c613ce1933d9a3，CC-BY）；同时混入 **CC-BY-NC-ND（禁商用+禁改 → 不可用）**，例如 *Ruined Round Tower*（https://sketchfab.com/3d-models/debaa8213bd544afaa52432cede8bbce）。
- 风格警告：站内"废墟/废弃建筑"高赞结果大量是**摄影扫描（RAWscan 实景）**，面数高、写实风，与低模风格冲突——仅建议淘"现代军事杂物"单品（沙袋、油桶、路障），不建议当建筑主力。
- 用途定位：**只补 CC0 包缺的那几件现代军事杂物**，并在 `CREDITS.md` 登记署名。

### 4.7 地形与天空补充（CC0 · ✅ 直连）

| 名称 | URL | 用途 |
|---|---|---|
| Poly Haven | https://polyhaven.com | **夜空 HDRI**（WorldEnvironment 环境光/天空）+ 地面 PBR 贴图，全 CC0 |
| ambientCG | https://ambientcg.com | 泥地/碎石/柏油 PBR 贴图，CC0，做地形材质 |
| OpenGameArt | https://opengameart.org | 备用淘货站，授权含 CC0/CC-BY/GPL 混杂，需逐件核 |

> 地面地形建议：Godot 内置 PlaneMesh + 高度图位移，或 CSG/网格手搭低模地形 + ambientCG 碎石贴图；远景天际线用 Downtown City 楼体剪影 + 雾，**不需要专门的天空盒资产**，Poly Haven 一张夜空 HDRI 即可。

---

## 五、夜战 · 月光冷色调 · 观感适配专项评估

1. **低模是夜战的最优解**：Kenney/Quaternius/KayKit 三家都是"小平面色板贴图 + 平直面"。平行月光（`DirectionalLight3D` 冷蓝）打在大平直面上明暗边界干净，剪影清晰；夜间浓雾+深色环境光天然掩盖低模细节短板——**低模在夜里比白天更好看**。
2. **统一调色是唯一的必修课**：三家色板色相不同（Kenney 偏饱和、Quaternius 偏写实灰、KayKit 偏圆润卡通）。每包只有 1–2 张色板 PNG（如 KayKit 的 `dungeon_texture.png`），**用图片工具统一降饱和+加冷灰蓝，工作量以小时计**，即可让全场资产观感一致。配合 ACES/AgX 色调映射 + 冷色环境光效果更佳。
3. **冷暖对比做层次**：主体冷灰蓝（月光），稀疏布置 Graveyard Kit 灯笼 / KayKit 火把 lit 变体 / Downtown 亮窗等暖光点，夜景层次立刻出来；切忌全场暖光。
4. **原作程序化掩体的替换映射**：碉堡→Castle Kit 石墙塔楼 / 灰盒；混凝土墙→Downtown 墙面模块 / KayKit wall 系列；废弃车→（属载具调研员范围，此处略）；岩石→Nature Kit；树→Graveyard 枯树 / Nature Kit；小屋→City Kit Suburban；瓦砾→KayKit rubble。
5. **性能**：全部低模 + 共享材质，配合 Godot 4.6 的 `MultiMeshInstance3D`（岩石/树木/瓦砾批量散布）与 MeshLibrary + GridMap（模块化墙体），夜战场景同屏数千件无压力。

---

## 六、灰盒补充清单（必须自制的缺口件）

CC0 包查无以下现代军事件，建议灰盒自制（BoxMesh/CylinderMesh 拼装 + 冷灰材质，1 人日内可完成）：

1. 沙袋墙（堆叠圆角方块，或胶囊体压扁阵列）
2. 铁丝网（圆柱支架 + 半透明网格面片/简单螺旋管）
3. 反坦克桩/刺猬（三根方梁交叉）
4. 混凝土碉堡（原作 createBunker 的盒体结构直接升级为带倒角灰盒）
5. 现代油桶（圆柱+环箍，可作爆炸物）
6. 弹药箱/军需箱（方盒+盖）

> 底材用 Kenney Prototype Kit 贴数字网格贴图做"建设中"观感也成立；正式版统一罩深灰冷色材质即融入。

---

## 七、法律风险与缺口汇总

| # | 风险/缺口 | 等级 | 对策 |
|---|---|---|---|
| 1 | **现代军事杂物 CC0 缺口**（沙袋/铁丝网/反坦克桩/碉堡/油桶） | 中 | 灰盒自制（§六）或 Sketchfab CC-BY 单品补 + 署名登记 |
| 2 | **itch.io / godotengine.org / poly.pizza 不可达** | 低（已绕开） | KayKit 走 GitHub 官方仓库；Asset Library 用 GitHub 直链替代；poly.pizza 用 quaternius.com 直链 |
| 3 | **三家色板风格混搭不统一** | 中 | 统一重染色板（降饱和+冷灰蓝）+ 夜光下验收；Sketchfab 扫描件只零星用 |
| 4 | **Quaternius 老包免费层无 glTF**（FBX/OBJ/Blend） | 低 | 优先用 MegaKit 新系列；老包用 Godot 4.6 内置 FBX 导入或 FBX2glTF 转换 |
| 5 | **Sketchfab 授权混杂**（CC-BY / CC-BY-NC-ND / 标准授权） | 中 | 只下 Downloadable + CC0/CC-BY；NC/ND 一律排除；建立 CREDITS.md 署名台账 |
| 6 | 无许可证 GitHub 仓库（默认保留所有权利） | — | 一律不用，本文已剔除 |

---

## 八、首选 + 备选一览（速查）

**首选组合（5 条，全 CC0、全可达、全 glTF 直入）**

1. Quaternius Downtown City MegaKit —— 建筑主体 + 天际线 — https://quaternius.com/packs/downtowncitymegakit.html
2. Kenney Graveyard Kit —— 断墙/枯树/围栏废墟氛围 — https://kenney.nl/assets/graveyard-kit
3. KayKit Dungeon Remastered（GitHub）—— 破墙/瓦砾/箱桶障碍 — https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0
4. Kenney Nature Kit —— 岩石/树木地形杂物 — https://kenney.nl/assets/nature-kit
5. Kenney Prototype Kit —— 军事灰盒补充 — https://kenney.nl/assets/prototype-kit

**备选**：Kenney Castle Kit（碉堡/围墙）、Kenney City Kit Suburban（小屋）、Kenney Survival Kit（营地杂物）、Quaternius Medieval Village MegaKit（模块化村庄）、KayKit City Builder Bits（卡通建筑）、KenneyNL/Starter-Kit-City-Builder（MIT · Godot 4.6 模块化参考工程）、Sketchfab CC-BY 单品（军事杂物补缺）、Poly Haven + ambientCG（天空 HDRI / 地面贴图）。

---

*本文仅新增 `desktop-port/assets/02-environment.md`，未修改项目其他任何文件。所有许可证与可达性结论均基于 2026-07-15 本机实测与官网/仓库原文。*
