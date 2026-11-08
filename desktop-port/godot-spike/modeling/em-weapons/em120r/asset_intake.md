# EM-120R 基础模型入库记录

日期：2026-11-08。本轮只处理资产，未挂载武器、未新增业务脚本、未调整战斗参数或第一人称握持。

## 型号与源文件

- 下载原件：`Downloads/179182f8411d19f139e6aa848337c7ab.glb`，未修改。
- 本地源备份：`em120r_hunyuan_v31_raw.glb`，与下载原件 SHA256 相同；仅留 modeling 工作区，不提交 Git。
- 概念参考：`em120r_reference.png`，保留原图。
- 识别依据：长方筒体、前端大口径凹腔、后端方盖与圆形侧按钮、中央握把、顶置盒式瞄具对应本型号概念图。没有根据下载顺序推断型号。
- 节点变换后 Blender 枪口方向为 **-Y**；-Y 端为大口径凹腔，+Y 端为封盖。正式处理绕 Blender Z 转 **180°**，使枪口指向 Blender +Y / Godot **-Z**。
- 此源模型的最长世界轴为 Y，与 EM-127M 的 X 轴不同；X 向相机是侧视，Y 向相机才是前后端。`source_views.png` 已按实际含义命名。

| 项目 | 源 GLB | 正式 GLB |
|---|---|---|
| 文件 | 本地 `em120r_hunyuan_v31_raw.glb` | `godot/assets/models/weapons/em120r_viewmodel.glb` |
| 字节数 | 81,778,504 | 15,122,476 |
| 三角面 | 1,500,000 | 70,000 |
| 顶点 / 导出属性顶点 | 840,655 | 73,385 |
| 网格 / primitive / 材质 | 1 / 1 / 1 | 1 / 1 / 1 |
| 内嵌 PNG | 3 张，各 4096×4096 | 3 张，各 2048×2048 |
| 贴图用途 | base color、normal、metallic-roughness | 保留相同三种用途 |
| 动画 / 骨架 | 无 / 无 | 无 / 无 |
| 材质 | OPAQUE、double-sided，KHR_materials_specular | 保留源材质设置和扩展 |
| SHA256 | `cbfadfe7dc40d313db699d28f5411585c0c4e10c6179b530ad4e752cc1dab2d6` | `a608521a1358fc0424fda593fd5c85d1abb495209e64046f04466134b4c600d5` |

## 处理参数与验证

- 复用 `desktop-port/godot-spike/modeling/scripts/prepare_generated_asset.py`，Blender **5.2.3 LTS**。
- root 冻结工作参数：最长边 **1.20m**、目标 **70,000** 三角面、贴图最长边 **2048**、yaw **180°**。
- 1.20m 只作为本轮入库工作尺度，未当成设定尺寸或实机标定结论。
- 原始 Blender 世界包围盒尺寸为 `(0.209783, 1.175310, 0.467986)`，需先应用导入节点变换再判断轴向，不能只读 primitive 局部轴。
- 正式 Godot XYZ 尺寸为 `(0.214504, 0.477973, 1.200048)m`。减面后最长边较名义 1.20m 多约 0.048mm；记录实际值，未伪称完全等于名义尺度。
- 正式 Godot 包围盒：min `(-0.107266, -0.239003, -0.600017)`，max `(0.107238, 0.238970, 0.600031)`。
- 二进制检查确认 GLB 2.0 标头和声明长度有效；全部 PNG 可解码、内嵌、尺寸达标；POSITION/NORMAL/UV0 和索引有效；节点平移/旋转/缩放已应用。
- 导出保持完整单体外形，没有开孔、删瞄具、透明镜片改造或拆件。输出不含动画、骨架、灯光、摄像机、Draco。
- Blender 导出提示多纹理节点共用采样设置；正式文件仍有三张正确关联的 PBR 贴图，材质关联已通过下述 Godot 检查。

### Godot 实证（root 串行执行）

- Godot **4.6.2** 成功导入并实例化 PackedScene；PBR albedo、normal、metallic、roughness 加载通过。
- 2048 贴图、70,000 三角面、包围盒居中及入库工作尺度、无骨架检查全部通过。
- **Vulkan Forward+ / RTX 4060** 成功渲染侧面、前端、后端、斜视四图。
- 标准 `godot/tools/check.ps1` 完整 L1：**148 脚本 / 43 场景 PASS**。
- 上述为独立静态模型的引擎导入与渲染验证，未验证武器挂载、ADS 通光、握持、射击或装填。

执行方式（仓库根目录）：

```powershell
& 'D:/steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python 'desktop-port/godot-spike/modeling/scripts/prepare_generated_asset.py' -- 'desktop-port/godot-spike/modeling/em-weapons/em120r/em120r_hunyuan_v31_raw.glb' 'godot/assets/models/weapons/em120r_viewmodel.glb' weapon 1.20 70000 'desktop-port/godot-spike/modeling/em-weapons/em120r/preview' 180
```

## 已知源模局限与明日待办

- 源模主要筒壳未见大片缺面，单体基础入库可用；未作全模型水密判定。
- 前口显示黑色凹腔及凹底；是否真正贯通尚未通过几何射线或逐面检查，本轮保留原样。
- 顶部瞄具两端为深色不透明表面，不能宣称 ADS 通光；明日需在实际镜轴上验证视线，再决定镜片/遮挡处理。
- 源模型为单体静态网格，无独立装填、换弹或开闭件。
- 纹理小字较模糊、凹槽和棱角较圆润，保留源生成模型特征；不以概念图细节冒充实际模型已有结构。
- 明日另做第一人称尺度、炮口/瞄具轴、握持、近裁剪和装填表现标定；这些均未在本轮完成。

## 预览范围

- 可提交源模证据：`preview/source_views.png`，含按实际轴命名的侧面、枪口、后端与两张斜视。
- `preview/source_side_*.png`、`source_muzzle.png`、`source_rear.png`、`source_iso_*.png` 及 Blender `side.png/front.png/rear.png/iso.png` 为本地诊断图，不保证在 Git checkout 中存在。
- 正式 Godot 静态预览已生成并纳入本次资产提交：`preview/godot_side.png`、`preview/godot_front.png`、`preview/godot_rear.png`、`preview/godot_iso.png`。这些是静态引擎预览，不是武器实机验证。
- 原始 GLB 备份及 `.kimi-tmp/weapon_glb_intake/` 检查脚本、结构 JSON 和诊断贴图均不随资产提交。
