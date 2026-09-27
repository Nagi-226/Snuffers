# 10 — Claude-of-Duty 地面街区环境借鉴发掘报告

> **日期**: 2026-09-27 | **作者**: Kimi Work（桌面行动层） | **状态**: 发掘完成，待裁决排期
> **背景**: TheLongSilence 仅有太空船场景，不适用于地面街区，经机主裁决放弃；转向 Claude-of-Duty（`E:\Github Project\Nagi_Games\Claude-of-Duty`，Three.js r180 + WebGL2，约 5.5 万行，**零二进制资产、全程序化生成**，地图为中东集市街区，CoD4 Crash/Backlot 风格）。
> **核心结论**: Claude-of-Duty 没有任何可直接复制的二进制资产，但其**布局范式、模块化建筑套件、程序化材质库、体积雾方案**四块对 Snuffers 地面街区环境有直接移植价值。

---

## 1. 可移植清单（按价值/成本排序）

### P0 — 布局数据驱动范式（`src/world/layout.js`，452 行）

整张地图是一张**声明式数据表**：

- `STREET` 常量：主街半宽 4.5m、建筑线 6.5m、人行道高 0.145m、z 向起止
- `ALLEYS[]`：巷道/空地以矩形 `[x0,z0,x1,z1]` + 地面材质标签声明
- `BUILDINGS[]`：每栋楼 = 占位（w×d）+ 层数 + 各朝向立面程序；**室内用归一化房间坐标（0..1）描述**，改楼体尺寸不改室内设计

**移植方式**: GDScript Dictionary/自定义 Resource 数组 + 一个 builder 解释器脚本。这与本项目「契约三件套数据驱动」的设计约束天然吻合。成本最低、收益最高，建议最先做。

### P1 — 程序化材质库 + 调色板纪律（`src/materials/` + `src/world/palette.js`）

- **19 种程序化表面 GLSL**（`materials/glsl/surfaces-{arch,ground,metal,organic}.js`）：混凝土、砖、灰泥、瓷砖、沥青、沙、土、砾石、锈蚀/喷漆/拉丝金属、波纹板、木、织物、麻布、植被、橡胶、玻璃。纯 GLSL，与 Godot ShaderLanguage 语法高度相似，可逐函数移植（fbm/value noise 部分几乎直接搬）。
- **PALETTE 调色板纪律**（palette.js 头部注释即设计哲学）：
  - 限定命名调色板 → 地图读起来像「同一个地方」；同 key 网格合并 draw call
  - `tint` 线性乘算控制在 0.02–0.9 反射率物理区间
  - **尺度分档**：建筑用混凝土（2.5m 平铺）与道具用混凝土（`concrete_prop`，更密平铺）是两条目——「2.5m 贴图贴在 0.5m 块上会糊成塑料感」
- **顶点遮罩惯例**: `r=边缘磨损 / g=污渍 / b=附加 AO`，× instanceColor 使同类道具个体差异化

**移植方式**: 先搬 3 种（混凝土/沥青/锈蚀金属）验证 shader 移植链路，再批量。Palette 表直接进 `game_config.gd` 或独立 Resource。

### P1 — 模块化立面套件（`src/world/kit.js` 1113 行 + `buildings.js` 776 行）

- **panel space 矩阵约定**: 每个立面元素的局部坐标系 = x 沿墙（居中）、y 从地板线向上、z 从外墙面向内进深；调用方只给一个 `pm` 矩阵，窗户自己知道窗台/窗框/百叶/格栅该放多深——**调用方不用算三角**
- **立面程序生成**: 每侧墙按 ~3m 开间步进，每开间每层从套件挑元素（店面/门/窗/拱窗/阳台门/留白）
- 套件元素：facadeWall、windowUnit、doorUnit、shopfront、balcony、parapet、stairRun、awning、drainpipe、spallPatch（墙面剥落）、rubbleMound（瓦砾堆）
- 底层件（`util.js`）：chamferBox、wallPanel、solidSlabs、clothGeometry、catenaryTube（悬链线管缆）、rockGeometry、polyPrism

**移植方式**: 两条路线——(a) GDScript 运行时拼装（ArrayMesh/MeshLibrary）；(b) **用我们已打通的 Blender headless 管线**离线烘焙套件件为 GLB 再进 Godot 拼装。建议 (b) 先行：白模教训表明运行时程序化拼装质量不可控，离线烘焙可预览迭代。

### P2 — 体积雾与大气透视（`src/sky/volumetrics.js`）

三分法管线：半分辨率步进（24–56 指数分布采样 + 交织梯度抖动）→ 时间累积重投影（把 32 个抖动样本变成干净光柱）→ 全分辨率解析合成（闭合式指数高度积分，远景雾霾无噪声）。

**关键设计哲学（直接适用于浓雾部队氛围）**:
- **散射与消光分离**，不用单一散射反照率绑定；**消光由目标能见度反推**——先定「浓雾里 30m 看不见人」，再算参数
- 低配降级路径：跳过步进，保留解析大气透视，远景衰减观感不变

**移植方式**: Godot 4.6 内置 VolumetricFog + FogVolume，主要借鉴参数分离哲学与能见度定标法，不需要移植 raymarching 代码。

### P2 — 道具库与布景层（`src/world/props.js` 994 行 + `dressing.js` 2269 行）

- 道具 = 倒角盒 + 管 + 布网格 + 噪声变形岩石的小装配体，**合并为单几何体注册为 InstancedMesh 原型**；本文件只管「长什么样」，摆放（旋转/缩放/tint 变化）在 dressing.js
- 布景哲学：「Geometry makes a level; dressing makes it a *place*」——悬链线电线、布篷、瓦砾、沙袋、烧毁汽车（burntCar）
- 特殊件：`burntCar`（烧毁汽车残骸）对废墟街区直接对口

### P3 — 已记录待排期（08 路线图已有）

- 武器手感：后座双层模型、视模型叠加层 lag 弹簧
- UI：命中标记时序参数
- fx：曳光/枪口火光/受击方向弧（A 方案三件套，G4 前施工）——`src/fx/tracers.js`/`muzzle.js` 有现成参数参照

---

## 2. 不可移植/无需移植

| 项 | 原因 |
|---|---|
| render/ HDR 管线（GTAO/TAA/bloom/AgX） | Godot 4.6 内置 SSAO/SSIL/TAA/bloom/ACES，只需参数调校 |
| physics/ 自研物理 | Godot 物理引擎完备 |
| 具体 GLSL 后处理 pass | 与 Godot RenderingServer 管线架构不同，重写比移植快 |

## 3. 建议行动序列

1. **街区布局数据表 + builder**（P0）：先在灰盒竞技场旁建一条试验街，验证范式
2. **3 种材质 shader 移植**（P1）：混凝土/沥青/锈蚀金属，验证 GLSL→Godot 链路
3. **立面套件 Blender 烘焙**（P1）：用已验证的 headless 管线产出墙/窗/门/阳台 GLB 件
4. **浓雾能见度定标**（P2）：定浓雾部队场景的能见度目标值，反推 FogVolume 参数
5. 道具库（P2）与三件套参数参照（P3）随后

> 每项动工前按 AGENTS.md #9 输出完成标准与验收用例。
