# 03 · 武器 / 载具 / 战场特效 资产调研

> 项目：废墟突围（Ruins Breakout）Godot 4.6.2 原生重制版
> 调研人：武器载具特效资产调研员（Kimi Work 子代理）
> 调研日期：2026-07-15（UTC+8）
> 美术方向：低多边形（low-poly）+ 夜战冷色光照；法律要求：仅 CC0 / CC-BY / MIT / Apache 等可商用授权

---

## 一、结论先行

### 首选推荐组合

| 槽位 | 首选 | 授权 | 一句话理由 |
|---|---|---|---|
| 武器模型主力 | **Quaternius Ultimate Guns Pack**（25 把枪，含步枪/狙击/火箭筒） | CC0 | GLB 直接拖入 Godot，风格与夜战低多边形完美统一，免署名可商用 |
| 武器系统 + 特效脚手架 | **Jeh3no / Godot-simple-FPS-weapon-system**（GitHub） | MIT | Godot 4.4–4.7 原生，含 5 种示例武器（手枪/突击步枪/霰弹/狙击/火箭筒）+ 枪口火光/弹孔/爆炸特效 + HUD，系统代码直接用，模型用 Quaternius 替换 |
| 撤离直升机 | **KumaSousa Low Poly Helicopter with animations**（itch.io） | CC0 | 低多边形、含动画（旋翼已分离可转）、62 KB FBX；备选 kazuma《Helicopter》（poly.pizza，CC0，FBX/GLTF） |
| 地雷 + 药包道具 | **Quaternius Toon Shooter Game Kit**（含地雷 Landmine、爆炸桶）+ **First Aid Kit / Pickup Health**（Quaternius） | CC0 | 与武器同风格同作者，一站式凑齐道具，含 FBX+glTF |
| 特效贴图 + 夜视 UI | **Kenney Particle Pack + Smoke Particles + Crosshair Pack + UI Pack Sci-fi** | CC0 | 共约 480 张粒子/准星/科幻界面贴图，GPUParticles3D 广告牌与 HUD 直接可用 |

### 关键风险与缺口

1. **直升机获取是最大网络缺口**：两个 CC0 首选（itch.io 的 KumaSousa、poly.pizza 的 kazuma）所在站点本机均不可达；quaternius.com 与 kenney.nl 均无直升机包。需通过代理/镜像，或改从 Sketchfab / BlendSwap（可达性未实测，发布前需验证）获取，或评估用 Quaternius 其他飞行器（Spaceships Pack）临时顶替。
2. **武器动画缺口**：Ultimate Guns Pack 为静态模型（无开火/换弹动画）；Quaternius Animated Guns Pack（6 把动画枪：P90/左轮/手枪/霰弹/狙击）仅提供 FBX/OBJ/Blend，无 GLB，需 FBX2glTF 或本机 Blender 转换。第一人称视口的枪械动画（摆动/后坐/换弹）建议主要靠 Jeheno 系统的程序化动画（bobbing/sway/recoil 已内置）解决。
3. **许可证核实残留**：Jeheno 系统内置武器模型来自 amaraha（itch.io，许可证未能核实，站点不可达）与 Sketchfab RPG-7（CC-BY，需署名）——建议只保留 Jeheno 的代码与 VFX，模型全部换成 Quaternius/Kenney 的 CC0 资产；PolyPack（Alstra Infinite）为自定义 FAL 许可（可商用+署名、禁止再分发原始资产），若采用需逐字读条款。

---

## 二、网络可达性实测（2026-07-15，本机 curl 直连）

| 站点 | 状态 | 备注 |
|---|---|---|
| quaternius.com | ✅ 可达（~2.3s） | 全部 Quaternius 包可直接下载 |
| kenney.nl | ✅ 可达（~1.9s） | 全部 Kenney 包可直接下载 |
| github.com | ✅ 可达（~0.4s） | GitHub 仓库无障碍 |
| opengameart.org | ✅ 可达（~1.6s） | 备选资产站可用 |
| poly.pizza | ❌ 不可达（两次超时） | 内容已经 Kimi 抓取服务核实；下载需代理/镜像 |
| godotengine.org / store.godotengine.org | ❌ 不可达 | Godot 资产库条目已核实；下载需代理/镜像 |
| itch.io | ❌ 不可达 | KumaSousa 直升机、amaraha 武器包受影哘 |

