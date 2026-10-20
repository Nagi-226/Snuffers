# 第一人称持枪手臂建模报告（派单 18 · EM-68A / EM-57P）

> 域：`desktop-port/godot-spike/modeling/`（W9 深度蜂）｜分支 dev1
> 日期：2026-10-20｜脚本：`desktop-port/godot-spike/modeling/scripts/build_fp_arms.py`
> 机读数据：`desktop-port/godot-spike/modeling/scripts/out/arms_em68a.json`、`arms_em57p.json`

---

## 0. 结论

| 项 | EM-68A（步枪） | EM-57P（手枪） |
|---|---|---|
| 交付 GLB | `godot/assets/models/weapons/arms_em68a.glb` 485,776 B | `godot/assets/models/weapons/arms_em57p.glb` 485,768 B |
| sha256 | `4a6e0df8c62b4ca5e313aa821314d9ca2884368003285c0265aaad28593e2008` | `8b3ef3175da3e9e9fa5d6122dee65303fed440580d184d4b759ce4ce055cbc4f` |
| 对象 | `em68a_arm_right` / `em68a_arm_left` | `em57p_arm_right` / `em57p_arm_left` |
| 三角面 | 1,188 / 1,190（预算 ≤15,000 ×） | 1,188 / 1,190 |
| 顶点 | 636 / 640 | 636 / 640 |
| 贴图 | 单张 1024² PNG 内嵌（sleeve / glove / pad / patch 四块 UV） | 同 |
| 穿模（收敛后） | **0 顶点 / 0.000000 m** | **0 顶点 / 0.000000 m** |
| 武器 GLB 改动 | 无（前后 sha256 相同，脚本内断言） | 无 |

- 手臂以**武器 GLB 的同一局部空间**落位（Godot 局部：X 右、Y 上、+Z 后、枪口 -Z，米制），导入后与武器实例同级挂在 `ViewModel` 下即为对位状态，**不需要再摆位**。
- 手枪沿用 `pistol.tscn` 的 `scale 0.4`，故脚本内 `hand_scale = 2.5`（手枪局部单位下建手，缩放后与真手同尺寸）。

---

## 1. 环境与命令

```bash
# Blender 5.2.2 LTS（headless，必须带 --factory-startup 与 --python-exit-code 1）
"D:\steam\steamapps\common\Blender\blender.exe" -b --factory-startup --python-exit-code 1 \
  --python "desktop-port/godot-spike/modeling/scripts/build_fp_arms.py" -- em68a em57p --render
```

- 无参数默认跑两把枪；`--render` 额外输出 Workbench 验证图；`--arms-only` 输出仅手臂的调试图。
- 脚本**只写**三个位置：`godot/assets/models/weapons/arms_<stem>.glb`、`modeling/scripts/out/arms_<stem>.json`、`modeling/em-weapons/renders_fp_arms/*.png`。
- 本机 `pwsh` 工具 100% 崩溃（0xC0000142），一律经 `modeling/tools/subproc/`（`runner.gd` + `cmd.json`）中继执行；`godot_run_headless` 单次调用约 130 s 上限，本脚本单枪约 25 s。

---

## 2. 坐标系与落位依据（实测，非猜测）

武器 GLB 是 glTF Y-up 存储，Blender 导入后变成 Z-up：`(x, y, z)_gltf → (x, -z, y)_blender`。脚本里所有锚点都按 glTF/Godot 局部空间记录，**建网格时统一经 `gltf_to_blender()` 转换**（det=+1，不改绕序与法线方向）。导出用 `export_yup=True`，往返一次回到同一坐标系。

握持锚点（从武器 GLB 实测，单位 m，glTF 局部空间）：

| 项 | EM-68A | EM-57P |
|---|---|---|
| 握把中心 | ≈ `(0, -0.115, 0.205)` | ≈ `(0, -0.235, 0.240)` |
| 握把 Z 区间（后→前） | 0.146…0.253 | 0.100…0.340 |
| 右手腕 | `(0.074, -0.105, 0.352)` | `(0.150, -0.262, 0.560)` |
| 左手腕 | `(-0.034, -0.132, -0.232)`（护木下方） | `(-0.150, -0.300, 0.600)`（托住右手） |
| 支撑手位置依据 | 护木段 Z -0.414…-0.150，body 下缘 Y +0.012、gl_module Y -0.032 → 手在 Y<-0.035 的自由空间 | 握把两侧 -0.071…+0.071 |

