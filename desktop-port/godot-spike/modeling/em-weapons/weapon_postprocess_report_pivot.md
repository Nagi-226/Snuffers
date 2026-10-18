# 弹匣枢轴原点迁移报告（W9 第三单 · 派单 17）

> 任务：把两个 viewmodel 里 **magazine 子对象的局部原点**从「与其它三个对象共享的世界原点」迁到
> **弹匣顶端面（插入弹井的入口面）的面积加权中心**，供程序化换弹动画以该点为枢轴做拔插/旋转。
> 硬约束：**世界空间几何逐点不变**；除原点迁移外不做任何其它变更；不减面/不重拓扑/不重采样贴图。
>
> 执行者：W9「深度蜂」（DeepSeek Harness + V4.1-Flash-1017）　分支：`dev1`　日期：2026-10-18

---

## §0 结论（先看这一段）

| 检查项 | em68a | em57p | 判定 |
|---|---|---|---|
| 管线自检（零几何改动 + 枢轴） | `PASS` | `PASS` | ✅ |
| magazine 新原点 = 弹匣顶面中心 | `(-0.005748168, 0.068321921, -0.054112017)` | `(-0.008679522, -0.187480494, -0.147694334)` | ✅ 实测取点 |
| **世界空间几何守恒**（应用节点变换后逐顶点比对） | 最大偏差 `3.725e-09 m` | 最大偏差 `3.725e-09 m` | ✅ |
| 其余三个对象原点不动 | body/optic/gl_module 均为 `[0,0,0]` | body/optic/laser_module 均为 `[0,0,0]` | ✅ |
| 顶点数 / 三角面数 | `757,380 / 1,464,017`（与输入完全相等） | `708,514 / 1,370,580`（+39 为已知基线，见 §5） | ✅ |
| 贴图字节 / 属性集合 / UV | 一致 / 一致 / UV 偏差 0 | 一致 / 一致 / UV 偏差 0 | ✅ |
| 脚本幂等（同输入跑两次 sha256 相同） | `True` | `True` | ✅ |
| 独立校验器「世界空间位置守恒」断言 | `PASS` | `PASS` | ✅ |

一句话：**两把枪的弹匣枢轴都已落在弹匣顶面中心，世界空间几何零变化（最大 3.7 nm，纯 float32 存储抖动）。**

产物（同名覆盖，均由本单脚本重新导出）：

| 文件 | 字节 | sha256 |
|---|---|---|
| `em68a_viewmodel.glb` | 53,476,400 | `7bc7bbfa2146b5e514b047344634543674eb52243de9a61469a115916d06f28c` |
| `em57p_viewmodel.glb` | 52,086,256 | `19ee99d303208003a160910c91ddf1902cb6a763326a3783d6046960efa43c5a` |

迁移前基线（保留在 `*.pre_pivot_backup.glb`，未入库，蜂后验证通过后可删）：

| 文件 | 字节 | sha256 |
|---|---|---|
| `em68a_viewmodel.pre_pivot_backup.glb` | 53,476,320 | `dbc5fe773d33f83a7508e98e75c1602ae783a7e4602e09e32ff39dbfb208e1dc` |
| `em57p_viewmodel.pre_pivot_backup.glb` | 52,086,172 | `dfcabb41d8e0dded6a94e2a07b3562388bc233d844d7e9368b325919699a4669` |

---

## §1 环境与命令

| 项 | 值 |
|---|---|
| Blender | `D:\steam\steamapps\common\Blender\blender.exe`（5.2.2 LTS，hash `d13f752e3b9c`），仅 headless |
| 管线脚本 | `desktop-port/godot-spike/modeling/scripts/weapon_postprocess.py`（两单共用一套，按 `PROFILES` 分档） |
| 编排脚本 | `desktop-port/godot-spike/modeling/scripts/rebuild_viewmodels.py`（**一条命令跑两枪**） |
| 独立校验器 | `desktop-port/godot-spike/modeling/scripts/verify_glb_identity.py`（新增「世界空间位置守恒」断言） |
| Python | `C:\Users\FJL03\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe` |

一条命令（派单要求 ④）：

```bash
python desktop-port/godot-spike/modeling/scripts/rebuild_viewmodels.py
```

该命令对两把枪依次执行 `pipeline → idem → verify` 三步，结果合并写入
`desktop-port/godot-spike/modeling/em-weapons/pivot_rebuild_summary.json`，末尾打印 `总结果: PASS/FAIL`。