> 含义：**能直连下载的只有 Quaternius、Kenney、GitHub、OpenGameArt 四个来源**。推荐组合已优先向这四个来源倾斜；poly.pizza / Godot Store / itch.io 条目均标注⚠️，作为备选或需镜像获取。

---

## 三、武器类资产清单

| # | 名称 | 平台 / URL | 许可证 | 格式 | 含动画 | 风格 | Godot 4 导入说明 | 可达性 |
|---|---|---|---|---|---|---|---|---|
| W1 | **Ultimate Guns Pack**（25 把枪：AK47、步枪、狙击、火箭筒、霰弹、手枪等） | Quaternius · https://quaternius.com/ （首页 "Ultimate Guns Pack"）；镜像 https://poly.pizza/bundle/Ultimate-Guns-Pack-cpgUfI4t2F | **CC0** | FBX + GLB | 否（静态） | 低多边形写实枪械 | GLB 直接拖入 Godot 4；FBX 可经 4.3+ 内置 ufbx 或 FBX2glTF | ✅ quaternius.com 可达；⚠️ poly.pizza 镜像不可达 |
| W2 | **Animated Guns Pack**（6 把动画枪：P90、左轮、手枪、霰弹、狙击步枪等） | Quaternius · https://quaternius.com/packs/animatedguns.html | **CC0** | FBX / OBJ / Blend（无 GLB） | **是**（开火/换弹等） | 低多边形 | FBX 需 FBX2glTF 转换，或本机装 Blender 用 .blend 联动导出 glTF | ✅ |
| W3 | **Toon Shooter Game Kit**（角色 17 动画 + 敌人 + 环境 + **地雷 + 爆炸桶**） | Quaternius · https://quaternius.com/ ；镜像 https://poly.pizza/bundle/Toon-Shooter-Game-Kit-qraiSXoAru | **CC0** | FBX + glTF | 是（角色） | 低多边形卡通 | glTF 直接拖入；一站解决道具+配角 | ✅；⚠️ 镜像不可达 |
| W4 | Sci-Fi Modular Gun Pack（模块化 sci-fi 枪零件+成品） | Quaternius / poly.pizza · https://poly.pizza/bundle/Sci-Fi-Modular-Gun-Pack-TbRddR9Fsu | **CC0** | FBX + GLB | 否 | 科幻低多边形 | GLB 直接拖入；模块化可拼瞄具/消音器 | ⚠️（quaternius.com 同名包可达） |
| W5 | **Kenney Blaster Kit**（40 文件：blaster、消音器、投掷物、烟雾；v2.1） | Kenney · https://kenney.nl/assets/blaster-kit | **CC0** | glTF/OBJ/FBX 多格式（Kenney 3D 包标配，以下载包为准） | 是（标注 Animation）+ 变体 | 科幻卡通 | glTF 直接拖入；风格偏卡通科幻，作备选 | ✅ |
| W6 | Guns Asset pack（AK47 及变体、AWP、手枪、**四联火箭筒**、Mac10、火箭筒及变体贴图、霰弹枪、4 种子弹、闪光弹、手雷×2、**烟雾弹**、燃烧弹、弹药箱） | Godot Asset Store · styloo（https://store.godotengine.org/search/?query=%23weapons） | **CC0 1.0** | Godot 资源包 | 未标注 | 低多边形 | Godot 编辑器内 AssetLib 一键安装 | ⚠️ 商店不可达，需镜像 |
| W7 | 1960s Soviet Weapons [PSX]（AK47、SKS、PPSh-41、Tokarev、Makarov，部分含可动部件） | Godot Asset Store · radint | **Apache 2.0** | .glb | 部分可动 | PSX 复古 | GLB 直接拖入；风格与夜战粗粝感可作变体 | ⚠️ |
| W8 | RPG Launcher（RPG 火箭筒单件） | poly.pizza · austincford（用户页 https://poly.pizza/u/austincford） | **CC-BY**（需署名） | FBX / OBJ / GLTF | 否 | 低多边形 | GLTF 直接拖入 | ⚠️ |
| W9 | Low Poly RPG-7（3.6k 三角面） | Sketchfab · https://sketchfab.com/3d-models/low-poly-rpg-7-de967b52c9794d2995d4606749fcdff7 | **CC-BY**（需署名） | glTF（Sketchfab 下载） | 否 | 低多边形写实 | glTF 直接拖入；Jeheno 系统内置同款 | ⚠️（可达性未实测） |
| W10 | Oldschool AFPS Weapons（9 把竞技场射击武器：火箭筒、榴弹、狙击等） | OpenGameArt · https://opengameart.org/content/oldschool-afps-weapons | **CC0** | OBJ（静态，1024² 贴图） | 否 | 复古低多边形 | OBJ 可导入但建议转 GLB | ✅ |
| W11 | Free Low Poly Weapons Pack（Jeheno 内置武器模型来源） | itch.io · https://amaraha.itch.io/free-low-poly-weapons-pack | **未能核实**（itch.io 不可达） | — | — | 低多边形 | 不建议直接使用，待核实 | ⚠️ |

