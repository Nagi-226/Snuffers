# ATTRIBUTION.md — assets/models/weapons

## arms_rifle.glb / arms_pistol.glb（第一人称手臂，2026-10-20 入库）

- **名称**: Rigged FPS Arms
- **作者**: RafaP（Sketchfab 发布者）；原始模型作者 DJMaesen（a.k.a. bumstrum）
- **来源 URL**: https://sketchfab.com/3d-models/rigged-fps-arms-6b1cde4746774b7893513f84cac7a866
- **许可证**: CC-BY 4.0（可商用，须署名）——游戏内署名清单需列入 "Rigged FPS Arms by DJMaesen / RafaP (CC-BY 4.0)"
- **下载日期**: 2026-10-20
- **本地化改动**（管线 `desktop-port/godot-spike/modeling/arm-candidates/export_arms.py`）:
  - 保留原网格与骨架，数值摆姿后重定向真实换弹动画；首帧保持原握姿
  - 底图处理：手腕肤色带涂深、整体压暗偏青蓝；手臂/手掌分面提高夜景可读性
  - 右臂外侧贴 EDAA 徽记布章（徽记源文件 E:\EDAA\EDAA徽记.png，项目自有设定资产）
- **原始文件**: `desktop-port/godot-spike/modeling/arm-candidates/rigged_fps_arms.glb`（按资产卫生规则不入库）

## Cransh 换弹动画（2026-10-24 重定向入库）

- **步枪**: Animated FPS Hands Rifle Animation Pack，作者 Cransh，使用 FP Arms / bumstrum
  - https://sketchfab.com/3d-models/animated-fps-hands-rifle-animation-pack-5f2d0ed780a94724b36ab505f7564057
  - 剪辑 `Armature|Arms_FPS_Anim_Reload_Fast`，重定时为 2.0 秒
- **手枪**: FPS Pistol Animations，作者 Cransh
  - https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d
  - 剪辑 `Armature|FPS_Pistol_Reload_full`，重定时为 1.6 秒
- **许可证**: CC-BY（Sketchfab 资产页标注）——游戏内署名需包含 "Cransh" 及上述两个动画包名称
- **下载日期**: 2026-10-24
- **本地化改动**: 60fps 重定向至 RafaP 手臂，36 根手臂/手指骨；源武器坐标对齐、臂长与第一人称取景适配；同源弹匣辅助骨；不使用 Cransh 低模网格
- **原始文件**: `godot/raw_assets/fps_reload/rifle_crank.glb` / `pistol_crank.glb`（按资产卫生规则不入库）

## EM-68D「穿杨」与 EM-12G-1「霰·Ⅰ」（2026-10-27 入库）

- **资产**: `em68d_viewmodel.glb`、`em12g1_viewmodel.glb`、`em12g1_magazine.glb`
- **来源**: 项目自有 EDAA 概念图，Kimi Work 免费图生 3D；输入为 `em68d_dmr_input.png`、`em12g1_shotgun_input.png`
- **许可/权属**: 项目自有设定与生成资产；非第三方素材，无额外署名要求
- **原始模型**: `desktop-port/godot-spike/modeling/em-weapons/em68d_raw.glb`、`em12g1_raw.glb`
- **本地处理**: 米制/朝向归一、游戏面数处理；Kimi Code 使用 `split_generated_weapon.py` 按实测连通分量拆出 body/magazine/optic、弹匣顶部枢轴、`add_glb_tangents.py` 补标准切线；未改变主体外形、UV 或材质
- **生成源备份**: `em68d_whole.glb`、`em12g1_whole.glb`（ modeling 工作区，非游戏引用）

## Low Poly SPAS-12（2026-10-31 引入）

- 正式资产：`spas12_display.glb`，用于第二关灯芯遗物货架拾取展示；第一人称使用下述 Saucy 部件模型。
- 作者：LowPolyCount（Sketchfab 用户 @EndangeredOXX）。
- 来源：https://sketchfab.com/3d-models/low-poly-spas-12-a8d79e51ed18443dbb8bbcc6d59cb9d7
- 许可证：Creative Commons Attribution（CC-BY）；下载页明确允许商用，必须署名。
- 署名文案：`Low Poly SPAS-12 by LowPolyCount is licensed under Creative Commons Attribution.`
- 本地改动：仅作为静态展示模型缩放与摆放；未改网格或材质，未引入原始 .blend 文件。

## Franchi SPAS-12 (Low-poly)（2026-11-01 第一人称启用）

