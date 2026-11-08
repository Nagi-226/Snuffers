# EM-127M 基础模型入库记录

日期：2026-11-08。本轮只处理资产，未挂载武器、未新增业务脚本、未调整战斗参数或第一人称握持。

## 型号与源文件

- 下载原件：`Downloads/407df3a4f27b220a454a64ad670ea518.glb`，未修改。
- 本地源备份：`em127m_hunyuan_v31_raw.glb`，与下载原件 SHA256 相同；仅留 modeling 工作区，不提交 Git。
- 概念参考：`em127m_reference.png`，保留原图。
- 识别依据：分节散热筒、双脚架、鼓状供弹箱、长镜、镂空握把保护架与枪托对应本型号概念图。没有根据下载顺序推断型号。
- 节点变换后 Blender 枪口方向为 **-X**；-X 端有散热筒和枪口，+X 端为枪托。正式处理绕 Blender Z 转 **-90°**，使枪口指向 Blender +Y / Godot **-Z**。

| 项目 | 源 GLB | 正式 GLB |
|---|---|---|
| 文件 | 本地 `em127m_hunyuan_v31_raw.glb` | `godot/assets/models/weapons/em127m_viewmodel.glb` |
| 字节数 | 84,012,756 | 15,399,736 |
| 三角面 | 1,499,756 | 70,000 |
| 顶点 / 导出属性顶点 | 876,368 | 72,850 |
| 网格 / primitive / 材质 | 1 / 1 / 1 | 1 / 1 / 1 |
| 内嵌 PNG | 3 张，各 4096×4096 | 3 张，各 2048×2048 |
| 贴图用途 | base color、normal、metallic-roughness | 保留相同三种用途 |
| 动画 / 骨架 | 无 / 无 | 无 / 无 |
| 材质 | OPAQUE、double-sided，KHR_materials_specular | 保留源材质设置和扩展 |
| SHA256 | `374f23dc88d8f140fae6fdb9933fcb88f66327d88c352b3098832625fc00190e` | `09c83ea7089814d53f7ea4421b2dcf90143fc4e38926d1c1798f6380ec4c3224` |

## 处理参数与验证

- 复用 `desktop-port/godot-spike/modeling/scripts/prepare_generated_asset.py`，Blender **5.2.3 LTS**。
- root 冻结工作参数：最长边 **1.30m**、目标 **70,000** 三角面、贴图最长边 **2048**、yaw **-90°**。
- 1.30m 只作为本轮入库工作尺度，未当成设定尺寸或实机标定结论。
- 原始 Blender 世界包围盒尺寸为 `(1.179819, 0.340228, 0.445858)`，需先应用导入节点变换再判断轴向，不能只读 primitive 局部轴。
- 正式 Godot XYZ 尺寸为 `(0.374645, 0.491545, 1.300754)m`。减面后最长边较名义 1.30m 多约 0.754mm；记录实际值，未伪称完全等于名义尺度。
- 正式 Godot 包围盒：min `(-0.187301, -0.245891, -0.650736)`，max `(0.187343, 0.245654, 0.650019)`。
- 二进制检查确认 GLB 2.0 标头和声明长度有效；全部 PNG 可解码、内嵌、尺寸达标；POSITION/NORMAL/UV0 和索引有效；节点平移/旋转/缩放已应用。
- 导出保持完整单体外形，没有开孔、删瞄具、透明镜片改造或拆分供弹/脚架。输出不含动画、骨架、灯光、摄像机、Draco。
- Blender 导出提示多纹理节点共用采样设置；正式文件仍有三张正确关联的 PBR 贴图，材质关联已通过下述 Godot 检查。

### Godot 实证（root 串行执行）

- Godot **4.6.2** 成功导入并实例化 PackedScene；PBR albedo、normal、metallic、roughness 加载通过。
- 2048 贴图、70,000 三角面、包围盒居中及入库工作尺度、无骨架检查全部通过。
- **Vulkan Forward+ / RTX 4060** 成功渲染侧面、前端、后端、斜视四图。
- 标准 `godot/tools/check.ps1` 完整 L1：**148 脚本 / 43 场景 PASS**。
- 上述为独立静态模型的引擎导入与渲染验证，未验证武器挂载、ADS 通光、握持、射击或换弹。

执行方式（仓库根目录）：

```powershell
& 'D:/steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python 'desktop-port/godot-spike/modeling/scripts/prepare_generated_asset.py' -- 'desktop-port/godot-spike/modeling/em-weapons/em127m/em127m_hunyuan_v31_raw.glb' 'godot/assets/models/weapons/em127m_viewmodel.glb' weapon 1.30 70000 'desktop-port/godot-spike/modeling/em-weapons/em127m/preview' -90
```

## 已知源模局限与明日待办

- 源模主要外壳未见大片缺面，单体基础入库可用；未作全模型水密判定。
- 瞄具两端为深色不透明表面，不能宣称 ADS 通光；明日需在实际镜轴上验证视线，再决定镜片/遮挡处理。
- 枪口中心显示暗色端面；真实贯通尚未通过几何射线或逐面检查，本轮保留原样。
- 供弹与脚架均包含在单体网格内，无独立换弹、供弹或脚架动画件。
- 纹理小字较模糊、部分凹槽圆润，保留源生成模型特征；不以概念图细节冒充实际模型已有结构。
- 明日另做第一人称尺度、朝向、枪口/镜轴、握持、近裁剪和动作标定；这些均未在本轮完成。

## 预览范围

- 可提交源模证据：`preview/source_views.png`，含按实际轴命名的侧面、枪口、后端与两张斜视。
- `preview/source_side_*.png`、`source_muzzle.png`、`source_rear.png`、`source_iso_*.png` 及 Blender `side.png/front.png/rear.png/iso.png` 为本地诊断图，不保证在 Git checkout 中存在。
- 正式 Godot 静态预览已生成并纳入本次资产提交：`preview/godot_side.png`、`preview/godot_front.png`、`preview/godot_rear.png`、`preview/godot_iso.png`。这些是静态引擎预览，不是武器实机验证。
- 原始 GLB 备份及 `.kimi-tmp/weapon_glb_intake/` 检查脚本、结构 JSON 和诊断贴图均不随资产提交。