**排除/不可用**：BlendSwap 上部分 RPG-7 为 CC-BY（可用但非首选）；CGTrader/Sketchfab 商店付费条目与无许可声明条目一律排除；Ishikawa1116《LOW POLY GUNS' ATTACHMENTS & OPTICS》（poly.pizza，$17 付费）排除。

---

## 四、载具（撤离直升机）清单

| # | 名称 | 平台 / URL | 许可证 | 格式 | 含动画 | 旋翼分离 | 风格 | Godot 4 导入 | 可达性 |
|---|---|---|---|---|---|---|---|---|---|
| V1 | **Low Poly Helicopter with animations**（KumaSousa） | itch.io · https://kumasousa.itch.io/low-poly-helicopter-with-animations | **CC0** | FBX（62 KB） | **是**（含动画，旋翼应为独立节点） | 预期已分离（带动画） | 低多边形（Imphenzia 风） | FBX 经 4.3+ ufbx 或 FBX2glTF；旋翼挂点旋转动画可直接播放 | ⚠️ itch.io 不可达，需镜像 |
| V2 | Helicopter（kazuma） | poly.pizza · https://poly.pizza/m/EQJ2MECUbx | **CC0** | FBX / GLTF | 否 | 未核实（需下载后确认，低模通常旋翼为独立 mesh，可在 Godot 内对旋翼节点加旋转） | 低多边形 | GLTF 直接拖入 | ⚠️ |
| V3 | PolyPack Planes & Choppers（5+ 飞机/直升机，Alstra Infinite） | poly.pizza（Free!）/ Godot Asset Store / Unity Asset Store | **FAL 自定义**（可商用+署名；禁止转售/再分发原始资产） | GLB/OBJ 等 | 未标注 | 未核实 | 低多边形 | GLB 直接拖入 | ⚠️ |
| V4 | Helicopter（Poly by Google） | poly.pizza（见 Race kit 合集引用） | **CC-BY 3.0**（需署名） | GLTF/OBJ | 否 | 未核实 | Google Poly 低多边形 | GLTF 直接拖入 | ⚠️ |

> 备注：Quaternius 现有载具包（Cars / Ships / Animated Tanks / Public Transport / Spaceships）**均无直升机**；Kenney Car Kit（https://kenney.nl/assets/car-kit，CC0，✅可达）只有汽车/卡丁车，可作地面载具备选但与本作需求无关。旋翼旋转动画实现成本低（Godot 内对旋翼节点 `rotate_y()` 即可），**"旋翼是否分离"比"是否带飞行动画"更重要**——V1 已带动画最省事；V2–V4 若为整体网格需在 Blender 里花 5 分钟拆旋翼。

---

## 五、道具（地雷 / 药包）清单

| # | 名称 | 平台 / URL | 许可证 | 格式 | 含动画 | 风格 | Godot 4 导入 | 可达性 |
|---|---|---|---|---|---|---|---|---|
| P1 | **Landmine（地雷，Quaternius）** | poly.pizza · https://poly.pizza/m/PtqkseZo9O ；亦含于 Toon Shooter Game Kit（W3） | **CC0** | FBX / GLTF | 否 | 低多边形 | GLTF 直接拖入 | ⚠️ 单件页不可达；**W3 整包可从 quaternius.com 直下（✅）** |
| P2 | **First Aid Kit（药包，2 款）/ Pickup Health / Health（Quaternius）** | poly.pizza 搜索 "first aid" 前 4 条均为 Quaternius | **CC0** | FBX / GLTF | 否 | 低多边形 | GLTF 直接拖入 | ⚠️；可经 quaternius.com 包获取 |
| P3 | Survival Pack（53 模型，含 First Aid 急救类 + 生存道具） | Quaternius · https://quaternius.com/packs/survival.html | **CC0** | FBX / OBJ / Blend | 是 | 低多边形 | FBX 需转换；量大可顺带取帐篷/补给点缀场景 | ✅ |
| P4 | Kenney Survival Kit（3D 生存包） | Kenney · https://kenney.nl/assets （All-in-1 列表确认存在） | **CC0** | glTF/OBJ/FBX | 未标注 | 低多边形 | glTF 直接拖入 | ✅（内容明细未逐项核对） |
| P5 | Spike Mine（尖刺雷，Aaron Clifford） | poly.pizza 搜索 "landmine" 第 2 条 | 未核实（poly.pizza 单件多为 CC0/CC-BY，下载前须看许可徽标） | FBX/GLTF | 否 | 低多边形 | — | ⚠️ |

