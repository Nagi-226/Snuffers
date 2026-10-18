# EM-68A 武器 GLB 后处理报告

> W9「深度蜂」首张派单 · 2026-10-18 · 输入 `em-weapons/em68a.glb`（AI 图生 3D 产物，机主已验收为完美成品）
> 对应派单：`desktop-port/godot-spike/14-dispatch-dsh-weapon-postprocess.md`
> 机器产物：`weapon_postprocess_report.json`（脚本自报）、`verify_glb_identity.json`（独立校验器）

## 0. 结论

**VERDICT = PASS**（脚本内判定）。输出 `em-weapons/em68a_viewmodel.glb`（53,476,320 B）已生成，
由 1 个对象拆成 **4 个独立子对象**（机体 / 弹匣 / 瞄具 / 下挂榴弹模块），
顶点数与三角面数与输入**精确相等**，顶点位置 / UV / 贴图字节与输入**逐位一致**，
未做任何减面、重拓扑、UV 改动、贴图重压缩或材质改名。

唯一与输入不再逐位一致的是**顶点法线方向**（最大 0.2125°，肉眼不可见），成因与处置见 §6-1。

## 1. 运行环境与命令

| 项 | 值 |
|---|---|
| Blender | 5.2.2 LTS（hash `d13f752e3b9c`，2026-09-15 构建）|
| glTF 导入/导出 | Khronos glTF Blender I/O v5.2.40（Blender 内置）|
| 运行方式 | `blender.exe -b --factory-startup --python-exit-code 1 --python weapon_postprocess.py -- <输入 glb>` |
| 单次总耗时 | 32.85 s（导入 3.05 s / 连通分量 10.36 s / 拆分 8.68 s / 导出 2.06 s / 其余为结构解析与比对）|
| 外部依赖 | 无（只用 Blender 自带 bpy + Python 标准库 `struct/json/hashlib/os/sys/time`）|

Draco 与 MeshOptimizer 库在 Blender 中可用但**全程未启用**（派单禁止压缩），导出参数显式 `export_draco_mesh_compression_enable=False`。

## 2. 输入实测清单（`em68a.glb`）

| 项 | 值 |
|---|---|
| 文件 | 54,695,528 B（52.2 MiB） |
| generator / version | `3d_generator` / glTF 2.0 |
| 节点 / 网格 / 图元 | 1 / 1 / 1（node `node_35a79196-e9c3-40fb-ba8f-3be1fcc4aebc`，mesh `mesh_35a79196-…`，mode 4 = TRIANGLES）|
| 顶点数 | **757,380** |
| 三角面数 | **1,464,017** |
| 顶点属性 | `POSITION` / `NORMAL` / `TEXCOORD_0`，全 float32、非 normalized |
| 材质数 | 1（`material_35a79196-e9c3-40fb-ba8f-3be1fcc4aebc`）|
| 材质参数 | alphaMode `OPAQUE`、doubleSided `false`、baseColorFactor `[1,1,1,1]`、metallic 1.0、roughness 1.0 |
| 贴图 | 3 张，均 **4096×4096**：`Color_…` JPEG 3,623,490 B（sha256 `6351eae8…`）、`ORM_…` JPEG 1,859,061 B（`677c97ee…`）、`NormalGL_…` PNG 7,406,595 B（`b458a4d7…`）|
| 动画 / skin / 相机 / 扩展 | 0 / 0 / 0 / 无 |
| 对象变换 | location (0,0,0)、rotation (0,0,0)、scale (1,1,1) — **已是 identity** |
| UV 层 | 1 层 `UVMap`；无顶点色 |
| 着色 | 1,464,017 面全部 shade smooth |
| 连通分量 | **203** 个 |
| 包围盒 | X [-0.049, 0.049]、Y [-0.5, 0.5]、Z [-0.22376, 0.22376]（米）|

**朝向（实测，供 Godot 侧参考）**：枪口 **+Y**、枪托 **-Y**、上方 **+Z**。
导出用 `export_yup=True`，故 glTF/Godot 中枪口指向 **Godot 本地 -Z**，即与 Godot 相机/角色的 forward 方向一致，导入后**不需要再转 90°**。

## 3. 输出实测清单与拆分结果

`em68a_viewmodel.glb`：53,476,320 B（51.0 MiB），generator `Khronos glTF Blender I/O v5.2.40`，
**4 节点 / 4 网格 / 4 图元 / 材质 1 / 贴图 3 / 动画 0 / skin 0**，4 个节点全为 scene root 且**无 TRS 字段（identity 变换）**。