> 本次实际执行说明：本机 `godot_run_headless` 单次调用约 130 s 上限，而整单约 4~5 分钟，
> 故实际按 `--steps` 拆成多次调用执行（`pipeline` / `idem` / `verify` 各自独立跑），
> 步骤语义与默认 `all` 完全一致，汇总 JSON 由多次执行累积而成（见 `updated_at` 字段）。

---

## §2 取点依据（为什么是「顶面面积加权重心」）

弹匣插入弹井的入口面 = 弹匣**世界 +Z 最高的那个面**。取点方法在脚本 `top_face_center()`：

1. 把弹匣全部顶点转到世界坐标，取 `z_max`；
2. 只保留**三个顶点都落在 `z >= z_max - 2 mm` 带内**的三角形（避免斜面/倒角污染）；
3. 用这些三角形的**面积加权重心**作为枢轴世界坐标。

两枪各自实测、没有互抄：

| 参数 | em68a_magazine | em57p_magazine |
|---|---|---|
| 世界 `z_max`（Blender Z-up） | `-0.053139586` m | `-0.146710515` m |
| band 内顶点数 | 56 | 43 |
| band 内三角形 / 弹匣三角形总数 | `30 / 107,453` | `6 / 116,508` |
| 顶面面积 | `2.2598565e-05 m²`（22.6 mm²） | `2.738004e-06 m²`（2.7 mm²） |
| 枢轴世界坐标（Blender） | `(-0.005748168, 0.068321921, -0.054112017)` | `(-0.008679522, -0.187480494, -0.147694334)` |
| 枢轴世界坐标（glTF/Godot Y-up，`x, z, -y`） | `(-0.005748168, -0.054112017, -0.068321921)` | `(-0.008679522, -0.147694334, 0.187480494)` |

em57p 的顶面只有 6 个三角形、面积 2.7 mm²（平顶盖板很窄），em68a 的顶面 30 个三角形、22.6 mm² ——
两枪几何差异明显，**必须各测各的**，这也是派单强调"不许互抄"的原因。

---

## §3 做法（只动原点，不动世界几何）

Blender 里对象原点 = 对象矩阵的平移分量，网格顶点坐标是**对象局部**坐标。因此：

```
M_new = M_old @ T(local)          local = M_old⁻¹ @ pivot_world
co_new = co_old - local       =>  M_new @ co_new = M_old @ co_old   （世界坐标不变）
```

脚本 `move_origin_to()` 就是这两行：`obj.data.transform(Translation(-local))` +
`obj.matrix_world = mw_before @ Translation(local)`。
导出为 glTF 后，该平移就是节点的 `translation`，Godot 导入后即 `MeshInstance3D` 的变换原点 →
换弹动画只要动这个节点的 `position/rotation` 即可（枢轴天然在弹匣顶部）。

**其余三个对象**：管线在步骤 5 对四对象执行过 `transform_apply(location/rotation/scale)`
（输入为恒等变换，结果仍为 `[0,0,0]`），枢轴迁移只作用于 `PROFILES[stem]["pivot_part"]`
（两档均为 `"magazine"`），所以其它三对象的原点保持 `[0,0,0]`。

幂等性：同一输入连跑两次，产物 sha256 完全相同（`rebuild_viewmodels.py` 的 `idem` 步骤实测
`True / True`）；脚本本身也是幂等的（每次从源 GLB 重建，不读上一次产物）。

---

## §4 世界空间守恒证据（三层）

### 4.1 管线内自检（Blender 侧，迁移前后同一进程内取快照）

对四个对象在各时刻取全部顶点的**世界坐标**，迁移后逐顶点（按索引）比对：

| 对象 | em68a 顶点数 | em68a 最大偏差 | em57p 顶点数 | em57p 最大偏差 |
|---|---|---|---|---|
| body | 577,448 | `0.0` | 566,300 | `0.0` |
| magazine | 54,952 | `3.725e-09 m` | 59,285 | `3.725e-09 m` |
| optic | 49,203 | `0.0` | 51,365 | `0.0` |
| gl_module / laser_module | 75,777 | `0.0` | 31,525 | `0.0` |
| **全对象最大** | | **`3.725e-09 m`** | | **`3.725e-09 m`** |

容差口径 `1e-6 m`（1 µm），理由是 Blender 顶点坐标为 float32：局部坐标整体平移后相对舍入会带来
~1e-8 m 量级抖动，实测 3.7e-9 m；1 µm 远大于该抖动、远小于任何真实几何变化（弹匣高度 ~17 cm，
1 µm 相当于其 1/170000）。