---

## 六、战场特效（枪口火光 / 爆炸 / 烟雾）清单

### 6.1 现成特效资源

| # | 名称 | 平台 / URL | 许可证 | 形态 | Godot 4 兼容 | 适用点 | 可达性 |
|---|---|---|---|---|---|---|---|
| X1 | **Godot-simple-FPS-weapon-system（Jeh3no）** | GitHub · https://github.com/Jeh3no/Godot-simple-FPS-weapon-system | **MIT** | Godot 4 插件（.tscn/.gd） | **4.4–4.7 完全支持**；4.0–4.3 需删 .uid | 枪口火光、弹孔贴花、爆炸特效、5 武器示例、武器管理/HUD 全套 | ✅ |
| X2 | **Kenney Particle Pack**（80 张 512² 粒子贴图） | Kenney · https://kenney.nl/assets/particle-pack | **CC0** | PNG 贴图 | 任意（纹理导入） | GPUParticles3D 广告牌贴图：火花/光点/烟尘 | ✅ |
| X3 | **Kenney Smoke Particles**（70 张贴图，tag: particle smoke explosion vfx） | Kenney · https://kenney.nl/assets/smoke-particles | **CC0** | PNG 贴图 | 任意 | 烟雾/爆炸广告牌粒子贴图 | ✅ |
| X4 | Fireball And VFX（风格化火球+爆炸，含 shader+mesh） | Godot Asset Store · Yogurt | **MIT** | Godot 资源 | Godot 4 | 爆炸特效参考/直接改造 | ⚠️ |
| X5 | GODOT-VFX-LIBRARY（35+ 粒子、17+ shader、管理器） | GitHub · https://github.com/haowg/GODOT-VFX-LIBRARY | **MIT** | Godot 4.5+ .tscn/.gdshader | Godot 4.5+ | 偏 2D（类银河城），可借火花/尘埃及管理器思路 | ✅ |
| X6 | CGHEVEN Asset Library（编辑器内浏览导入 flipbook VFX/模型/HDRI） | Godot Asset Store | **MIT**（插件）；素材按 CGHEVEN 条款 | 插件+序列帧 | Godot 4 | 爆炸序列帧（flipbook）专业素材，需注册账号 | ⚠️ |
| X7 | Godot Retro（合成器效果+shader 包） | Godot Asset Store · Lucas Ângelo | **CC0**（个别 glitch/NTSC shader 例外，用前核对） | Shader | Godot 4 | **夜视仪后期**（绿调/噪点/扫描线）参考 | ⚠️ |
| X8 | Saltmire Spark（单行调用 2D 粒子突发） | Godot Asset Store | **MIT** | 插件 | Godot 4 | 2D 专用，本作 3D 场景不适合——**排除** | ⚠️ |
| X9 | PopcornFX（外部编辑器 VFX 方案） | Godot Asset Store | Community License | 插件（Alpha） | 实验性 | 需外部编辑器、Alpha 状态、许可非标准——**排除** | ⚠️ |

### 6.2 自制（GPUParticles3D）vs 现成特效包：取舍评估

**结论：混合策略 —— 以 GPUParticles3D 自制为主，Kenney CC0 贴图打底，Jeheno（MIT）的特效场景结构直接借用/仿写。**

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| 纯现成特效包 | 省工时 | Godot 4 生态里 **3D 战斗特效成品包很少**（商店搜 "muzzle flash 3d" 0 结果）；2D 包多不适用；风格难统一 | 不可行作主力 |
| 纯自制 GPUParticles3D | 与夜战冷色光照完美统一；枪口火光=1-2 帧高亮突发+PointLight 闪光即可；爆炸=火球突发+烟雾广告牌+碎屑三层叠加；教程成熟（gameidea.org FPS 系列第 8 篇、80.lv Gabriel Aguiar 枪口火光教程） | 需要 1–2 天调参 | **主力方案** |
| 混合（推荐） | Jeheno 的 muzzle flash / bullet hole / explosion 场景可直接拆用（MIT）；Kenney 贴图解决美术素材；爆炸想更华丽再上 CGHEVEN flipbook | 需整合 | **采用** |