| 子对象（节点名）| 连通分量 | 顶点数 | 三角面 | 包围盒 X / Y / Z（米）|
|---|---|---|---|---|
| `em68a_body`（机体，含机匣/枪管/护木/枪托/握把/扳机护圈/机瞄等）| 169 | 577,448 | 1,112,992 | [-0.049, 0.049] / [-0.5, 0.5] / [-0.16333, 0.17279] |
| `em68a_magazine`（弹匣）| 5 | 54,952 | 107,453 | [-0.03056, 0.03119] / [-0.04097, 0.09522] / [-0.22376, -0.05314] |
| `em68a_optic`（红点瞄具）| 9 | 49,203 | 96,144 | [-0.04232, 0.04415] / [-0.04284, 0.08364] / [0.1334, 0.22376] |
| `em68a_gl_module`（下挂榴弹模块）| 20 | 75,777 | 147,428 | [-0.04646, 0.04613] / [0.10658, 0.42608] / [-0.0443, 0.03457] |
| **合计** | **203** | **757,380** | **1,464,017** | — |

四个部件顶点数与三角面数之和**与输入总数完全相等**，且每个部件的实测值与拆分前的预期值逐项相等。

### 3.1 拆分方式（未增删改任何几何）

单材质模型无法靠材质区分部件，因此拆分为两步：
1. **识别**：按顶点连通性把 1,464,017 面切成 203 个连通分量，再按包围盒空间规则归属到 4 个部件（规则常量集中在脚本第 29–43 行）：
   - 瞄具 `lo.z > 0.125`（顶部导轨顶面实测 0.1328）且中心 `-0.05 < y < 0.10`；
   - 弹匣 `hi.z < -0.05` 且中心 `-0.10 < y < 0.13`；
   - 下挂榴弹 中心 `y > 0.10` 且 `hi.z < 0.04`（护木下方整套组件）；
   - 其余归机体。
2. **分离**：用顶点组承载分量归属标签，再 `bpy.ops.mesh.separate(type='SELECTED')` 级联分离 3 次，得到 4 个对象。
   全程只做"分组 + 分离已有几何"，没有任何顶点/UV 的增、删、改，也没有 recalc normals 或 merge by distance。

规则不是我凭形状猜的，而是"规则 → 高亮渲染 → 隔离渲染"三轮实证收敛的结果（证据见 §4.3）。

### 3.2 两个需要蜂后知晓的判断

- **机瞄（前后照门）留在 `em68a_body`**，没有并入 `em68a_optic`。理由：前后照门是机体的固定折叠件，且其包围盒与红点镜（y∈[-0.0428, 0.0836], z∈[0.1334, 0.2238]）重叠，按连通分量无法与导轨干净切分；`em68a_optic` 只含可拆装的红点镜本体。
- **`em68a_gl_module` 取"护木下方整套组件"**（侧板/底部肋条/弹膛前端帽与其安装框），不是只取一根管子。理由：该模块侧板与弹膛为一个整体结构，只取管子会把它拆成碎件；隔离渲染确认这 20 个分量构成一个功能完整的下挂模块。

## 4. 零改动证据（三层）

### 4.1 官方计数（`weapon_postprocess_report.json` → `comparison`）

| 指标 | 输入 | 输出 | 结果 |
|---|---|---|---|
| GLB 三角面 | 1,464,017 | 1,464,017 | 相等 |
| GLB 顶点 | 757,380 | 757,380 | 相等 |
| Blender 内三角面 | 1,464,017 | 拆分后合计 1,464,017 | 相等 |
| Blender 内顶点 | 757,380 | 拆分后合计 757,380 | 相等 |
| 顶点属性集合 | NORMAL/POSITION/TEXCOORD_0 | 同 | 相等 |
| 贴图字节 | 3 张 sha256 集合 | 同 3 张 | 集合完全一致（未重编码）|
| 节点 / 网格 | 1 / 1 | 4 / 4 | 仅层级变化（派单允许）|

### 4.2 独立校验（`verify_glb_identity.py` / `verify_glb_identity.json`）

这个校验器**不经过 Blender**，直接用 `struct` 解 GLB 的 JSON/BIN chunk、用 numpy 重算哈希，
用来防止"导出器自报自夸"。15 条断言：**12 PASS / 3 FAIL**。

| # | 断言 | 结果 |
|---|---|---|
| 1 | 顶点数一致（757,380）| PASS |
| 2 | 三角面数一致（1,464,017）| PASS |
| 3 | 属性布局一致（全 float32 / 非 normalized）| PASS |
| 4 | 各属性顶点数守恒 | PASS |
| 5 | 三角面集合一致（按位置组、忽略绕序，731,981 组）| PASS `513da060…` |
| 6 | 三角面绕序保留 | PASS `3087bbdb…` |
| 7 | 每位置 POSITION 一致 | PASS `7e7d3768…` |
| 8 | 每位置 NORMAL 一致 | **FAIL** → 见 §6-1 |
| 9 | 每位置 TEXCOORD_0 一致 | PASS `0703646d…` |
| 10 | 法线偏差 ≤ 1e-5 度 | **FAIL** → 见 §6-1 |
| 11 | UV 偏差 = 0 | PASS（`uv_max_abs_delta = 0.0`）|
| 12 | 贴图字节集合一致（未重压缩/未重采样）| PASS（3 张大小+mime+sha256 全同）|
| 13 | 材质语义一致（按贴图内容解析）| **FAIL（伪阳性）** → 见 §6-2 |
| 14 | 对象数 1 → 4，名称正确 | PASS |
| 15 | 无动画 / skin / 相机 | PASS |