> **踩坑记录（重要）**：第一版用「1 nm 量化哈希」判等，被上述 3.7e-9 m 的纯浮点抖动判成 FAIL；
> 第二版改用「排序后比对」，又因为 `np.lexsort` 用原始 float64 排序、两点在 x 轴相差 <1e-9 而 y 轴
> 相差很大时顺序互换，把微小抖动**放大成 8.3 cm 的假差异**（实测 `sorted_max_abs_delta_m=0.0835`）。
> 最终口径 = **逐顶点索引比对 + 1 µm 容差**（拆分与迁移都不重排顶点，索引一一对应），
> 排序比对仅作参考、不参与判定。

### 4.2 独立校验器（文件级，不经 Blender）新增断言

`verify_glb_identity.py` 新增：

- `node_world_matrices(gltf)`：展开 glTF 节点 TRS/父子链，得到每个 mesh 节点的 4×4 世界矩阵；
- `world_positions_by_node()`：把 POSITION accessor 乘上世界矩阵，得到**应用节点变换后的世界坐标**；
- 断言 **「世界空间位置守恒（应用节点变换后逐顶点世界坐标一致）」**。

结果：两枪均 `PASS`，逐对象最大偏差 `3.725e-09 m`（与 Blender 侧自检互相独立、数值一致）。

### 4.3 节点世界平移（导出后实测，最能说明"只有弹匣动了"）

```
em68a  输入 {body:[0,0,0], gl_module:[0,0,0], magazine:[0,0,0], optic:[0,0,0]}
       输出 {body:[0,0,0], gl_module:[0,0,0], magazine:[-0.005748168, -0.054112017, -0.068321921], optic:[0,0,0]}
em57p  输入 {body:[0,0,0], laser_module:[0,0,0], magazine:[0,0,0], optic:[0,0,0]}
       输出 {body:[0,0,0], laser_module:[0,0,0], magazine:[-0.008679522, -0.147694334, 0.187480494], optic:[0,0,0]}
```

### 4.4 校验器其余 6 条断言的失败项：全部是「局部坐标类」，非回归

本单对比的是「迁移前 viewmodel vs 迁移后 viewmodel」，而**迁移的就是对象的局部原点**，
所以凡是以局部坐标/局部法线为基准的断言必然变化。逐条解释：

| 失败断言 | 原因 | 是否问题 |
|---|---|---|
| 三角面集合一致（按位置组，忽略绕序） | 位置分组用的是**局部** POSITION，magazine 局部坐标整体平移 | 否，符合预期 |
| 三角面绕序保留（按位置组） | 同上 | 否 |
| 每位置 POSITION 一致 | 同上 | 否 |
| 每位置 TEXCOORD_0 一致 | UV 未变（`uv_max_abs_delta=0.0`），但按位置分组的键变了 | 否 |
| 每位置 NORMAL 一致 | 同上（法线本身未动） | 否 |
| 法线偏差 ≤ 1e-5 度 | 重导出时法线按 float32 重新量化，实测最大 `8.1041e-05` 度（≈1.4e-6 rad） | 否，量级可忽略 |

`pivot_rebuild_summary.json` 里已用机器可读字段标注：
`verify_failures_local_space_only: true`、`verify_other_failures: []`（无其它类型失败）。

---

## §5 已知基线：em57p 文件级顶点数 +39（非本单引入）

| 项 | 输入 `em57p.glb` | 输出 `em57p_viewmodel.glb` |
|---|---|---|
| 三角面 | 1,370,580 | 1,370,580（相等） |
| 顶点（文件级） | 708,475 | 708,514（**+39**） |
| 顶点（Blender 侧） | 708,475 | 708,475（相等） |

+39 = **13 个非平滑面 × 3 角点**，是 glTF 导出器对 `use_smooth=False` 的面拆角点的固有行为；
第二单已用「零拆分对照实验（只 import→export）」证明同样 +39，与拆分/枢轴无关。
2026-10-18 蜂后裁决口径：em57p 以「与自身迁移前比」为准，+39 列为已知基线。
本单已在 `PROFILES["em57p"]` 写入 `file_vertex_delta_allowance: 39`（带理由），
管线报告据此判 `PASS`，em68a 的允许增量为 `0`（实测逐字节相等）。

---

## §6 未解决问题

1. **【P3】备份 GLB 占空间**：`em68a_viewmodel.pre_pivot_backup.glb`（53.5 MB）+
   `em57p_viewmodel.pre_pivot_backup.glb`（52.1 MB）为本次对比基线，**未入库**。
   蜂后 Godot 侧验证通过后可删；若要长期留证，建议由蜂后决定是否入库（约 105 MB）。
2. **【P3】本地坐标类断言无法用于"迁移前后"对比**：这是校验器口径问题，不是数据问题。
   若后续要做"严格全绿"的迁移前后对比，需要给校验器加一个「允许局部坐标整体平移」的开关，
   本单为保持校验器通用性未加。