**右手四指沿握把轴向（`spread=(0,1,0)`，食指最高）堆叠**、掌心朝武器内侧，这是抓握竖直握把的正确指序；第一版把四指横向摊开是错的（已修）。

---

## 3. 几何与材质做法

- 单手 = 掌体（四段放样）+ 四指（各三关节，逐段放样并在关节处封盖）+ 拇指（两段）+ 前臂袖管（肘部断面起，带袖口翻边）+ 左臂 EDAA 臂章贴片（手背上方 quad）。全部放样后 `bmesh.ops.recalc_face_normals` 统一朝外，避免封盖反法线出现"黑洞"。
- 手部基准尺寸按真人数据取整：掌长 98 mm、掌宽 86 mm、掌厚 31 mm、指节 45.5/28/21 mm、指径 21.6 mm、前臂长 250 mm。
- 贴图：numpy 生成单张 1024² PNG，四块 UV 区域分别对应 ①深色作战服布料（低对比噪点 + 缝线）②战术手套皮革（细颗粒 + 缝线）③指节护垫（深色 + 高光）④EDAA 臂章（暗底 + 青蓝描边）。材质 = Principled BSDF，Base Color 接贴图，Emission 用同图（强度 2.2）出青蓝自发光条纹，Roughness/Metallic 走 Separate Color 从同一张图取通道。整包内嵌，不引用外部文件。

---

## 4. 不穿模验证

方法：对每只手臂的 1276 个顶点，用 **BVHTree 三方向射线奇偶表决**判内外（武器网格是 AI 生成的分块壳体、非闭合流形，单方向奇偶会出大量假阳性——实测曾把武器下方 17 cm 的点判成"内部"，故改为三个固定方向**全部为奇数**才计为内部）。

自动避让：若某只手仍有穿插，沿该手预设的 `clear_dir`（右手 ±X 外侧、左手 -Y 下方）整体平移「穿透深度 + 2.5 mm」，最多 3 轮，每轮重测。**宁可留 ≤3 mm 缝隙也不穿模。**

| 阶段 | EM-68A 右手 | EM-68A 左手 | EM-57P 右手 | EM-57P 左手 |
|---|---|---|---|---|
| 初测 | 58 点 / 14.36 mm | 6 点 / 38.25 mm | 65 点 / 43.05 mm | 16 点 / 32.39 mm |
| 避让第 1 轮 | 35 点 / 10.07 mm | 0 / 0 | 5 点 / 4.81 mm | 0 / 0 |
| 避让第 2 轮 | 17 点 / 7.45 mm | 0 / 0 | 1 点 / 3.48 mm | 0 / 0 |
| 避让第 3 轮 | **0 / 0** | **0 / 0** | **0 / 0** | **0 / 0** |

最终两把枪共 4 只手全部 0 穿插顶点。避让位移量写在各枪的 `out/arms_<stem>.json` → `penetration.moved`。

---

## 5. 验证渲染（`modeling/em-weapons/renders_fp_arms/`，按派单不入库）

- `em68a_side.png` / `em57p_side.png`：侧视（相机 +X 看 -X），看整体姿态与握把接触。
- `em68a_front.png` / `em57p_front.png`：正视（从枪口方向看），看左右手是否对称、有无穿出。
- `em68a_fp_true.png` / `em57p_fp_true.png`：**按当前 `player.tscn` 实际变换**（`WeaponMount (0.35,-0.30,-0.50)` + `rifle (0,0.02,0.12)` / `pistol scale 0.4 (0,0.03,0.04)`，fov 75°）回算的第一人称视角。
- `em68a_fp_suggested.png` / `em57p_fp_suggested.png`：按提案变换（`wp_sugg = (-0.25, 0.24, -0.05)`）回算的第一人称视角。
- `em68a_grip34.png` / `em68a_far34.png`：握把特写与反面检查（确认手指没有从握把另一侧穿出）。