> 夜视仪效果同理：**自写全屏 shader**（绿色调映射 + 噪点 + 扫描线 + 暗角 + 高亮增益）即可，无需现成资产；X7 的 CC0 shader 可作参考。

---

## 七、夜视仪 UI 元素清单

| # | 名称 | 平台 / URL | 许可证 | 格式 | 内容 | 可达性 |
|---|---|---|---|---|---|---|
| U1 | **Kenney Crosshair Pack**（200 张 64² 准星） | https://kenney.nl/assets/crosshair-pack | **CC0** | PNG | FPS 准星（夜视模式下换绿色调即可） | ✅ |
| U2 | **Kenney UI Pack Sci-fi**（130 文件：按钮/面板/滑条） | https://kenney.nl/assets/ui-pack-sci-fi | **CC0** | PNG + 主题 | 科幻界面框架，可作夜视仪 HUD 边框/面板 | ✅ |
| U3 | Kenney Game Icons / Input Prompts（通用图标） | https://kenney.nl/assets | **CC0** | PNG | 药包/弹药拾取提示图标 | ✅ |
| U4 | 自制夜视 shader + 遮罩 | 项目内自制 | — | .gdshader | 夜视仪圆形视野遮罩、绿色调、噪点扫描线 | — |

---

## 八、GitHub / Godot 仓库许可证核实记录

| 仓库 / 条目 | 核实结果 | 证据 |
|---|---|---|
| Jeh3no/Godot-simple-FPS-weapon-system | **MIT，核实通过**；Godot 4.4–4.7 支持；100% GDScript；含 5 武器示例（手枪/突击步枪/霰弹/狙击/火箭筒） | README 兼容性章节 + Godot Store 条目 |
| └ 其内置武器模型（amaraha） | **未核实**（itch.io 不可达）→ 建议替换为 Quaternius | README Credits |
| └ 其内置 RPG-7 模型（Sketchfab） | **CC-BY**，需署名 → 建议替换为 Quaternius Rocket Launcher（CC0） | Sketchfab 页面 License: CC Attribution |
| └ 其内置 Ammo Canister（Stephen Yoshimura） | **CC-BY**（poly.pizza）→ 保留则需署名 | README Credits |
| haowg/GODOT-VFX-LIBRARY | **MIT，核实通过**；Godot 4.5+；偏 2D | GitHub README License 章节 |
| PolyPack Planes & Choppers（Alstra Infinite） | **FAL 自定义许可**：可商用+需署名；禁止转售/再分发 | Godot Store 条目描述 |

---

## 九、署名（Attribution）备忘

若按首选组合执行，**CC0 资产无需署名**；仅当启用以下备选时才需要：
- austincford《RPG Launcher》（CC-BY）
- Sketchfab《Low Poly RPG-7》（CC-BY）
- Poly by Google《Helicopter》（CC-BY 3.0）
- Alstra Infinite《PolyPack Planes & Choppers》（FAL，需 credit）
- Jeheno 内置的 Ammo Canister / RPG-7（若不替换）

建议在项目内维护 `ATTRIBUTION.md`，凡 CC-BY/FAL 资产逐条登记名称/作者/URL/许可证。

---

## 十、下一步行动建议

1. 从 quaternius.com 直接下载：Ultimate Guns Pack、Animated Guns Pack、Toon Shooter Game Kit、Survival Pack（全部 CC0，✅可达）。
2. 从 kenney.nl 直接下载：Particle Pack、Smoke Particles、Crosshair Pack、UI Pack Sci-fi、Blaster Kit（全部 CC0，✅可达）。
3. 从 GitHub clone：Jeh3no/Godot-simple-FPS-weapon-system（MIT，✅可达），保留代码与特效，模型替换为 Quaternius。
4. 直升机：优先想办法获取 KumaSousa CC0 直升机（itch.io 镜像/代理）；拿不到则用 kazuma《Helicopter》（poly.pizza 镜像）；再不行实测 Sketchfab/BlendSwap 可达性后选 CC0 直升机；兜底用 Quaternius Spaceships Pack 飞行器改涂装。
5. 特效落地顺序：枪口火光（自制+Jeheno 结构）→ 爆炸（自制三层粒子）→ 烟雾（Kenney 贴图广告牌）→ 夜视 shader。