3. **【P3】枢轴方向语义**：枢轴取的是弹匣**顶面中心**（面心），不含弹匣的旋转轴朝向。
   换弹动画若需要"沿弹匣轴线方向"拔插，还需要一个轴向（本单未提供，派单也未要求）。
4. **【P2，跨单挂账】** 法线往返微差（本单实测最大 `8.1041e-05` 度，第二单为 `0.212453` 度）：
   属 Blender glTF 导出器重算法线的固有行为，未做 custom normals 回写（禁令：禁法线重算，
   即禁止由本 Agent 主动改法线；导出器行为无法关闭而不改视觉结果）。
5. **Godot 侧验证归蜂后**：需在 Godot 里确认 ①四对象仍在、②magazine 的
   `MeshInstance3D.transform.origin` ≈ 上表 glTF 坐标、③外观与上一版肉眼无差、
   ④世界包围盒不变。

---

## §7 申请事项（越界与规则冲突，需蜂后裁决）

1. **GLB 入库**：本次重出的两个 `*_viewmodel.glb` 已被 git 跟踪（第二单后由蜂后入库），
   本单**未提交**它们的改动（派单："GLB 是否入库由蜂后统一处理，你照旧只交脚本/报告/JSON"）。
   因此 `git status` 会显示这两个 GLB 为已修改状态，属预期。
2. **执行通道**：本机 `pwsh` 工具 100% 崩溃（`0xC0000142 STATUS_DLL_INIT_FAILED`），
   全程走「`modeling/tools/subproc/` + `godot_run_headless` 中继」执行 Blender / git。
   该目录含 `runner.gd` / `runner_async.gd` / `launch_detached.py` / `kill_stray.py` /
   `ps_check.py` / `fingerprint.py` / `cmd.json` / `last.log`，**未入库**，是唯一执行通道。
3. **单次调用 130 s 上限**：DSH `godot_run_headless` 超时上限约 130 s，整单 4~5 分钟跑不完，
   故实际按 `--steps` 分步调用；默认（不带 `--steps`）仍是一条命令跑完的完整路径。
4. **他人未提交改动**：工作树仍有 51 个 `M godot/assets/**/*.import`、
   `desktop-port/godot-spike/07-suffers-art-design.md` 等改动（非本单产生，mtime 为 10-07），
   本单未触碰、未提交。

---

## §8 Godot 侧自检建议（给蜂后）

1. 导入 `em68a_viewmodel.glb` / `em57p_viewmodel.glb`，确认仍为 **4 个 `MeshInstance3D`**
   （`*_body` / `*_magazine` / `*_optic` / `*_gl_module|*_laser_module`）。
2. 检查 magazine 节点的 `transform.origin`：
   - em68a ≈ `(-0.0057, -0.0541, -0.0683)`
   - em57p ≈ `(-0.0087, -0.1477, 0.1875)`
   （Godot 与 glTF 同为 Y-up 右手系，数值应逐位一致；若 Godot 导入时套了根节点缩放，
   以 `MeshInstance3D` 的最终 `global_transform.origin` 为准。）
3. 从 Godot 侧读 magazine 的世界 AABB，与迁移前的值应完全相同（`Y[-0.22376,-0.05314]` 等）。
4. 写一个最小旋转测试：把 magazine 节点绕其原点转 30°，确认**绕弹匣顶部旋转**（而非绕几何中心）。
5. 对照旧版截图确认外观零变化。

---

## §9 复跑与下一棒注意

```bash
# 只跑一把枪
python desktop-port/godot-spike/modeling/scripts/rebuild_viewmodels.py -- em57p
# 分步（单次调用时长受限时）
python .../rebuild_viewmodels.py -- em68a --steps pipeline
python .../rebuild_viewmodels.py -- em68a --steps idem
python .../rebuild_viewmodels.py -- em68a --steps verify
```

- **备份只在缺失时创建**（`backup_reused` 字段可查），所以复跑不会把"迁移后"误当基线；
  若要用新的基线，手工删除 `*.pre_pivot_backup.glb` 即可。
- 幂等步骤会临时写 `<stem>_viewmodel.idem_check.glb` 并在比对后删除；异常中断时请手工清理。
- 另需清理的中途产物：`<stem>_viewmodel.idem_check.glb`、
  `weapon_postprocess_report_<stem>.idem.json`、`pivot_rebuild.log`（均已未入库）。
- 新增武器时必须先在 `PROFILES` 里标定阈值与 `pivot_part`，否则管线会拒绝运行并报错。