---

## 6. 已知问题（需要蜂后/机主裁决）

1. **按当前 `player.tscn` 的实际变换，第一人称视角里几乎看不到手**：`WeaponMount` 平移 `(0.35,-0.30,-0.50)` 使武器原点在相机前 0.50 m、右下 0.35/0.30 m；步枪枪托后端（局部 z=+0.5）因此落在相机后方 0.12 m，握把落在相机前仅约 0.08 m 且横向偏离约 0.41 m → 握把整体在 75° 水平视锥外（横向半张角约 31°）。这不是手臂的问题，是挂载变换的问题。`player.tscn` 属我禁改文件，**提案见 §7-1**，`fp_suggested` 就是按提案渲染的效果图。
2. **手臂是简化造型**：手指为三段直筒放样，关节处封盖，未做皮肤褶皱与指甲；袖口为薄翻边。满足 15000 面预算与「可辨认的作战服前臂 + 战术手套」要求，但不是美术级成品。
3. **未在 Godot 内验证**：派单规定 Godot 侧验证归蜂后。本地只做了 Blender 侧几何与 Workbench 渲染验证。
4. **左手对位取的是「托护木下缘」**（EM-68A）与「托右手」 （EM-57P）。若机主要求「手握护木侧面」或手枪单手不扶，改 `PARAMS[*]["left"]` 一处即可。

---

## 7. 申请事项

1. **申请调整武器挂载**（`.tscn` 属我禁改域）：建议 `WeaponMount` 平移由 `(0.35,-0.30,-0.50)` 改为约 `(-0.25,0.24,-0.05)` 的等价组合，或把 `rifle.tscn` / `pistol.tscn` 里武器实例的局部偏移前推约 0.15–0.25 m。否则手臂再准也看不见。`em68a_fp_suggested.png` / `em57p_fp_suggested.png` 是按此提案渲的。
2. **申请 GLB 入库裁决**：`arms_em68a.glb` / `arms_em57p.glb`（各 ~474 KB）已写入 `godot/assets/models/weapons/`，是否入库按第二单惯例由蜂后统一处理；本次我只提交脚本 + 报告 + 机读 JSON。
3. **申请渲染图存放**：`modeling/em-weapons/renders_fp_arms/` 6×2 张 PNG（约 1 MB）按派单不入库，若需要进文档请告知。

---

## 8. Godot 侧自检建议（蜂后执行）

1. 把 `arms_em68a.glb` / `arms_em57p.glb` 拖进对应武器场景，作为 `EM68A` / `EM57P` 实例的**兄弟节点**（同在 `ViewModel` 下，`transform` 保持 identity），不要作为它们的子节点——手臂与武器共享同一局部原点。
2. 检查 4 个 `MeshInstance3D`（每枪 2 个），三角面各 1188 / 1190，材质 1 个、贴图内嵌。
3. 侧视（编辑器正交视图）确认手指包住握把、无一根手指从另一侧穿出。
4. 若按 §7-1 调了挂载，用第一人称视角确认能看到右手背与左前臂。
5. 武器 GLB 的 sha256 应仍为 `em68a_viewmodel.glb` = `7bc7bbfa…d06f28c`、`em57p_viewmodel.glb` = `19ee99d3…43c5a`（本单未改动）。

---

## 9. 复跑与注意事项

1. 复跑会**覆盖** `godot/assets/models/weapons/arms_*.glb`；若要留旧版请先备份。
2. 自动避让会改手臂整体位置（≤ 数 mm 级），因此**同一份输入重跑结果稳定**（脚本内无随机项，贴图噪点用固定 seed）。
3. 换新武器时：先在 `PARAMS` 里加一档锚点（握把中心/朝向/护木截面按 §2 的方法实测），再跑一次看 `renders_fp_arms/` 的 side/far34 两张。
4. `--render` 会覆盖同名 PNG；`--arms-only` 的调试图名为 `*_arms34.png`，不覆盖交付图。
5. 武器 GLB 路径写死在 `PARAMS[stem]["weapon"]`，改名会直接报错退出（防止套错枪）。
