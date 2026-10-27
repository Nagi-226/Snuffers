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