- 正式资产：`spas12_viewmodel.glb`，用于 SPAS-12 第一人称模型与独立泵套部件运动。
- 作者：Saucy（Sketchfab 用户 @saucy）。
- 来源：https://sketchfab.com/3d-models/franchi-spas-12-low-poly-bed6a6e266cb44fc871d1cf18b268787
- 许可证：Creative Commons Attribution（CC-BY）；下载页明确允许商用，必须署名。
- 署名文案：`Franchi SPAS-12 (Low-poly) by Saucy is licensed under Creative Commons Attribution.`
- 动画：原始绑定含 `SPAS-12|Pump_01/02/03` 等动画；游戏内按独立 `Action_sleeve` 网格驱动泵动，第一人称双臂复用项目已登记手臂。
- 本地改动：静态部件烘焙以避免 Godot 蒙皮姿态异常，统一米制尺度与第一人称朝向；原始绑定备份在 modeling 工作区，未引入原始 .blend 文件。

## EM-57S-1「雹·Ⅰ」/ EM-68L「殷雷」/ EM-127P「锏」（2026-11-07 入库）

- **正式资产**: `em57s1_viewmodel.glb`、`em68l_viewmodel.glb`、`em127p_viewmodel.glb`。
- **来源**: 项目自有 EDAA 概念设定，AI 图生 3D 原始模型；无第三方网格或贴图，无额外署名要求。
- **原始模型**: `desktop-port/godot-spike/modeling/em-weapons/em57s1/em57s1_hunyuan_v31_raw.glb`、`em68l/em68l_hunyuan_v31_magazine_adjusted.glb`、`em127p/em127p_hunyuan_v31_raw.glb`（原始工作区，不直接入库）。
- **本地处理**: `prepare_generated_asset.py` 统一米制长度与枪口 -Z、几何居中、贴图最长边 2048；三角面分别由 1500000/1499208/1500000 减至 59999/70000/40000；导出游戏用 GLB。EM-127P 另经 `open_em127p_optic.py` 仅将镜内遮挡面改为透明材质，完整保留原始 40000 三角面，不删除几何；后部黑色原面板的几何、UV 与材质均保持，无额外方片或灯带。
- **生成日期**: 2026-11-07。

## EM-86S「惊蛰」/ EM-86B「裂空」/ EM-86D「贯日」（2026-11-07 入库）

- **正式资产**: `em86s_viewmodel.glb`、`em86b_viewmodel.glb`（ADS 开孔版）、`em86b_viewmodel_intact.glb`（常规完整版）、`em86d_viewmodel.glb`。
- **来源**: 项目自有 EDAA 概念设定，AI 图生 3D 原始模型；无第三方网格或贴图，无额外署名要求。
- **原始模型**: `desktop-port/godot-spike/modeling/em-weapons/em86s/em86s_hunyuan_v31_raw.glb`、`em86b/em86b_hunyuan_v31_retry_raw.glb`、`em86d/em86d_hunyuan_v31_retry_raw.glb`（原始工作区，不直接入库）。
- **本地处理**: `prepare_generated_asset.py` 将三把源模的 Blender -X 枪口统一旋转 -90° 到 Blender +Y / Godot -Z；米制长度 1.05/0.95/1.08m、几何居中、贴图最长边 2048；三角面分别由 1500000/1499986/1499998 减至各 70000，导出游戏用 GLB。初版误按 +90° 导出导致枪托朝前，机主实机指认后已按正确映射重导出。EM-86B 另经 `open_em86b_optic.py` 清除瞄具轴心遮挡面，形成真实贯通镜筒，保留镜框、UV 与材质。
- **生成日期**: 2026-11-07。

## EM-127G「凿空」/ EM-12G-2「霰·Ⅱ」（2026-11-07 入库）

- **正式资产**: `em127g_viewmodel.glb`、`em12g2_viewmodel.glb`。
- **来源**: 项目自有 EDAA 概念设定，AI 图生 3D 原始模型；无第三方网格或贴图，无额外署名要求。
- **原始模型**: `desktop-port/godot-spike/modeling/em-weapons/em127g/em127g_hunyuan_v31_raw.glb`、`em12g2/em12g2_hunyuan_v31_raw.glb`（原始工作区，不直接入库）。
- **本地处理**: `prepare_generated_asset.py` 按各自枪口实测分别旋转 -90°（EM-127G）与 +90°（EM-12G-2）到 Godot -Z；长度 1.15/0.90m、几何居中、贴图最长边 2048；三角面分别由 1499222/1499648 减至各 70000。
- **生成日期**: 2026-11-07。


## EM-57S-2「雹·Ⅱ」/ EM-86M / EM-40T-1（2026-11-08 入库）