另一项独立事实：输出 4 个 node **均不含 matrix/translation/rotation/scale 字段**，即全部 identity 变换；
输入 node 同样 identity。因此派单要求的"应用全部变换"在效果上已满足（本来就没有待应用的变换），
每个部件不需要额外烘焙即可被 Godot 当独立节点重新挂接。

### 4.3 视觉证据（`em-weapons/renders/`，未入库的工作树产物）

| 用途 | 文件 |
|---|---|
| 原样六视角（确认外形与朝向）| `view_pos_x/neg_x/pos_y/neg_y/pos_z/three_quarter.png` |
| 26 个最大连通分量上色 + 图例 | `colors_side_pos_x.png`、`colors_side_neg_x.png`、`colors_three_quarter.png`、`legend.json` |
| 规则高亮（红=弹匣 / 绿=瞄具 / 蓝=下挂榴弹 / 灰=机体）| `hl_side_pos_x.png`、`hl_side_neg_x.png`、`hl_bottom.png`、`hl_three_quarter.png` |
| 部件隔离渲染（证明每个部件自身完整、无被切碎）| `iso_body_side.png`、`iso_body_under_front.png`、`iso_magazine_side.png`、`iso_magazine_under_front.png`、`iso_optic_side.png`、`iso_optic_under_front.png`、`iso_gl_module_side.png`、`iso_gl_module_under_front.png` |
| 下挂模块特写（确认大口径圆膛与步枪枪口制退器并存）| `detail_underbarrel_34.png`、`detail_underbarrel_front.png`、`detail_underbarrel_bottom.png` |
| 瞄具特写 | `detail_top_optic_34.png`、`detail_top_optic_side.png` |

## 5. 逐条对照派单验收标准

| 派单条目 | 结果 |
|---|---|
| L35 `blender -b --python weapon_postprocess.py -- em68a.glb` 一次跑通、输出 GLB 存在 | ✅ 可重复跑通；输出 53,476,320 B 存在。（诚实记录：**首次**运行因脚本自身一个 KeyError 崩溃，修正后跑通，非几何问题）|
| L36 导出与输入逐顶点一致，报告含两组实测值 | ✅ 顶点/三角面/位置/UV/贴图逐位一致（§4.1、§4.2）；法线一项见表述偏差 |
| L36 仅对象层级允许变化 | ✅ 1→4 节点，几何无增删 |
| L37 体积不作限制 | ✅ 未压缩（51.0 MiB）|
| L38 Godot 侧验证归蜂后 | ✅ 未触碰 `godot/` |
| L29 禁减面/重拓扑/顶点合并/法线重算 | ⚠️ 前三项 0 发生；**法线被 Blender 重算**（§6-1）|
| L29 禁重压缩/重采样贴图 | ✅ 3 张贴图 sha256 逐字节一致 |
| L29 禁改材质命名 | ✅ 材质名 `material_35a79196-…` 保持不变 |
| L30c 拆弹匣/瞄具/下挂榴弹、拆不出要明示、不许硬凑 | ✅ 三件全部拆出；两处判断依据见 §3.2 |
| L31d Y-up 保持 / 应用全部变换 / 贴图内嵌不压缩 | ✅ identity 变换 + Y-up + 内嵌未压缩（§3、§4.2）|
| L32 交付报告 `.md` | ✅ 本文件 |

## 6. 未解决问题清单

### 6-1 【P2，机主已裁决：只报告不修】导出后顶点法线被 Blender 重算

- 现象：glTF 导入（写入 Blender 自定义法线）→ 导出的往返中，法线被重新归一化，
  707,045 个可配对顶点里 **全部** 有微小角度差；另有 50,335 个顶点因位置组重排无法按组配对（不影响几何）。
- 量化：平均 **0.007272°**、p99.9 **0.060315°**、最大 **0.212453°**（即最坏情况偏离不到 0.22 度）。
- 判定：这是 glTF↔Blender 法线往返的固有行为，**不是**主动"优化"，视觉上不可见（0.21° 远低于 8-bit 法线贴图量化误差）。
- 处置：按机主 2026-10-18 裁决**只在报告明示**，不追加回写 custom normals 的尝试。
- 若蜂后坚持位级一致：唯一可行路径是在导出前 `mesh.normals_split_custom_set(输入法线)` 回写原法线，
  但需重跑并重新验证，且不保证导出器完全不再归一化。

