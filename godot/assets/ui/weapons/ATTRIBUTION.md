# 武器 HUD 模型轮廓线稿资产说明

这 16 张 SVG 同时用于右下角弹药 HUD 和顶部武器选择器。线稿依据各武器的完整游戏用 GLB 正交侧视提取，枪口朝右；不包含手臂、隐藏边或三角网格线。

处理方式：Blender Freestyle 提取可见轮廓与结构折线，按实模透明轮廓闭合外框，合并可见短链、简化曲线并减少倒角细节。手枪与步枪的浅面板主轮廓按同一正交参考校描。外轮廓、主结构、细节分别使用不同线宽和亮度；所有图共用 `120×58` 视区，SVG 原始尺寸为 `240×116`。

下表中的模型路径均相对于 `assets/models/weapons/`。EM 系列的权属沿用该目录的 `ATTRIBUTION.md`：项目自有设定与生成资产，无第三方网格或贴图，不额外赋予 CC0 许可。

| 文件 | 对应武器 | 完整来源模型 | 作者 / 来源 | 许可证 / 权属 | 日期 |
|---|---|---|---|---|---|
| `em57p.svg` | EM-57P | `em57p_viewmodel.glb` | 项目自有 EDAA 设定与模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em68a.svg` | EM-68A | `em68a_viewmodel.glb` | 项目自有 EDAA 设定与模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em68d.svg` | EM-68D | `em68d_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em12g1.svg` | EM-12G-1 | `em12g1_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `spas12.svg` | SPAS-12 | `spas12_viewmodel.glb` | Saucy，Franchi SPAS-12 (Low-poly)；本项目轮廓处理 | CC-BY，衍生线稿保留署名义务 | 2026-11-08 |
| `em57s1.svg` | EM-57S-1 | `em57s1_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em57s2.svg` | EM-57S-2 | `em57s2_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em86m.svg` | EM-86M | `em86m_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em40t1.svg` | EM-40T-1 | `em40t1_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em68l.svg` | EM-68L | `em68l_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em127p.svg` | EM-127P | `em127p_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em86s.svg` | EM-86S | `em86s_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em86b.svg` | EM-86B | `em86b_viewmodel_intact.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em86d.svg` | EM-86D | `em86d_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em127g.svg` | EM-127G | `em127g_viewmodel.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |
| `em12g2.svg` | EM-12G-2 | `em12g2_viewmodel_intact.glb` | 项目自有 EDAA 设定与生成模型；本项目轮廓处理 | 项目自有资产 | 2026-11-08 |

## 雷霆 / 长弓（2026-11-09）

- `em127m.svg` / `em120r.svg`：分别由正式 `em127m_viewmodel.glb` / `em120r_viewmodel.glb` 的实际可见侧面轮廓生成，沿用项目青蓝线稿处理。
- 作者/来源：机主腾讯混元3D生成的项目武器模型；https://3d.hunyuan.tencent.com/creation 。生成输出适用平台条款；原模型来源登记见 `assets/models/weapons/ATTRIBUTION.md`。本轮未引入第三方图标，未重新审核平台条款。
- 日期：2026-11-09。

## SPAS-12 来源与署名

- 名称：Franchi SPAS-12 (Low-poly)。
- 原作者：Saucy（Sketchfab 用户 `@saucy`）。
- 来源 URL：https://sketchfab.com/3d-models/franchi-spas-12-low-poly-bed6a6e266cb44fc871d1cf18b268787
- 许可证：Creative Commons Attribution（CC-BY，沿用源资产页的标注）。
- 改动：根据已入库的第一人称部件模型与场景基变换提取可见侧面轮廓，转为青蓝 SVG；不包含原贴图。
- 署名文案：`SPAS-12 HUD linework derived from Franchi SPAS-12 (Low-poly) by Saucy, licensed under Creative Commons Attribution.`

SPAS-12 线稿来源是第一人称 Saucy 模型，与货架展示用的 LowPolyCount `spas12_display.glb` 分别记录。

## 9×19 社区武器图标（2026-11-11）

- `g17.svg`：Glock 17 Gen5 + Olight 的简化侧面示意线稿；外形参考已入库 `addons/community_weapons/g17_gen5_olight.glb`，原作者 8sianDude，来源 https://sketchfab.com/3d-models/g17-gen-5-handgun-olight-nsw-police-force-0200c248eba14385ad2bee8d4dc4e586 。
- `mpx.svg`：SIG MPX 战术配件版的简化侧面示意线稿；外形参考已入库 `addons/community_weapons/mpx_tactical.glb`，本体原作者 michalstk11，来源 https://sketchfab.com/3d-models/sig-sauer-mpx-d6e0a8020a7b4a9a876787ec91290022 。配件作者为 Sambit_Raut（EXPS3）、elitej1gaming（前握把）、D_U（AN/PEQ15）、mbvisuals1（M600DF）；各自完整 URL 见 `addons/community_weapons/ATTRIBUTION.md`。
- 图标绘制：本项目 Codex，2026-11-11；人工绘制 SVG 轮廓和主要结构，采用同一青蓝线稿样式与 `120×58` 视区，未复制源贴图或源网格，也未复用雷械图标。此两图不是前文 Blender Freestyle 提取流程的产物。
- 源模型及配件许可证：[CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/)；本项目此两张衍生示意图同按 CC-BY 4.0 提供。游戏内标题页“资产署名”已列以上原作者、来源与许可。