- **正式资产**: `em57s2_viewmodel.glb`、`em86m_viewmodel.glb`、`em40t1_viewmodel.glb`。
- **来源**: 机主提供的项目自有 EDAA 概念参考图，腾讯混元 3D V3.1 单图生成；无第三方网格或贴图，无额外署名要求。
- **原始模型**: `desktop-port/godot-spike/modeling/em-weapons/em57s2/em57s2_hunyuan_v31_raw.glb`、`em86m/em86m_hunyuan_v31_raw.glb`、`em40t1/em40t1_hunyuan_v31_raw.glb`（原始工作区，不直接入库）。
- **本地处理**: `prepare_generated_asset.py` 按实测 +X 枪口统一旋转 +90° 到 Blender +Y / Godot -Z；长度分别为 0.82/1.10/1.00m、几何居中、贴图最长边 2048；三角面分别由 1500000/1499846/1499676 减至 59999/70000/70000，导出游戏用 GLB。初版 EM-57S-2 / EM-86M ADS 删除344/1476面，机主实机截图确认误伤镜框；本轮 `restore_optic_shells.py` 从常规完整版恢复全部原表面积，沿窄镜轴精确分割原面，只有中心遮挡片使用透明材质，框缘维持不透明；ADS最终60883/71160三角面，两个常规GLB不改。EM-40T-1 先经 `move_em57s2_actual_tail.py` 移植 `tail_11` 原184面环、UV与材质（该历史文件名不能证明是真枪尾，实际在EM-57S-2负Z枪口端）；初版宽范围删面导致前镜壳破洞，本轮 `restore_em40t1_shell.py` 从初次入库Git资产恢复2741个原前壳面，精确分割为2842面。`restore_em40t1_cap_center.py` 恢复同源34面真实中心表面、适配至原孔后侧，并增加70面连接；`restore_em40t1_top_seam.py` 以168面连接真实顶部边界。原184面环及贴图不动，中央孔在原环中本就开放，本轮为镜片与接缝补全，最终64791面；只验证指定局部闭合，不宣称整个AI模型水密。
- **生成日期**: 2026-11-08。
- **EM-86M 通光续修**（同日机主实机反馈）：初次恢复的18mm半径仍压住镜内视野，后续仅将透明棱柱半径增至23.5mm，轴心 `(0,0.180)` 与深度 `[-0.23,0.17]` 不变。精确分割后72318三角面（71312不透明/1006透明），原1.104743598717944m²表面积完整保留，无删面；19个原框缘样本保持不透明，常规GLB、原贴图与其他两枪资产不改。

## EM-127M「雷霆」/ EM-120R「长弓」（2026-11-08 资产准备）

- **正式资产**: `em127m_viewmodel.glb`、`em120r_viewmodel.glb`；本轮仅准备静态基础模型，尚未接入武器场景或玩法。
- **作者/来源**: 机主提供的项目自有 EDAA 武器概念图，由机主在腾讯混元 3D 平台执行图生 3D 并下载。来源 URL: https://3d.hunyuan.tencent.com/creation 。输入图保存在 `desktop-port/godot-spike/modeling/em-weapons/em127m/em127m_reference.png`、`em120r/em120r_reference.png`。
- **许可/权属**: 概念设定与输入图为项目自有资产；生成输出适用腾讯混元平台条款。本轮未引入第三方下载网格或贴图，也未重新审核平台条款。
- **下载日期**: 2026-11-08。EM-127M 原下载文件 `407df3a4f27b220a454a64ad670ea518.glb`；EM-120R 原下载文件 `179182f8411d19f139e6aa848337c7ab.glb`。Downloads 原件保留，原始高面数副本仅保存在 modeling 工作区，不提交 Git。
- **本地处理**: 复用 `prepare_generated_asset.py`，依据实际枪口方向归一至 Godot -Z，几何居中，贴图最长边由 4096 降至 2048；目标各 70000 三角面。EM-127M/EM-120R 最长边分别采用 1.30/1.20m **资产工作尺度**，不代表已确定的设定尺寸或实机挂载标定。
- **复现与限制**: 两型号目录的 `asset_intake.md` 记录源文件哈希、处理参数、正式资产统计及明日实机接入注意事项。源模为静态单网格，无独立骨架或换弹动画；瞄具通光、供弹部件拆分、握持与碰撞均需实机接入阶段另外验证。
- **技术验证**: 正式两份各 70000 三角面、三张内嵌 2048 PNG；Godot 4.6.2 实际导入、PBR 贴图加载与 Vulkan 多视图渲染通过，标准完整 L1 148 脚本/43 场景通过。预览与技术通过仅覆盖静态资产准备。