### 6-2 【P3，伪阳性】校验器第 13 条"材质语义一致"失败

输入材质带 `normalTexture.scale: 1`（显式字段），输出省略该字段（glTF 默认值即 1.0），
我的严格 dict 比较把"字段缺失"判成不一致。**语义完全等价**，无实际差异。属校验器断言过严，非模型问题。

### 6-3 【P3】GLB 内 images 数组顺序变化

输入顺序 Color / ORM / NormalGL，输出顺序 NormalGL / Color / ORM。三张图字节完全相同、引用关系不变。
（注：脚本首版按数组下标比较贴图 sha256，因此一度在 JSON 里误报 `images_byte_identical=False`
和"发生重编码"备注；**该伪阴性已修正**为按 sha256 集合比较，现为 `True` 并附"仅数组顺序变化"说明。）

### 6-4 【P3】四个部件共享同一原点（模型几何中心）

因应用户"保持 identity 变换"的要求，`em68a_magazine` 等子对象的局部原点都在模型中心，而不是弹匣口/导轨面。
换弹动画若需要以弹匣口为枢轴，需再加一步"按部件包围盒设 object origin 并烘焙"——这会让 node TRS 不再 identity。
**本次未做**（派单未要求），如需要请下一单明确。

### 6-5 【流程】Godot 侧导入验证未做

按派单 L38 属蜂后职责。给蜂后的自检建议见 §8。

## 7. 申请事项（按派单 L45，请蜂后裁决，我未自行处置）

1. **大资产是否入库**：`em-weapons/em68a.glb`（52.2 MiB，机主原件）与 `em68a_viewmodel.glb`（51.0 MiB，本次产物）
   目前都是**未跟踪**文件。按机主 2026-10-18 裁决，本次提交只含脚本 / 报告 / 校验 JSON，两个 GLB 与 `renders/` 留在工作树。
   若项目需要资产随仓，建议由 W8 在 `.gitignore` 中明确规则（`.gitignore` 属其域，我未改）。
2. **handoff 越界写**：派单 L46 要求写 `desktop-port/godot-spike/03-handoff-2026-10-18.md`，
   该路径在派单 L10 的可写域（仅 `modeling/`）之外。按机主 2026-10-18 裁决"视为已授权"已写入，
   请蜂后确认后续 W9 派单是否把 handoff 路径正式纳入可写域。
3. **工作树入场时已有他人未提交改动**：51 个 `M godot/assets/**/*.import`（mtime 均为 10-07 18:08:27~30）
   以及未跟踪的 `concept-art/_backup_v4~v6`、`modeling/audit-0927|0930|1007-daynight`、`tmp_shots/`、
   `2026-09-11-a5184548/`、`godot/tools/flyview_debug.log` 等。我**未 stash、未提交、未删除**任何他人改动，
   本次提交只 `git add` 自己域内的新增文件。请蜂后或对应 Agent 处置。

## 8. 给蜂后的 Godot 侧自检建议

1. 导入 `em68a_viewmodel.glb`，确认生成 **4 个 MeshInstance3D**（`em68a_body` / `em68a_magazine` / `em68a_optic` / `em68a_gl_module`），无报错。
2. 确认枪口朝 **-Z**（Godot forward），若在 FPS 视图模型里方向不对，只需整体绕 Y 转 180°，不要改模型。
3. 确认材质为 1 个 `StandardMaterial3D`（或导入生成的 material），3 张贴图正确挂接（albedo / ORM→metallic-roughness / normal）。
4. 换弹动画可只操作 `em68a_magazine` 节点；瞄具与下挂模块可独立隐藏/替换（`em68a_optic`、`em68a_gl_module`）。
5. 首帧若发现法线细看有极轻微差异，属 §6-1 已知项，不影响验收。

## 9. 复跑与 em57p 适配

- 复跑（一条命令即可，幂等覆盖输出）：
  `blender.exe -b --factory-startup --python-exit-code 1 --python modeling/scripts/weapon_postprocess.py -- <绝对路径>/em68a.glb`
- `em57p.glb`（手枪）**不可直接套用**本脚本的部件阈值：`MAG_MIN_Z` / `OPTIC_MIN_Z` / `GL_MAX_Z` 等常量是针对 EM-68A 实测标定的，
  换模型必须按 §4.3 的高亮渲染重新标定后再用。脚本已把阈值集中在文件头常量区，改完重跑即可。
- 本脚本不做任何"优化"，只做"统计 + 归属 + 分离 + 原样导出"，因此对同管线的新模型安全。
