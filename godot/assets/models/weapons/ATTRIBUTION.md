# ATTRIBUTION.md — assets/models/weapons

## Glock 17 / SIG MPX 社区候选登记（2026-11-10，未入库）

- **状态**：仅完成候选核验，无模型下载日期、正式GLB或游戏引用；不使用混元3D生成这两种武器。
- **Glock 17 已获机主同意**：`G17 pistol`，作者MarkkuK；https://sketchfab.com/3d-models/g17-pistol-374ba78efdef4151acd626fb82f81369 。尚未下载或入库。
- **SIG MPX 路线A已批准**：`Sig Sauer MPX`，作者michalstk11；https://sketchfab.com/3d-models/sig-sauer-mpx-d6e0a8020a7b4a9a876787ec91290022 。组合Sambit_Raut的EXPS3、elitej1gaming的Foregrip、D_U的AN/PEQ15、mbvisuals1的M600DF；各自URL及CC-BY4.0证据见候选清单。尚未下载或装配。
- **G17 Gen5战术灯候选**：`G17 Gen 5 Handgun + Olight - NSW Police Force`，作者8sianDude（@haoliu95）；https://sketchfab.com/3d-models/g17-gen-5-handgun-olight-nsw-police-force-0200c248eba14385ad2bee8d4dc4e586 。2026-11-10核验CC-BY4.0、可商用须署名，含Olight PL-2白光灯及夜光机械瞄具。机主询问适用性，未定为替换原G17；下载日期、原件哈希、正式输出和修改记录均待实际处理补齐。
- **许可核验**：本日Sketchfab官方模型API标注CC-BY 4.0，可商用、须署名；格式GLB/glTF。正式接入仍需核对包内说明、上游来源、尺寸和动画部件，并补完整入库记录及游戏内署名。
- **候选清单与证据**：`desktop-port/godot-spike/08-community-weapon-candidates-2026-11-10.md` 及同名JSON；包含面数/贴图、动画备选与未完成检查。

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

## EC-120 多用途导弹（2026-11-09）

- **正式资产**: `ec120_missile.glb`，用于 EM-120R 实际飞行导弹。
- **作者/来源**: 机主本轮确认在腾讯混元 3D 生成并提供下载文件。来源 URL: https://3d.hunyuan.tencent.com/creation 。
- **许可/权属**: 生成输出适用腾讯混元平台条款；本轮依据机主来源确认登记，未重新审核平台条款。
- **下载日期**: 2026-11-09。原件 `C:/Users/FJL03/Downloads/3db60707308f6ce53c8f550f8fba6af5.glb` 保留且不提交；SHA256 `30cc76b2950950b6ddbc719ca2f04f058ca1d15d119495cb6379fd38307303a6`。
- **本地处理**: 复用 `prepare_generated_asset.py`，1,500,000 面减至16,000，内嵌贴图最长边2048；工作长度0.80m，实际0.800898m。Blender实测+X弹头旋转90°至+Y，导出为Godot -Z；前/后/侧视图确认弹头与尾喷口朝向。
- **正式SHA256**: `5cd73209d975ad5992bf169bd900398292d762874887f051034d6b2c0deab9f2`。无外部源贴图或动画依赖；尾焰在运行时生成，冷推出阶段不显示尾焰。

## 雷械真实弹匣拆件（2026-11-10）

- 衍生资源以 `_reload.glb` 命名：EM-57S-1、EM-68L、EM-57S-2 ADS、EM-86B/D/S/M ADS、EM-12G-2、EM-127G/M、EM-40T-1、EM-127P；均由本目录对应项目自有原模型加工，不引入新的第三方网格或贴图。
- 处理：按实际弹匣位置，将原网格的每个面分配到枪身或 `DetachableMagazine`，保留原面、UV、材质和法线；原始游戏资源不改写。EM-57S-2 依据 `modeling/em-weapons/em127p/reference/weapon_naming.md` 的顶置横匣设定向上拔匣，其余依各枪底部结构定位。
- 源/衍生 SHA256、面数、真实弹匣边界与枢轴、方向和抓点见 `desktop-port/godot-spike/modeling/reload_magazines/prepared_magazines.json`。处理管线为 `modeling/scripts/prepare_reload_magazines.py` 与 `magazine_cut_regions.json`。
- 既有 EM-68A / EM-68D / EM-12G-1 原本就有真实独立弹匣，沿用其原资源；SPAS-12 保留管式逐壳，EM-120R 沿用原装填机制。
- 黑色手臂为独立 CC-BY 4.0 资源，完整上游及改作署名见 `godot/addons/community_weapons/ATTRIBUTION.md`；不改变本节雷械模型的项目自有来源。

## EM-120R 后部导弹装填视觉（2026-11-10）

- **名称**：LoadingMissile，复用已有 EC-120 导弹模型。
- **作者/来源**：既有 `ec120_missile.glb` 的来源/作者/权属沿用本台账原登记；本项目/Codex仅实现后部装填动作，没有新增网格、贴图或下载原件。
- **来源URL**：https://github.com/Nagi-226/Snuffers/blob/dev1/godot/scenes/weapons/em120r.tscn
- **许可/权属**：沿用既有EM120R/EC120模型来源与平台条款。
- **日期/用途**：2026-11-10，按机主最新指令移除侧面供弹模块，直接用既有导弹从后口装填；10发/3秒批量结算不变。真实后口、尾段抓点与运动参数集中于GameConfig/计划§7.2。

## EC-60E「闷罐」手投等离子雷（2026-11-12）

- **正式资产**：`ec60e_grenade.glb`，用于实体投体与 HUD 实模线稿参考。
- **作者/来源**：机主提供并确认型号的 EC-60E GLB；概念参考为机主本地 `E:/EDAA/E系列电磁轻武器-概念图谱.html`。本轮未取得该下载模型的生成平台、原作者或公开来源 URL，不能据相似文件名推定来源。
- **来源位置**：`C:/Users/FJL03/Downloads/EC-60E 闷罐.glb`（机主已从 `4f97956fcaea0b22b091bf6784211c08.glb` 改名）。源文件 86,298,640 字节，SHA256 `D0E3FA0ECFC0993B8BAAB5A4B4AF876902972CFEE597DDE86BEB17F0DBEDA603`；Downloads 原件保持，不提交原始高面数文件。
- **许可/权属**：机主提供用于本项目接入；原模型许可证和原作者信息本轮未提供，登记为待补充，不声明 CC0、CC-BY 或平台许可。
- **本地处理**：本项目 Codex 复用 `prepare_generated_asset.py`，居中并按约 60mm 直径／91.5mm 长边工作尺度减面；1,500,000→12,000 三角面，Godot 实际 X/Y/Z 包围尺寸约 59.75×91.92×60.06mm（Y 为高度；离线 Blender 使用 Z 向上）。保留原 PBR，3 张贴图最长边 2048 并内嵌，无外部贴图路径；运行 GLB 12,648,636 字节。离线日志与预览在 `.kimi-tmp/nov12_ec60e/`。
- **日期**：2026-11-12。本轮未增加游戏运行时外部依赖。
